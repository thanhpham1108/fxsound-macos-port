// macOS 13 system-audio backend using an independently installed BlackHole 2ch.
// AGPL-3.0-or-later.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include "FxAudioBridge.hpp"
#include "LegacyRing.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <spawn.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char** environ;
namespace {
AudioObjectPropertyAddress addr(AudioObjectPropertySelector selector,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal){return {selector,scope,kAudioObjectPropertyElementMain};}
bool get(AudioObjectID id,AudioObjectPropertySelector selector,void* data,UInt32& size,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal){auto a=addr(selector,scope);return AudioObjectGetPropertyData(id,&a,0,nullptr,&size,data)==noErr;}
std::vector<AudioObjectID> deviceIDs(){
    auto a=addr(kAudioHardwarePropertyDevices);UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes)!=noErr||bytes%sizeof(AudioObjectID))return {};
    std::vector<AudioObjectID> ids(bytes/sizeof(AudioObjectID));
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,ids.data())!=noErr)return {};
    return ids;
}
std::string uid(AudioObjectID id){CFStringRef value=nullptr;UInt32 size=sizeof(value);if(!get(id,kAudioDevicePropertyDeviceUID,&value,size)||!value)return {};std::string result=[(__bridge NSString*)value UTF8String];CFRelease(value);return result;}
std::string name(AudioObjectID id){CFStringRef value=nullptr;UInt32 size=sizeof(value);if(!get(id,kAudioObjectPropertyName,&value,size)||!value)return {};std::string result=[(__bridge NSString*)value UTF8String];CFRelease(value);return result;}
bool hasStream(AudioObjectID id,AudioObjectPropertyScope scope){auto a=addr(kAudioDevicePropertyStreams,scope);UInt32 bytes=0;return AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&bytes)==noErr&&bytes>=sizeof(AudioObjectID);}
bool physical(AudioObjectID id){UInt32 type=0,size=sizeof(type);return get(id,kAudioDevicePropertyTransportType,&type,size)&&type!=kAudioDeviceTransportTypeVirtual&&type!=kAudioDeviceTransportTypeAggregate&&hasStream(id,kAudioDevicePropertyScopeOutput);}
AudioObjectID blackHole(){for(auto id:deviceIDs())if(name(id)=="BlackHole 2ch"&&hasStream(id,kAudioDevicePropertyScopeInput)&&hasStream(id,kAudioDevicePropertyScopeOutput))return id;return 0;}
AudioObjectID defaultOutput(){AudioObjectID id=0;UInt32 size=sizeof(id);get(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,&id,size);return id;}
bool setDefault(AudioObjectID id){auto a=addr(kAudioHardwarePropertyDefaultOutputDevice);return AudioObjectSetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,sizeof(id),&id)==noErr;}
bool format(AudioObjectID id,AudioObjectPropertyScope scope,AudioStreamBasicDescription& f){
    auto a=addr(kAudioDevicePropertyStreams,scope);UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&bytes)!=noErr||bytes<sizeof(AudioObjectID))return false;
    std::vector<AudioObjectID> streams(bytes/sizeof(AudioObjectID));
    if(AudioObjectGetPropertyData(id,&a,0,nullptr,&bytes,streams.data())!=noErr)return false;
    UInt32 size=sizeof(f);return get(streams[0],kAudioStreamPropertyVirtualFormat,&f,size);
}
bool stereoFloat(const AudioStreamBasicDescription& f){return f.mFormatID==kAudioFormatLinearPCM&&f.mChannelsPerFrame==2&&f.mBitsPerChannel==32&&(f.mFormatFlags&kAudioFormatFlagIsFloat)&&f.mSampleRate>=44100&&f.mSampleRate<=48000;}
std::string lastPhysicalUID;
struct Engine {
    AudioObjectID virtualDevice=0, output=0, original=0;
    AudioDeviceIOProcID inputProc=nullptr, outputProc=nullptr;
    bool inputStarted=false,outputStarted=false,routed=false;
    double inputRate=48000,outputRate=48000;
    fxport::Settings settings;
    fxport::JsDsp dsp;
    fxport::LegacyRing ring;
    std::array<float,2048> inputWork{},outputWork{};
    std::atomic<bool> changed{false},routeLost{false};
    std::atomic<uint64_t> callbacks{0},badLayouts{0},dspFailures{0},nonFinite{0};
    static OSStatus listener(AudioObjectID,UInt32,const AudioObjectPropertyAddress*,void* context) noexcept {static_cast<Engine*>(context)->changed.store(true,std::memory_order_relaxed);return noErr;}
    static OSStatus input(AudioObjectID,const AudioTimeStamp*,const AudioBufferList* in,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void* context) noexcept {
        auto& e=*static_cast<Engine*>(context);
        if(!in||!in->mNumberBuffers||!in->mBuffers[0].mData)return noErr;
        const bool interleaved=in->mNumberBuffers==1&&in->mBuffers[0].mNumberChannels==2;
        const bool planar=in->mNumberBuffers==2&&in->mBuffers[0].mNumberChannels==1&&in->mBuffers[1].mNumberChannels==1&&in->mBuffers[1].mData;
        if(!interleaved&&!planar){e.badLayouts.fetch_add(1);return noErr;}
        size_t frames=in->mBuffers[0].mDataByteSize/(interleaved?8:4);
        if(planar)frames=std::min(frames,size_t(in->mBuffers[1].mDataByteSize/4));
        const auto* a=static_cast<const float*>(in->mBuffers[0].mData);
        const auto* b=planar?static_cast<const float*>(in->mBuffers[1].mData):nullptr;
        for(size_t offset=0;offset<frames;offset+=1024){
            const auto count=std::min<size_t>(1024,frames-offset);
            for(size_t i=0;i<count;++i){e.inputWork[2*i]=a[(offset+i)*(interleaved?2:1)];e.inputWork[2*i+1]=planar?b[offset+i]:a[(offset+i)*2+1];}
            if(!e.dsp.process(e.inputWork.data(),count)){e.dspFailures.fetch_add(1);continue;}
            bool valid=true;for(size_t i=0;i<count*2;++i)if(!std::isfinite(e.inputWork[i])){valid=false;break;}
            if(!valid){e.nonFinite.fetch_add(1);continue;}
            e.ring.push(e.inputWork.data(),count);
        }
        e.callbacks.fetch_add(1);return noErr;
    }
    static OSStatus playback(AudioObjectID,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList* out,const AudioTimeStamp*,void* context) noexcept {
        auto& e=*static_cast<Engine*>(context);if(!out||!out->mNumberBuffers||!out->mBuffers[0].mData)return noErr;
        const bool interleaved=out->mNumberBuffers==1&&out->mBuffers[0].mNumberChannels==2;
        const bool planar=out->mNumberBuffers==2&&out->mBuffers[0].mNumberChannels==1&&out->mBuffers[1].mNumberChannels==1&&out->mBuffers[1].mData;
        if(!interleaved&&!planar){e.badLayouts.fetch_add(1);return noErr;}
        size_t frames=out->mBuffers[0].mDataByteSize/(interleaved?8:4);
        if(planar)frames=std::min(frames,size_t(out->mBuffers[1].mDataByteSize/4));
        auto* a=static_cast<float*>(out->mBuffers[0].mData);
        auto* b=planar?static_cast<float*>(out->mBuffers[1].mData):nullptr;
        for(size_t offset=0;offset<frames;offset+=1024){
            const size_t count=std::min<size_t>(1024,frames-offset);
            e.ring.pull(e.outputWork.data(),count,e.inputRate,e.outputRate);
            for(size_t i=0;i<count;++i){a[(offset+i)*(interleaved?2:1)]=e.outputWork[2*i];if(planar)b[offset+i]=e.outputWork[2*i+1];else a[(offset+i)*2+1]=e.outputWork[2*i+1];}
        }
        return noErr;
    }
    bool launchGuard(){
        NSString* helper=[[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"FxRouteGuard"];
        const auto originalUID=uid(original),virtualUID=uid(virtualDevice);
        if(originalUID.empty()||virtualUID.empty())return false;
        const std::string parent=std::to_string(getpid());
        const char* argv[]={helper.fileSystemRepresentation,parent.c_str(),virtualUID.c_str(),originalUID.c_str(),nullptr};
        pid_t child=0;
        if(posix_spawn(&child,helper.fileSystemRepresentation,nullptr,nullptr,const_cast<char* const*>(argv),environ)!=0)return false;
        std::thread([child]{int status=0;waitpid(child,&status,0);}).detach();return true;
    }
    bool start(const std::string& selected,std::string& error){
        virtualDevice=blackHole();if(!virtualDevice){error="Install BlackHole 2ch to enable Ventura audio";return false;}
        original=defaultOutput();
        if(selected.empty()){
            output=physical(original)?original:0;
            if(!output)for(auto id:deviceIDs())if(physical(id)&&uid(id)==lastPhysicalUID){output=id;break;}
        }else for(auto id:deviceIDs())if(physical(id)&&uid(id)==selected){output=id;break;}
        if(!output)for(auto id:deviceIDs())if(physical(id)){output=id;break;}
        if(!output){error="No physical speakers or headphones found";return false;}
        if(!physical(original))original=output;
        lastPhysicalUID=uid(output);
        AudioStreamBasicDescription inputFormat{},outputFormat{};
        if(!format(virtualDevice,kAudioDevicePropertyScopeInput,inputFormat)||!format(output,kAudioDevicePropertyScopeOutput,outputFormat)||!stereoFloat(inputFormat)||!stereoFloat(outputFormat)){
            error="Ventura routing requires stereo float audio at 44.1 or 48 kHz";return false;
        }
        inputRate=inputFormat.mSampleRate;outputRate=outputFormat.mSampleRate;
        NSString* base=[[NSBundle mainBundle] resourcePath];
        if(!dsp.start(inputRate,settings,[[base stringByAppendingPathComponent:@"dsp"] UTF8String])||!dsp.warmup(64)){
            error="Could not initialize FxSound DSP";return false;
        }
        if(AudioDeviceCreateIOProcID(virtualDevice,input,this,&inputProc)!=noErr||AudioDeviceCreateIOProcID(output,playback,this,&outputProc)!=noErr){error="Could not open audio devices";return false;}
        if(!launchGuard()){error="Could not start output recovery helper";return false;}
        if(!setDefault(virtualDevice)){error="Could not route system output to BlackHole";return false;}
        routed=true;
        if(AudioDeviceStart(output,outputProc)!=noErr){error="Could not start physical output";return false;}outputStarted=true;
        if(AudioDeviceStart(virtualDevice,inputProc)!=noErr){error="Could not start BlackHole input";return false;}inputStarted=true;
        auto a=addr(kAudioHardwarePropertyDefaultOutputDevice);
        AudioObjectAddPropertyListener(kAudioObjectSystemObject,&a,listener,this);
        a=addr(kAudioDevicePropertyDeviceIsAlive);AudioObjectAddPropertyListener(output,&a,listener,this);
        NSLog(@"Ventura routing: BlackHole %s -> %s (%.0f -> %.0f Hz)",uid(virtualDevice).c_str(),uid(output).c_str(),inputRate,outputRate);
        return true;
    }
    bool outputChanged(){
        if(!changed.exchange(false))return false;
        if(defaultOutput()!=virtualDevice){routeLost.store(true);return true;}
        UInt32 alive=0,size=sizeof(alive);return !get(output,kAudioDevicePropertyDeviceIsAlive,&alive,size)||!alive;
    }
    void stop(){
        if(routed&&defaultOutput()==virtualDevice){
            AudioObjectID restore=physical(original)?original:0;
            if(!restore)for(auto id:deviceIDs())if(physical(id)){restore=id;break;}
            if(restore)setDefault(restore);
        }
        routed=false;
        auto a=addr(kAudioHardwarePropertyDefaultOutputDevice);AudioObjectRemovePropertyListener(kAudioObjectSystemObject,&a,listener,this);
        a=addr(kAudioDevicePropertyDeviceIsAlive);if(output)AudioObjectRemovePropertyListener(output,&a,listener,this);
        if(inputStarted)AudioDeviceStop(virtualDevice,inputProc);inputStarted=false;
        if(outputStarted)AudioDeviceStop(output,outputProc);outputStarted=false;
        if(inputProc)AudioDeviceDestroyIOProcID(virtualDevice,inputProc);inputProc=nullptr;
        if(outputProc)AudioDeviceDestroyIOProcID(output,outputProc);outputProc=nullptr;
        if(callbacks.load())NSLog(@"Ventura callbacks=%llu bad_layouts=%llu dsp_failures=%llu non_finite=%llu ring_underruns=%llu ring_overruns=%llu",callbacks.load(),badLayouts.load(),dspFailures.load(),nonFinite.load(),ring.underruns(),ring.overruns());
    }
    ~Engine(){stop();}
};
}
namespace fxport {
bool legacyDriverReady(std::string& error){if(blackHole())return true;error="BlackHole 2ch is required on macOS 13";return false;}
std::vector<OutputDevice> outputDevices(){
    const auto current=defaultOutput();std::vector<OutputDevice> result;
    for(auto id:deviceIDs())if(physical(id))result.push_back({uid(id),name(id),id==current||(!physical(current)&&uid(id)==lastPhysicalUID)});
    return result;
}
AudioHandle startAudio(const Settings& settings,const std::string& selected,std::string& error){
    auto* engine=new Engine();engine->settings=settings;
    if(!engine->start(selected,error)){delete engine;return nullptr;}return engine;
}
void stopAudio(AudioHandle handle){delete static_cast<Engine*>(handle);}
bool outputChanged(AudioHandle handle){return handle&&static_cast<Engine*>(handle)->outputChanged();}
bool legacyRouteLost(AudioHandle handle){return handle&&static_cast<Engine*>(handle)->routeLost.load();}
}
