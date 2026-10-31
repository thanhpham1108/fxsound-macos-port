// Test helper for the user's selected Mac output. AGPL-3.0-or-later.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include <unistd.h>
#include <vector>
#include <cstdio>

static AudioObjectPropertyAddress addr(AudioObjectPropertySelector selector) {return {selector,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};}
int main(){
    AudioObjectID device=0;UInt32 bytes=sizeof(device);auto property=addr(kAudioHardwarePropertyDefaultOutputDevice);
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&property,0,nullptr,&bytes,&device)!=noErr||!device)return 1;
    property=addr(kAudioDevicePropertyNominalSampleRate);Float64 original=0;bytes=sizeof(original);
    if(AudioObjectGetPropertyData(device,&property,0,nullptr,&bytes,&original)!=noErr)return 1;
    Boolean writable=false;
    if(AudioObjectIsPropertySettable(device,&property,&writable)!=noErr||!writable){printf("rate read-only: %.0f\n",original);return 3;}
    Float64 target=(original==48000)?44100:48000;
    auto rangesAddress=addr(kAudioDevicePropertyAvailableNominalSampleRates);UInt32 rangeBytes=0;
    if(AudioObjectGetPropertyDataSize(device,&rangesAddress,0,nullptr,&rangeBytes)!=noErr||rangeBytes%sizeof(AudioValueRange))return 1;
    std::vector<AudioValueRange> ranges(rangeBytes/sizeof(AudioValueRange));
    if(AudioObjectGetPropertyData(device,&rangesAddress,0,nullptr,&rangeBytes,ranges.data())!=noErr)return 1;
    bool supported=false;for(auto r:ranges) if(r.mMinimum<=target&&target<=r.mMaximum)supported=true;
    if(!supported){printf("target rate %.0f unsupported; left %.0f unchanged\n",target,original);return 3;}
    struct Restore {AudioObjectID id;AudioObjectPropertyAddress p;Float64 rate;~Restore(){UInt32 n=sizeof(rate);OSStatus e=AudioObjectSetPropertyData(id,&p,0,nullptr,n,&rate);printf("restored %.0f status=%d\n",rate,(int)e);}} restore{device,property,original};
    bytes=sizeof(target);OSStatus error=AudioObjectSetPropertyData(device,&property,0,nullptr,bytes,&target);
    printf("changed %.0f to %.0f status=%d\n",original,target,(int)error);
    if(error!=noErr)return 1;
    sleep(3);
    return 0;
}
