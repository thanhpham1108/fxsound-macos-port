#include "LegacyRing.hpp"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>

int main() {
    fxport::LegacyRing ring;
    std::array<float,1024*2> input{},output{};
    for(size_t i=0;i<1024;++i){input[2*i]=0.25f;input[2*i+1]=-0.25f;}
    assert(ring.push(input.data(),1024)==1024);
    assert(ring.pull(output.data(),512,48000,48000));
    for(size_t i=0;i<512*2;++i)assert(std::fabs(output[i])==0.25f);
    assert(!ring.pull(output.data(),1024,48000,48000));
    assert(ring.underruns()>0);
    assert(ring.push(input.data(),1024)==1024);
    assert(ring.push(input.data(),1024)==1024);
    assert(ring.pull(output.data(),512,44100,48000));
    for(size_t i=0;i<512*2;++i)assert(std::isfinite(output[i])&&std::fabs(output[i])<=1.f);
    fxport::LegacyRing saturated;
    for(size_t i=0;i<20;++i)saturated.push(input.data(),1024);
    assert(saturated.overruns()>0);
    fxport::LegacyRing steady;
    steady.push(input.data(),1024);
    for(size_t i=0;i<10000;++i){
        assert(steady.pull(output.data(),512,48000,47999.8));
        assert(steady.push(input.data(),512)==512);
    }
    assert(steady.underruns()==0&&steady.overruns()==0);
    std::puts("LegacyRing: basic buffering, underrun and resampling passed");
}
