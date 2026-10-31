// AGPL-3.0-or-later. Offline stereo PCM prototype for the FxSound EQ slice.
#include "FxEq.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static uint16_t u16(const char* p){return uint16_t(uint8_t(p[0])|(uint16_t(uint8_t(p[1]))<<8));}
static uint32_t u32(const char* p){return uint32_t(uint8_t(p[0])|(uint32_t(uint8_t(p[1]))<<8)|(uint32_t(uint8_t(p[2]))<<16)|(uint32_t(uint8_t(p[3]))<<24));}
static void put16(std::ostream& o,uint16_t n){char p[2]={char(n),char(n>>8)};o.write(p,2);}
static void put32(std::ostream& o,uint32_t n){char p[4]={char(n),char(n>>8),char(n>>16),char(n>>24)};o.write(p,4);}
int main(int argc,char** argv){
    try {
        if(argc<3) throw std::runtime_error("usage: fxwav input.wav output.wav [--bypass] [--gain dB] [--band Hz dB Q]");
        bool bypass=false; float gain=0; std::vector<fxport::Band> bands;
        for(int i=3;i<argc;++i){std::string flag=argv[i];
            if(flag=="--bypass") bypass=true;
            else if(flag=="--gain"&&i+1<argc) gain=std::stof(argv[++i]);
            else if(flag=="--band"&&i+3<argc){fxport::Band b{std::stof(argv[i+1]),std::stof(argv[i+2]),std::stof(argv[i+3])};bands.push_back(b);i+=3;}
            else throw std::runtime_error("invalid option");
        }
        std::ifstream in(argv[1],std::ios::binary); if(!in)throw std::runtime_error("cannot open input");
        char hdr[12];in.read(hdr,12); if(in.gcount()!=12||std::memcmp(hdr,"RIFF",4)||std::memcmp(hdr+8,"WAVE",4))throw std::runtime_error("expected RIFF WAV");
        uint16_t format=0,channels=0,bits=0,align=0;uint32_t rate=0;std::vector<char> pcm;
        while(in){char ch[8];in.read(ch,8);if(in.gcount()==0)break;if(in.gcount()!=8)throw std::runtime_error("truncated chunk");uint32_t size=u32(ch+4);
            if(size>268435456)throw std::runtime_error("chunk too large");
            if(!std::memcmp(ch,"fmt ",4)){std::vector<char> b(size);in.read(b.data(),size);if(size<16||!in)throw std::runtime_error("invalid fmt");format=u16(b.data());channels=u16(b.data()+2);rate=u32(b.data()+4);align=u16(b.data()+12);bits=u16(b.data()+14);}
            else if(!std::memcmp(ch,"data",4)){pcm.resize(size);in.read(pcm.data(),size);if(!in)throw std::runtime_error("truncated samples");}
            else in.seekg(size,std::ios::cur);
            if(size&1)in.seekg(1,std::ios::cur);
        }
        if(channels!=2||!rate||!((format==1&&bits==16&&align==4)||(format==3&&bits==32&&align==8))||pcm.empty()||pcm.size()%align)throw std::runtime_error("requires interleaved stereo PCM16 or float32 WAV");
        std::vector<float> samples(pcm.size()/(bits/8));
        for(size_t i=0;i<samples.size();++i){if(format==1){samples[i]=int16_t(u16(pcm.data()+2*i))/32768.f;}else{uint32_t raw=u32(pcm.data()+4*i);std::memcpy(&samples[i],&raw,4);if(!std::isfinite(samples[i]))throw std::runtime_error("nonfinite sample");}}
        fxport::Processor processor(float(rate),bands,gain);if(!processor.process(samples.data(),samples.size()/2,bypass))throw std::runtime_error("DSP failed");
        float peak=0;size_t clipped=0;for(float x:samples){peak=std::max(peak,std::abs(x));if(std::abs(x)>1.f)++clipped;}
        std::ofstream out(argv[2],std::ios::binary);if(!out)throw std::runtime_error("cannot open output");
        uint32_t bytes=uint32_t(samples.size()*4);out.write("RIFF",4);put32(out,36+bytes);out.write("WAVEfmt ",8);put32(out,16);put16(out,3);put16(out,2);put32(out,rate);put32(out,rate*8);put16(out,8);put16(out,32);out.write("data",4);put32(out,bytes);
        for(float x:samples){uint32_t raw;std::memcpy(&raw,&x,4);put32(out,raw);}if(!out)throw std::runtime_error("write failed");
        std::cout<<"frames="<<samples.size()/2<<" peak="<<peak<<" samples_above_full_scale="<<clipped<<"\n";
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
