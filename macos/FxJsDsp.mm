// JavaScriptCore host for FxSound's golden-tested JavaScript DSP port.
// AGPL-3.0-or-later. Used while the native C/C++ stages are being ported.
#import <Foundation/Foundation.h>
#include <JavaScriptCore/JavaScriptCore.h>
#include "FxJsDsp.hpp"
#include <cstring>
#include <vector>

namespace fxport {
struct JsDsp::Impl {
    JSGlobalContextRef ctx = nullptr;
    JSObjectRef buffer = nullptr;
    JSObjectRef processor = nullptr;
    JSObjectRef process = nullptr;
    std::vector<float> samples;
    static constexpr size_t maxFrames = 8192;
    ~Impl() {
        if (ctx) {
            if (buffer) JSValueUnprotect(ctx, buffer);
            if (processor) JSValueUnprotect(ctx, processor);
            JSGlobalContextRelease(ctx);
        }
    }
};
static void retainExternalBytes(void*, void*) {}

static std::string exceptionText(JSContextRef ctx, JSValueRef ex) {
    if (!ex) return "unknown JavaScriptCore failure";
    JSStringRef value = JSValueToStringCopy(ctx, ex, nullptr);
    if (!value) return "cannot format JavaScriptCore exception";
    std::vector<char> text(JSStringGetMaximumUTF8CStringSize(value));
    JSStringGetUTF8CString(value, text.data(), text.size());
    JSStringRelease(value);
    return text.data();
}
static JSValueRef property(JSContextRef ctx, JSObjectRef object, const char* name) {
    JSStringRef key = JSStringCreateWithUTF8CString(name);
    JSValueRef value = JSObjectGetProperty(ctx, object, key, nullptr);
    JSStringRelease(key);
    return value;
}

JsDsp::JsDsp() = default;
JsDsp::~JsDsp() = default;

bool JsDsp::start(double sampleRate, const Settings& s, const std::string& directory) {
    impl_.reset(); error_.clear();
    auto engine = std::make_unique<Impl>();
    engine->samples.resize(Impl::maxFrames * 2);
    engine->ctx = JSGlobalContextCreate(nullptr);
    if (!engine->ctx) { error_ = "Cannot create JavaScriptCore context"; return false; }
    JSValueRef exception = nullptr;
    engine->buffer = JSObjectMakeTypedArrayWithBytesNoCopy(engine->ctx, kJSTypedArrayTypeFloat32Array,
        engine->samples.data(), engine->samples.size() * sizeof(float), retainExternalBytes, nullptr, &exception);
    if (!engine->buffer || exception) { error_ = exceptionText(engine->ctx, exception); return false; }
    JSValueProtect(engine->ctx, engine->buffer);

    NSArray<NSString*>* files = @[@"sos.js", @"controls.js", @"aural.js", @"lex.js", @"wide.js",
                                  @"maximizer.js", @"play.js", @"stream.js"];
    NSString* base = [NSString stringWithUTF8String:directory.c_str()];
    for (NSString* filename in files) {
        NSString* path = [base stringByAppendingPathComponent:filename];
        NSError* readError = nil;
        NSString* source = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
        if (!source) { error_ = std::string("Cannot read ") + path.UTF8String; return false; }
        JSStringRef script = JSStringCreateWithUTF8CString(source.UTF8String);
        JSStringRef sourceURL = JSStringCreateWithUTF8CString(path.UTF8String);
        JSEvaluateScript(engine->ctx, script, nullptr, sourceURL, 1, &exception);
        JSStringRelease(script); JSStringRelease(sourceURL);
        if (exception) { error_ = filename.UTF8String; error_ += ": " + exceptionText(engine->ctx, exception); return false; }
    }

    NSMutableArray* gains = [NSMutableArray arrayWithCapacity:10];
    NSMutableArray* freqs = [NSMutableArray arrayWithCapacity:10];
    for (float gain : s.gains) [gains addObject:@(gain)];
    for (float frequency : s.freqs) [freqs addObject:@(frequency)];
    NSDictionary* values = @{@"power":@(s.power), @"eq":@(s.eq), @"gains":gains, @"freqs":freqs,
        @"qMultiplier":@(s.qMultiplier), @"masterGainDb":@(s.masterGainDb),
        @"balanceDb":@(s.balanceDb), @"normalizationDb":@(s.normalizationDb),
        @"volumeLeveling":@(s.volumeLeveling), @"fidelity":@(s.fidelity),
        @"ambience":@(s.ambience), @"surround":@(s.surround),
        @"dynamicBoost":@(s.dynamicBoost), @"bass":@(s.bass)};
    NSData* json = [NSJSONSerialization dataWithJSONObject:values options:0 error:nil];
    NSString* jsonText = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString* create = [NSString stringWithFormat:@"FxDsp.createStream(%.0f, %@)", sampleRate, jsonText];
    JSStringRef expression = JSStringCreateWithUTF8CString(create.UTF8String);
    JSValueRef result = JSEvaluateScript(engine->ctx, expression, nullptr, nullptr, 1, &exception);
    JSStringRelease(expression);
    if (!result || exception || !JSValueIsObject(engine->ctx, result)) {
        error_ = exceptionText(engine->ctx, exception); return false;
    }
    engine->processor = JSValueToObject(engine->ctx, result, &exception);
    if (!engine->processor || exception) { error_ = exceptionText(engine->ctx, exception); return false; }
    JSValueProtect(engine->ctx, engine->processor);
    JSValueRef fn = property(engine->ctx, engine->processor, "process");
    if (!JSValueIsObject(engine->ctx, fn)) { error_ = "Streaming processor has no process function"; return false; }
    engine->process = JSValueToObject(engine->ctx, fn, &exception);
    if (!engine->process || exception) { error_ = exceptionText(engine->ctx, exception); return false; }
    impl_ = std::move(engine);
    return true;
}

bool JsDsp::process(float* samples, size_t frames) noexcept {
    if (!impl_ || !samples || frames > Impl::maxFrames) return false;
    auto& engine = *impl_;
    std::memcpy(engine.samples.data(), samples, frames * 2 * sizeof(float));
    JSValueRef args[] = {engine.buffer, JSValueMakeNumber(engine.ctx, static_cast<double>(frames))};
    JSValueRef exception = nullptr;
    JSObjectCallAsFunction(engine.ctx, engine.process, engine.processor, 2, args, &exception);
    if (exception) return false;
    std::memcpy(samples, engine.samples.data(), frames * 2 * sizeof(float));
    return true;
}
bool JsDsp::warmup(size_t blocks) noexcept {
    float silence[960] = {};
    for (size_t i = 0; i < blocks; ++i) {
        if (!process(silence, 480)) return false;
    }
    return true;
}
}
