#import <Foundation/Foundation.h>
#include "FxPreset.hpp"

namespace fxport {
static float number(NSDictionary* source, NSString* key, float fallback=0) {
    id value=source[key];
    return [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : fallback;
}
std::vector<NamedPreset> loadFactoryPresets(const std::string& resourceDirectory) {
    NSString* base=[NSString stringWithUTF8String:resourceDirectory.c_str()];
    NSString* path=[base stringByAppendingPathComponent:@"presets/factory.json"];
    NSData* data=[NSData dataWithContentsOfFile:path];
    if(!data)return {};
    id parsed=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![parsed isKindOfClass:[NSArray class]])return {};
    std::vector<NamedPreset> result;
    for(id item in (NSArray*)parsed){
        if(![item isKindOfClass:[NSDictionary class]])continue;
        NSDictionary* entry=(NSDictionary*)item;
        NSString* title=entry[@"name"];
        NSArray* gains=entry[@"gains"];
        NSArray* freqs=entry[@"freqs"];
        if(![title isKindOfClass:[NSString class]]||![gains isKindOfClass:[NSArray class]]||
           ![freqs isKindOfClass:[NSArray class]]||gains.count!=10||freqs.count!=10)continue;
        NamedPreset preset;
        preset.name=title.UTF8String;
        preset.settings.power=number(entry,@"power",1)!=0;
        preset.settings.eq=number(entry,@"eq",1)!=0;
        for(int i=0;i<10;++i){preset.settings.gains[i]=[gains[i] floatValue];preset.settings.freqs[i]=[freqs[i] floatValue];}
        preset.settings.fidelity=number(entry,@"fidelity");
        preset.settings.ambience=number(entry,@"ambience");
        preset.settings.surround=number(entry,@"surround");
        preset.settings.dynamicBoost=number(entry,@"dynamicBoost");
        preset.settings.bass=number(entry,@"bass");
        result.push_back(std::move(preset));
    }
    return result;
}
}
