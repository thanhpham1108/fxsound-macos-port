// Restores the prior system output if the Ventura audio app stops unexpectedly.
// AGPL-3.0-or-later.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <signal.h>
#include <unistd.h>

static AudioObjectID findDevice(const char* uid) {
    AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes)!=noErr)return 0;
    NSMutableData* list=[NSMutableData dataWithLength:bytes];
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,list.mutableBytes)!=noErr)return 0;
    const auto* ids=static_cast<const AudioObjectID*>(list.bytes);
    for(size_t i=0;i<bytes/sizeof(AudioObjectID);++i){
        CFStringRef value=nullptr;UInt32 size=sizeof(value);
        auto p=AudioObjectPropertyAddress{kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        if(AudioObjectGetPropertyData(ids[i],&p,0,nullptr,&size,&value)!=noErr||!value)continue;
        const bool match=std::strcmp([(__bridge NSString*)value UTF8String],uid)==0;
        CFRelease(value);
        if(match)return ids[i];
    }
    return 0;
}

static AudioObjectID fallbackOutput() {
    AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes)!=noErr)return 0;
    NSMutableData* list=[NSMutableData dataWithLength:bytes];
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,list.mutableBytes)!=noErr)return 0;
    const auto* ids=static_cast<const AudioObjectID*>(list.bytes);
    for(size_t i=0;i<bytes/sizeof(AudioObjectID);++i){
        UInt32 type=0,size=sizeof(type);
        auto transport=AudioObjectPropertyAddress{kAudioDevicePropertyTransportType,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        if(AudioObjectGetPropertyData(ids[i],&transport,0,nullptr,&size,&type)!=noErr||type==kAudioDeviceTransportTypeVirtual||type==kAudioDeviceTransportTypeAggregate)continue;
        auto streams=AudioObjectPropertyAddress{kAudioDevicePropertyStreams,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};
        size=0;
        if(AudioObjectGetPropertyDataSize(ids[i],&streams,0,nullptr,&size)==noErr&&size>=sizeof(AudioObjectID))return ids[i];
    }
    return 0;
}

int main(int argc,const char* argv[]) {
    @autoreleasepool {
        if(argc!=4)return 2;
        const pid_t parent=static_cast<pid_t>(std::strtol(argv[1],nullptr,10));
        if(parent<=1)return 2;
        const AudioObjectID virtualDevice=findDevice(argv[2]);
        AudioObjectID previousDevice=findDevice(argv[3]);
        if(!previousDevice)previousDevice=fallbackOutput();
        if(!virtualDevice||!previousDevice||virtualDevice==previousDevice)return 2;
        AudioObjectPropertyAddress a{kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        for(;;){
            AudioObjectID current=0;UInt32 bytes=sizeof(current);
            if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,&current)!=noErr)return 1;
            if(kill(parent,0)!=0 && errno==ESRCH){
                if(current==virtualDevice){
                    AudioObjectSetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,sizeof(previousDevice),&previousDevice);
                }
                return 0;
            }
            if(current!=virtualDevice){
                // Wait briefly for the app to route to BlackHole, then exit after normal restoration.
                static unsigned idle=0;
                if(++idle>25)return 0;
            }else{
                // A changed output after this point belongs to the user or normal shutdown.
                break;
            }
            usleep(100000);
        }
        for(;;){
            AudioObjectID current=0;UInt32 bytes=sizeof(current);
            if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,&current)!=noErr)return 1;
            if(current!=virtualDevice)return 0;
            if(kill(parent,0)!=0 && errno==ESRCH){
                AudioObjectSetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,sizeof(previousDevice),&previousDevice);
                return 0;
            }
            usleep(100000);
        }
    }
}
