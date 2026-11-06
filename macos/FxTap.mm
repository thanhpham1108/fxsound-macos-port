// FxSound macOS routing prototype. AGPL-3.0-or-later.
// Core Audio setup follows Apple's Capturing System Audio With Core Audio Taps sample.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include "FxEq.hpp"
#include "FxJsDsp.hpp"
#include "FxPreset.hpp"
#include "FxAudioBridge.hpp"
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <memory>
#include <vector>
#include <signal.h>
#include <unistd.h>

static AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) { return {selector, scope, kAudioObjectPropertyElementMain}; }
static bool property(AudioObjectID object, AudioObjectPropertySelector selector, void* value, UInt32& size, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal, UInt32 qualifierSize=0, const void* qualifier=nullptr) {
    auto a=address(selector,scope);
    return AudioObjectGetPropertyData(object,&a,qualifierSize,qualifier,&size,value)==noErr;
}
static bool streamFormat(AudioObjectID device, AudioObjectPropertyScope scope, AudioStreamBasicDescription& format) {
    auto a=address(kAudioDevicePropertyStreams,scope); UInt32 size=0;
    if(AudioObjectGetPropertyDataSize(device,&a,0,nullptr,&size)!=noErr || size!=sizeof(AudioObjectID)) return false;
    AudioObjectID stream=0;
    if(!property(device,kAudioDevicePropertyStreams,&stream,size,scope))return false;
    size=sizeof(format); return property(stream,kAudioStreamPropertyVirtualFormat,&format,size);
}
static bool stereoFloat(const AudioStreamBasicDescription& f) {
    return f.mFormatID==kAudioFormatLinearPCM && f.mChannelsPerFrame==2 && f.mBitsPerChannel==32 &&
        (f.mFormatFlags & (kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked))==(kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked) &&
        !(f.mFormatFlags & kAudioFormatFlagIsNonInterleaved) && f.mBytesPerFrame==8 && f.mFramesPerPacket==1 &&
        (f.mSampleRate==44100 || f.mSampleRate==48000);
}
static NSString* deviceUID(AudioObjectID device) {
    CFStringRef value=nullptr; UInt32 size=sizeof(value);
    if(!property(device,kAudioDevicePropertyDeviceUID,&value,size)||!value)return nil;
    return (__bridge_transfer NSString*)value;
}
static bool outputDeviceIDs(std::vector<AudioObjectID>& devices) {
    auto a=address(kAudioHardwarePropertyDevices);UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes)!=noErr||bytes%sizeof(AudioObjectID))return false;
    devices.resize(bytes/sizeof(AudioObjectID));
    return AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,devices.data())==noErr;
}
static bool physicalOutput(AudioObjectID device) {
    UInt32 transport=0,size=sizeof(transport);
    if(!property(device,kAudioDevicePropertyTransportType,&transport,size))return false;
    if(transport==kAudioDeviceTransportTypeVirtual || transport==kAudioDeviceTransportTypeAggregate)return false;
    auto a=address(kAudioDevicePropertyStreams,kAudioDevicePropertyScopeOutput);size=0;
    return AudioObjectGetPropertyDataSize(device,&a,0,nullptr,&size)==noErr && size>=sizeof(AudioObjectID);
}
static void listOutputs() {
    std::vector<AudioObjectID> devices;
    if(!outputDeviceIDs(devices)) {fprintf(stderr,"Cannot enumerate outputs\n");return;}
    for(auto id:devices) if(physicalOutput(id)) {
        CFStringRef name=nullptr;UInt32 size=sizeof(name);
        if(!property(id,kAudioObjectPropertyName,&name,size))continue;
        NSString* uid=deviceUID(id);
        printf("%s\t%s\n",uid.UTF8String,((__bridge NSString*)name).UTF8String);
        if(name)CFRelease(name);
    }
}
struct Engine {
    AudioObjectID tap=0, aggregate=0;
    AudioObjectID physical=0;
    AudioDeviceIOProcID proc=nullptr;
    std::unique_ptr<fxport::Processor> dsp;
    std::unique_ptr<fxport::JsDsp> fullDsp;
    fxport::Settings settings;
    bool eqOnly=false;
    double dspSampleRate=48000;
    std::atomic<unsigned long> callbacks{0}, badLayouts{0}, activeInputFrames{0}, changedFrames{0}, clippedSamples{0};
    std::atomic<unsigned long> dspFailures{0}, nonFiniteBlocks{0}, callbackOverruns{0}, maxCallbackUs{0};
    std::atomic<bool> dspNeedsRestart{false};
    bool dryBypass=false;
    bool started=false;
    bool statsLogged=false;
    bool usesDefault=true;
    bool listenDefault=false,listenAlive=false,listenRate=false;
    std::atomic<bool> deviceChanged{false};
    static OSStatus changed(AudioObjectID,UInt32,const AudioObjectPropertyAddress*,void* context) noexcept {
        static_cast<Engine*>(context)->deviceChanged.store(true,std::memory_order_relaxed);return noErr;
    }
    bool meaningfulDeviceChange() {
        if(!deviceChanged.exchange(false,std::memory_order_relaxed))return false;
        UInt32 alive=0,size=sizeof(alive);
        if(!property(physical,kAudioDevicePropertyDeviceIsAlive,&alive,size)||!alive){NSLog(@"Device change: selected output is unavailable");return true;}
        Float64 rate=0;size=sizeof(rate);
        if(!property(physical,kAudioDevicePropertyNominalSampleRate,&rate,size)||std::fabs(rate-dspSampleRate)>0.5){NSLog(@"Device change: rate %.0f -> %.0f",dspSampleRate,rate);return true;}
        if(usesDefault){
            AudioObjectID current=0;size=sizeof(current);
            if(!property(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,&current,size)||current!=physical){NSLog(@"Device change: default %u -> %u",physical,current);return true;}
        }
        return false;
    }
    static OSStatus io(AudioObjectID, const AudioTimeStamp*, const AudioBufferList* in, const AudioTimeStamp*, AudioBufferList* out, const AudioTimeStamp*, void* context) noexcept {
        auto& engine=*static_cast<Engine*>(context); engine.callbacks.fetch_add(1,std::memory_order_relaxed);
        const auto callbackStart=std::chrono::steady_clock::now();
        if(!out)return noErr;
        for(UInt32 i=0;i<out->mNumberBuffers;++i) if(out->mBuffers[i].mData) std::memset(out->mBuffers[i].mData,0,out->mBuffers[i].mDataByteSize);
        if(!in || in->mNumberBuffers!=1 || out->mNumberBuffers!=1 || !in->mBuffers[0].mData || !out->mBuffers[0].mData ||
           in->mBuffers[0].mNumberChannels!=2 || out->mBuffers[0].mNumberChannels!=2 ||
           in->mBuffers[0].mDataByteSize!=out->mBuffers[0].mDataByteSize || in->mBuffers[0].mDataByteSize%8) {
            engine.badLayouts.fetch_add(1,std::memory_order_relaxed);return noErr;
        }
        const size_t bytes=in->mBuffers[0].mDataByteSize;
        std::memcpy(out->mBuffers[0].mData,in->mBuffers[0].mData,bytes);
        if(!engine.dryBypass) {
            bool processed=engine.eqOnly
                ? engine.dsp->process(static_cast<float*>(out->mBuffers[0].mData),bytes/8,false)
                : engine.fullDsp->process(static_cast<float*>(out->mBuffers[0].mData),bytes/8);
            if(processed){
                const float* result=static_cast<const float*>(out->mBuffers[0].mData);
                for(size_t i=0;i<bytes/sizeof(float);++i){
                    if(!std::isfinite(result[i])){
                        processed=false;
                        engine.nonFiniteBlocks.fetch_add(1,std::memory_order_relaxed);
                        engine.dspNeedsRestart.store(true,std::memory_order_relaxed);
                        break;
                    }
                }
            }
            if(!processed){
                std::memcpy(out->mBuffers[0].mData,in->mBuffers[0].mData,bytes);
                engine.dspFailures.fetch_add(1,std::memory_order_relaxed);
            }
        }
        const float* source=static_cast<const float*>(in->mBuffers[0].mData);
        const float* result=static_cast<const float*>(out->mBuffers[0].mData);
        unsigned long active=0,changed=0,clipped=0;
        for(size_t i=0;i<bytes/8;++i){
            if(std::fabs(source[2*i])>1.e-4f||std::fabs(source[2*i+1])>1.e-4f)++active;
            if(std::fabs(source[2*i]-result[2*i])>1.e-4f||std::fabs(source[2*i+1]-result[2*i+1])>1.e-4f)++changed;
            if(std::fabs(result[2*i])>1.f)++clipped;
            if(std::fabs(result[2*i+1])>1.f)++clipped;
        }
        engine.activeInputFrames.fetch_add(active,std::memory_order_relaxed);
        engine.changedFrames.fetch_add(changed,std::memory_order_relaxed);
        engine.clippedSamples.fetch_add(clipped,std::memory_order_relaxed);
        const auto elapsed=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-callbackStart).count();
        unsigned long previous=engine.maxCallbackUs.load(std::memory_order_relaxed);
        while(static_cast<unsigned long>(elapsed)>previous && !engine.maxCallbackUs.compare_exchange_weak(previous,static_cast<unsigned long>(elapsed),std::memory_order_relaxed)){}
        const double budgetUs=1000000.0*(bytes/8)/engine.dspSampleRate;
        if(elapsed>budgetUs)engine.callbackOverruns.fetch_add(1,std::memory_order_relaxed);
        return noErr;
    }
    void stop() {
        if(listenDefault||listenAlive||listenRate){
            auto a=address(kAudioHardwarePropertyDefaultOutputDevice);
            if(listenDefault)AudioObjectRemovePropertyListener(kAudioObjectSystemObject,&a,changed,this);
            a=address(kAudioDevicePropertyDeviceIsAlive);
            if(listenAlive)AudioObjectRemovePropertyListener(physical,&a,changed,this);
            a=address(kAudioDevicePropertyNominalSampleRate);
            if(listenRate)AudioObjectRemovePropertyListener(physical,&a,changed,this);
            listenDefault=listenAlive=listenRate=false;
        }
        if(proc){if(started)AudioDeviceStop(aggregate,proc);AudioDeviceDestroyIOProcID(aggregate,proc);proc=nullptr;started=false;}
        if(aggregate){AudioHardwareDestroyAggregateDevice(aggregate);aggregate=0;}
        if(tap){AudioHardwareDestroyProcessTap(tap);tap=0;}
        dsp.reset();
        fullDsp.reset();
        if(!statsLogged && callbacks.load()){
            NSLog(@"callbacks=%lu bad_layouts=%lu dsp_failures=%lu non_finite_blocks=%lu callback_overruns=%lu max_callback_us=%lu active_input_frames=%lu changed_frames=%lu clipped_samples=%lu",
                  callbacks.load(),badLayouts.load(),dspFailures.load(),nonFiniteBlocks.load(),callbackOverruns.load(),maxCallbackUs.load(),
                  activeInputFrames.load(),changedFrames.load(),clippedSamples.load());
            statsLogged=true;
        }
    }
    ~Engine(){stop();}
    bool start(float boostDb, NSString* selectedUID) {
        AudioObjectID output=0, self=0;UInt32 size=sizeof(output);
        usesDefault=selectedUID==nil;
        if(selectedUID){
            std::vector<AudioObjectID> devices;
            if(!outputDeviceIDs(devices))return false;
            for(auto id:devices) if(physicalOutput(id)&&[selectedUID isEqualToString:deviceUID(id)]) {output=id;break;}
        } else if(!property(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,&output,size))return false;
        if(!physicalOutput(output)){
            std::vector<AudioObjectID> devices;
            if(!outputDeviceIDs(devices))return false;
            output=0;
            for(auto id:devices)if(physicalOutput(id)){output=id;break;}
            usesDefault=false;
        }
        if(!output||!physicalOutput(output)){NSLog(@"No supported physical output");return false;}
        physical=output;
        pid_t pid=getpid();size=sizeof(self);
        if(!property(kAudioObjectSystemObject,kAudioHardwarePropertyTranslatePIDToProcessObject,&self,size,kAudioObjectPropertyScopeGlobal,sizeof(pid),&pid)||!self){NSLog(@"Cannot exclude own audio process");return false;}
        NSString* uid=deviceUID(output);if(!uid)return false;
        CATapDescription* desc=[[CATapDescription alloc] initExcludingProcesses:@[@(self)] andDeviceUID:uid withStream:0];
        desc.name=@"FxSound DSP prototype";desc.privateTap=YES;desc.muteBehavior=CATapMuted;
        NSLog(@"self process=%u exclusive=%d mute=%ld tap device=%@",self,desc.exclusive,(long)desc.muteBehavior,uid);
        OSStatus err=AudioHardwareCreateProcessTap(desc,&tap);
        if(err!=noErr){NSLog(@"Create tap failed: %d",(int)err);return false;}
        CFStringRef tapUID=nullptr;size=sizeof(tapUID);
        if(!property(tap,kAudioTapPropertyUID,&tapUID,size)||!tapUID){stop();return false;}
        NSString* tuid=(__bridge_transfer NSString*)tapUID;
        NSDictionary* configuration=@{
            @(kAudioAggregateDeviceNameKey):@"FxSound DSP prototype",
            @(kAudioAggregateDeviceUIDKey):[[NSUUID UUID] UUIDString],
            @(kAudioAggregateDeviceSubDeviceListKey):@[@{@(kAudioSubDeviceUIDKey):uid}],
            @(kAudioAggregateDeviceTapListKey):@[@{@(kAudioSubTapUIDKey):tuid}],
            @(kAudioAggregateDeviceMainSubDeviceKey):uid,
            @(kAudioAggregateDeviceIsPrivateKey):@YES
        };
        err=AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)configuration,&aggregate);
        if(err!=noErr){NSLog(@"Create aggregate failed: %d",(int)err);stop();return false;}
        auto tapListAddress=address(kAudioAggregateDevicePropertyTapList);UInt32 tapListBytes=0;
        AudioObjectGetPropertyDataSize(aggregate,&tapListAddress,0,nullptr,&tapListBytes);
        AudioStreamBasicDescription tapFormat{};size=sizeof(tapFormat);
        bool tapFormatOK=property(tap,kAudioTapPropertyFormat,&tapFormat,size);
        NSLog(@"aggregate=%u tap=%u tap-list-bytes=%u tap-format=%d/%u/%.0f",aggregate,tap,tapListBytes,tapFormatOK,tapFormat.mChannelsPerFrame,tapFormat.mSampleRate);
        AudioStreamBasicDescription inputFormat{},outputFormat{};
        if(!streamFormat(aggregate,kAudioDevicePropertyScopeInput,inputFormat)||
           !streamFormat(aggregate,kAudioDevicePropertyScopeOutput,outputFormat)||
           !stereoFloat(inputFormat)||!stereoFloat(outputFormat)||inputFormat.mSampleRate!=outputFormat.mSampleRate){
            NSLog(@"Unsupported aggregate format; requires one interleaved stereo float32 input and output at 44.1/48 kHz");stop();return false;
        }
        dspSampleRate=inputFormat.mSampleRate;
        if(eqOnly)dsp=std::make_unique<fxport::Processor>((float)inputFormat.mSampleRate,std::vector<fxport::Band>{{1000.f,boostDb,1.f}});
        else {
            fullDsp=std::make_unique<fxport::JsDsp>();
            NSString* resourcePath=[[NSBundle mainBundle] resourcePath];
            std::string scriptDirectory=[[resourcePath stringByAppendingPathComponent:@"dsp"] UTF8String];
            if(!fullDsp->start(inputFormat.mSampleRate,settings,scriptDirectory)){
                NSLog(@"Full DSP initialization failed: %s",fullDsp->error().c_str());stop();return false;
            }
            if(!fullDsp->warmup(64)){NSLog(@"Full DSP warmup failed");stop();return false;}
        }
        err=AudioDeviceCreateIOProcID(aggregate,io,this,&proc);
        if(err!=noErr){NSLog(@"Create IOProc failed: %d",(int)err);stop();return false;}
        err=AudioDeviceStart(aggregate,proc);
        if(err!=noErr){NSLog(@"Start failed: %d",(int)err);stop();return false;}
        started=true;
        auto defaultAddress=address(kAudioHardwarePropertyDefaultOutputDevice);
        auto aliveAddress=address(kAudioDevicePropertyDeviceIsAlive);
        auto rateAddress=address(kAudioDevicePropertyNominalSampleRate);
        listenDefault=AudioObjectAddPropertyListener(kAudioObjectSystemObject,&defaultAddress,changed,this)==noErr;
        listenAlive=AudioObjectAddPropertyListener(physical,&aliveAddress,changed,this)==noErr;
        listenRate=AudioObjectAddPropertyListener(physical,&rateAddress,changed,this)==noErr;
        if(!listenDefault||!listenAlive||!listenRate){
            NSLog(@"Could not monitor output changes");stop();return false;
        }
        NSLog(@"Running at %.0f Hz, output %@",inputFormat.mSampleRate,uid);return true;
    }
};
namespace fxport {
std::vector<OutputDevice> outputDevices() {
    std::vector<OutputDevice> result;
    std::vector<AudioObjectID> devices;
    if(!outputDeviceIDs(devices))return result;
    AudioObjectID defaultOutput=0;UInt32 defaultSize=sizeof(defaultOutput);
    property(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,&defaultOutput,defaultSize);
    for(auto id:devices)if(physicalOutput(id)){
        CFStringRef name=nullptr;UInt32 size=sizeof(name);
        if(!property(id,kAudioObjectPropertyName,&name,size)||!name)continue;
        NSString* uid=deviceUID(id);
        if(uid)result.push_back({uid.UTF8String,((__bridge NSString*)name).UTF8String,id==defaultOutput});
        CFRelease(name);
    }
    return result;
}
AudioHandle startAudio(const Settings& settings, const std::string& selectedUID, std::string& error) {
    auto* engine=new Engine();
    engine->settings=settings;
    NSString* uid=selectedUID.empty()?nil:[NSString stringWithUTF8String:selectedUID.c_str()];
    if(!engine->start(6.f,uid)){error="Could not start the selected output. Check System Audio Recording permission and device format.";delete engine;return nullptr;}
    return engine;
}
void stopAudio(AudioHandle handle){delete static_cast<Engine*>(handle);}
bool outputChanged(AudioHandle handle){
    if(!handle)return false;
    auto* engine=static_cast<Engine*>(handle);
    if(engine->dspNeedsRestart.exchange(false,std::memory_order_relaxed)){
        NSLog(@"DSP produced non-finite audio; restarting processing state");
        return true;
    }
    return engine->meaningfulDeviceChange();
}
}
static volatile sig_atomic_t quitFlag=0;
static void quitHandler(int){quitFlag=1;}
#ifndef FXTAP_NO_MAIN
int main(int argc,const char* argv[]) {
    @autoreleasepool {
        if(argc==2 && !strcmp(argv[1],"--list-devices")){listOutputs();return 0;}
        auto resourceDirectory=std::string([[[NSBundle mainBundle] resourcePath] UTF8String]);
        auto presets=fxport::loadFactoryPresets(resourceDirectory);
        if(argc==2 && !strcmp(argv[1],"--list-presets")){
            for(const auto& preset:presets)printf("%s\n",preset.name.c_str());
            return 0;
        }
        bool bypass=false,eqOnly=false;NSString* selectedUID=nil;
        fxport::Settings settings;
        if(argc<2 || strcmp(argv[1],"--run")){fprintf(stderr,"usage: FxTap --list-devices | --run [--bypass] [--eq-only] [--device UID] [--effect name value] [--eq-band index gain]\n");return 2;}
        for(int i=2;i<argc;++i){
            if(!strcmp(argv[i],"--bypass"))bypass=true;
            else if(!strcmp(argv[i],"--eq-only"))eqOnly=true;
            else if(!strcmp(argv[i],"--preset") && i+1<argc){
                const char* name=argv[++i];bool found=false;
                for(const auto& preset:presets)if(!strcmp(name,preset.name.c_str())){settings=preset.settings;found=true;break;}
                if(!found){fprintf(stderr,"unknown preset: %s\n",name);return 2;}
            }
            else if(!strcmp(argv[i],"--device") && i+1<argc)selectedUID=[NSString stringWithUTF8String:argv[++i]];
            else if(!strcmp(argv[i],"--effect") && i+2<argc){
                const char* name=argv[++i]; char* end=nullptr;float value=strtof(argv[++i],&end);
                if(!end||*end||value<0||value>10){fprintf(stderr,"effect value must be 0..10\n");return 2;}
                if(!strcmp(name,"clarity"))settings.fidelity=value;
                else if(!strcmp(name,"ambience"))settings.ambience=value;
                else if(!strcmp(name,"surround"))settings.surround=value;
                else if(!strcmp(name,"dynamic"))settings.dynamicBoost=value;
                else if(!strcmp(name,"bass"))settings.bass=value;
                else {fprintf(stderr,"unknown effect\n");return 2;}
            }
            else if(!strcmp(argv[i],"--eq-band") && i+2<argc){
                int band=atoi(argv[++i]);float gain=strtof(argv[++i],nullptr);
                if(band<0||band>=10||gain< -20||gain>20){fprintf(stderr,"invalid EQ band\n");return 2;}
                settings.gains[band]=gain;
            }
            else if(!strcmp(argv[i],"--eq-frequency") && i+2<argc){
                int band=atoi(argv[++i]);float frequency=strtof(argv[++i],nullptr);
                if(band<0||band>=10||frequency<20||frequency>20000){fprintf(stderr,"invalid EQ frequency\n");return 2;}
                settings.freqs[band]=frequency;
            }
            else {fprintf(stderr,"invalid option\n");return 2;}
        }
        signal(SIGINT,quitHandler);signal(SIGTERM,quitHandler);
        Engine engine;
        engine.dryBypass=bypass;
        engine.eqOnly=eqOnly;
        engine.settings=settings;
        if(!engine.start(6.f,selectedUID))return 1;
        bool changed=false;
        while(!quitFlag && !(changed=engine.meaningfulDeviceChange())) { @autoreleasepool { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; } }
        if(changed)NSLog(@"Output device or sample rate changed; stopping for safe restart");
    }
    return 0;
}
#endif
