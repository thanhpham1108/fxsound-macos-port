// FxSound SOS parametric EQ port, AGPL-3.0-or-later.
// Equations follow upstream dsp/ptutil/Filt/FiltCalcBiqd.cpp::filtCalcParametric
// and dsp/ptutil/SOS/SosProcess.cpp::sosProcessBuffer (stereo branch).
#include "FxEq.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace fxport {
namespace {
constexpr float pi = 3.14159265358979323846f;
struct Section { float b0=1,b1=0,b2=0,a2=0,s1=0,s2=0,s3=0,s4=0; bool on=false; };
float bandwidthAngle(float a, float bandwidth) {
    const float t=std::tan(2*pi*bandwidth), a2=a*a, a4=a2*a2;
    const float d=2*a2*t, sn=(1+a4)*t, cs=1-a4;
    const float mag=std::sqrt(sn*sn+cs*cs);
    const float asnd=std::asin(std::clamp(d/mag,-1.f,1.f));
    const float delta=std::atan2(sn,cs);
    float theta=.5f*(pi-asnd-delta);
    const float tmp=.5f*(asnd-delta);
    if(tmp>0 && tmp<theta) theta=tmp;
    if(bandwidth>=.5f) theta=.005f;
    return theta/(2*pi);
}
Section design(float fs, Band band) {
    Section s;
    if(band.gainDb==0) return s;
    float q=band.q;
    if(band.frequencyHz<60) q=std::min(q,1+(band.frequencyHz-20)*19/40);
    if(std::abs(band.gainDb)<6) q=std::min(q,.2f+std::abs(band.gainDb)*19.8f/6);
    const float center=band.frequencyHz/fs, bw=center/q;
    const float a=std::tan(pi*(center-.25f)), asq=a*a;
    const float A=std::pow(10.f,band.gainDb/20.f);
    const float F=(band.gainDb<6 && band.gainDb>-6) ? std::sqrt(A) : (A>1 ? A/std::sqrt(2.f) : A*std::sqrt(2.f));
    const float C=1/std::tan(2*pi*bandwidthAngle(a,bw)), F2=F*F, diff=A*A-F2;
    const float alphad=std::abs(diff)<=1.65436e-24f ? C : std::sqrt(C*C*(F2-1)/diff);
    const float alphan=A*alphad, sum=1+asq, delta=1-asq;
    const float a0=sum+alphad*delta, recipa0=1/a0;
    s.b0=(sum+alphan*delta)*recipa0;
    s.b1=4*a*recipa0;
    s.b2=(sum-alphan*delta)*recipa0;
    s.a2=(sum-alphad*delta)*recipa0;
    s.on=true;
    if(!std::isfinite(s.b0)||!std::isfinite(s.b1)||!std::isfinite(s.b2)||!std::isfinite(s.a2)) throw std::invalid_argument("unstable EQ settings");
    return s;
}
}
struct Processor::State { std::vector<Section> sections; float gain=1; };
Processor::Processor(float sampleRate,const std::vector<Band>& bands,float masterGainDb):sampleRate_(sampleRate) {
    if(!std::isfinite(sampleRate)||sampleRate<8000||sampleRate>192000||bands.size()>32||!std::isfinite(masterGainDb)||std::abs(masterGainDb)>24) throw std::invalid_argument("invalid EQ format or gain");
    auto state=new State;
    try {
        state->gain=std::pow(10.f,masterGainDb/20.f);
        state->sections.reserve(bands.size());
        for(const auto& band:bands) {
            if(!std::isfinite(band.frequencyHz)||band.frequencyHz<20||band.frequencyHz>=sampleRate*.45f||!std::isfinite(band.gainDb)||std::abs(band.gainDb)>24||!std::isfinite(band.q)||band.q<=0||band.q>20) throw std::invalid_argument("invalid EQ band");
            state->sections.push_back(design(sampleRate,band));
        }
    } catch(...) { delete state; throw; }
    handle_=state;
}
Processor::~Processor(){delete handle_;}
bool Processor::reset() noexcept {if(!handle_)return false; for(auto& s:handle_->sections) s.s1=s.s2=s.s3=s.s4=0;return true;}
bool Processor::process(float* x,std::size_t frames,bool dryBypass) noexcept {
    if(!handle_||(!x&&frames))return false;
    if(dryBypass)return true;
    for(std::size_t j=0;j<frames;++j){
        float l=x[2*j],r=x[2*j+1];
        for(auto& s:handle_->sections) if(s.on){
            float yl=s.s1+s.b0*l+1.e-30f;
            s.s1=(l-yl)*s.b1+s.s2; s.s2=s.b2*l-s.a2*yl; l=yl;
            float yr=s.s3+s.b0*r+1.e-30f;
            s.s3=(r-yr)*s.b1+s.s4; s.s4=s.b2*r-s.a2*yr; r=yr;
        }
        x[2*j]=l*handle_->gain; x[2*j+1]=r*handle_->gain;
    }
    return true;
}
}
