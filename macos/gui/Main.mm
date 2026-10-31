// Functional JUCE front end for the FxSound macOS audio engine.
// The dark layout follows FxSound's JUCE FxProView and FxTheme. AGPL-3.0-or-later.
#include <juce_gui_extra/juce_gui_extra.h>
#import <Foundation/Foundation.h>
#include "FxAudioBridge.hpp"
#include "FxPreset.hpp"
#include <array>
#include <cmath>
#include <cstdlib>
#include <memory>

namespace {
const juce::Colour background{0xff181818}, panel{0xff0f0f0f}, black{0xff000000};
const juce::Colour pink{0xffe63462}, dimPink{0xff742834}, labelColour{0xffb1b1b1};
const char* effectNames[] = {"Clarity", "Ambience", "Surround Sound", "Dynamic Boost", "Bass Boost"};

class FxLook final : public juce::LookAndFeel_V4 {
public:
    FxLook() {
        setColour(juce::ComboBox::backgroundColourId, black);
        setColour(juce::ComboBox::textColourId, labelColour);
        setColour(juce::ComboBox::outlineColourId, black);
        setColour(juce::PopupMenu::backgroundColourId, panel);
        setColour(juce::PopupMenu::textColourId, labelColour);
        setColour(juce::PopupMenu::highlightedBackgroundColourId, dimPink);
        setColour(juce::Label::textColourId, labelColour);
        setColour(juce::TextButton::buttonColourId, background);
        setColour(juce::TextButton::textColourOffId, pink);
    }
    void drawComboBox(juce::Graphics& g, int w, int h, bool, int, int, int, int, juce::ComboBox&) override {
        g.setColour(black); g.fillRoundedRectangle(0, 0, (float)w, (float)h, 7.f);
        juce::Path arrow; arrow.startNewSubPath((float)w-29, h*0.46f);
        arrow.lineTo((float)w-24, h*0.57f); arrow.lineTo((float)w-19, h*0.46f);
        g.setColour(pink); g.strokePath(arrow, juce::PathStrokeType(1.3f));
    }
    void drawLinearSlider(juce::Graphics& g, int x, int y, int w, int h, float pos,
                          float, float, const juce::Slider::SliderStyle, juce::Slider& slider) override {
        if (slider.getName().startsWith("eq")) return; // the parent paints the EQ curve and handles
        const float cy = y + h * 0.5f;
        g.setColour(dimPink); g.fillRoundedRectangle((float)x, cy-1.5f, (float)w, 3.f, 1.5f);
        g.setColour(pink); g.fillRoundedRectangle((float)x, cy-1.5f, juce::jmax(0.f,pos-x), 3.f, 1.5f);
        g.fillEllipse(pos-7.f, cy-7.f, 14.f, 14.f);
        g.setColour(black); g.fillEllipse(pos-2.f, cy-2.f, 4.f, 4.f);
    }
    void drawRotarySlider(juce::Graphics& g, int x, int y, int w, int h, float p,
                          float start, float end, juce::Slider&) override {
        const auto bounds=juce::Rectangle<float>((float)x+5,(float)y+5,(float)w-10,(float)h-10);
        auto r=juce::jmin(bounds.getWidth(),bounds.getHeight())*0.5f;
        auto c=bounds.getCentre();
        juce::Path arc; arc.addCentredArc(c.x,c.y,r,r,0,start,end,true);
        g.setColour(dimPink); g.strokePath(arc,juce::PathStrokeType(4.f,juce::PathStrokeType::curved,juce::PathStrokeType::rounded));
        juce::Path active;active.addCentredArc(c.x,c.y,r,r,0,start,start+p*(end-start),true);
        g.setColour(pink);g.strokePath(active,juce::PathStrokeType(4.f,juce::PathStrokeType::curved,juce::PathStrokeType::rounded));
        auto angle=start+p*(end-start);
        g.fillEllipse(c.x+r*std::sin(angle)-3,c.y-r*std::cos(angle)-3,6,6);
    }
};

class IconButton final : public juce::Button {
public:
    enum class Kind { Menu, Power };
    explicit IconButton(Kind value) : juce::Button(value==Kind::Menu?"Menu":"Power"), kind(value) {}
    void paintButton(juce::Graphics& g, bool hover, bool down) override {
        auto bounds=getLocalBounds().toFloat();
        g.setColour((hover||down)?pink.brighter(0.18f):(kind==Kind::Power?pink:labelColour));
        if(kind==Kind::Menu){
            const float left=bounds.getCentreX()-9.f;
            for(float y: {bounds.getCentreY()-6.f,bounds.getCentreY(),bounds.getCentreY()+6.f})
                g.drawLine(left,y,left+18.f,y,1.5f);
        }else{
            auto center=bounds.getCentre();
            juce::Path arc;
            arc.addCentredArc(center.x,center.y+1.f,10.f,10.f,0.f,0.65f,5.63f,true);
            g.strokePath(arc,juce::PathStrokeType(2.f,juce::PathStrokeType::curved,juce::PathStrokeType::rounded));
            g.drawLine(center.x,center.y-12.f,center.x,center.y+1.f,2.f);
        }
    }
private:
    Kind kind;
};

class MainComponent final : public juce::Component, private juce::Timer {
    FxLook look;
    juce::ComboBox presetBox, deviceBox;
    IconButton power{IconButton::Kind::Power}, menu{IconButton::Kind::Menu};
    juce::Label status;
    std::array<juce::Slider,5> effects;
    std::array<juce::Slider,10> eqGains, frequencies;
    std::vector<fxport::NamedPreset> presets;
    std::vector<fxport::OutputDevice> devices;
    fxport::Settings settings;
    fxport::AudioHandle audio=nullptr;
    std::string selectedUID;
    bool loading=false;
    juce::String snapshotPath;
    bool snapshotWritten=false;

    void setStatus(const juce::String& message, bool error=false) {
        status.setColour(juce::Label::textColourId,error?pink:labelColour);
        status.setText(message,juce::dontSendNotification);
    }
    void syncControls() {
        loading=true;
        const float levels[]={settings.fidelity,settings.ambience,settings.surround,settings.dynamicBoost,settings.bass};
        for(size_t i=0;i<effects.size();++i)effects[i].setValue(levels[i],juce::dontSendNotification);
        for(size_t i=0;i<eqGains.size();++i){
            eqGains[i].setValue(settings.gains[i],juce::dontSendNotification);
            float frequency=settings.freqs[i]>0?settings.freqs[i]:float(62.5*std::pow(256.0,i/9.0));
            frequencies[i].setValue(frequency,juce::dontSendNotification);
        }
        loading=false;
        repaint();
    }
    void readControls() {
        settings.fidelity=(float)effects[0].getValue();
        settings.ambience=(float)effects[1].getValue();
        settings.surround=(float)effects[2].getValue();
        settings.dynamicBoost=(float)effects[3].getValue();
        settings.bass=(float)effects[4].getValue();
        for(size_t i=0;i<eqGains.size();++i){
            settings.gains[i]=(float)eqGains[i].getValue();
            settings.freqs[i]=(float)frequencies[i].getValue();
        }
    }
    void restartAudio() {
        if(loading)return;
        readControls();
        if(audio){fxport::stopAudio(audio);audio=nullptr;}
        std::string error;
        audio=fxport::startAudio(settings,selectedUID,error);
        setStatus(audio?(settings.power?"Processing system audio":"FxSound off · audio passing through"):
                  juce::String(error),!audio);
    }
    void refreshDevices() {
        devices=fxport::outputDevices();
        deviceBox.clear(juce::dontSendNotification);
        int id=1;
        for(const auto& device:devices)deviceBox.addItem(device.name,id++);
        int selected=0;
        for(size_t i=0;i<devices.size();++i){
            if(devices[i].uid==selectedUID)selected=(int)i;
            else if(selectedUID.empty()&&devices[i].isDefault)selected=(int)i;
        }
        if(!devices.empty()){
            selected=juce::jlimit(0,(int)devices.size()-1,selected);
            selectedUID=devices[(size_t)selected].uid;
            deviceBox.setSelectedId(selected+1,juce::dontSendNotification);
        }
    }
    void showMenu() {
        juce::PopupMenu popup;
        popup.addItem(1,"Reset to selected preset");
        popup.addItem(2,"Refresh output devices");
        popup.addSeparator();
        popup.addItem(3,"About this port");
        popup.showMenuAsync(juce::PopupMenu::Options().withTargetComponent(menu),
            [safe=juce::Component::SafePointer<MainComponent>(this)](int choice){
                if(!safe)return;
                if(choice==1 && safe->presetBox.getSelectedItemIndex()>=0){
                    safe->settings=safe->presets[(size_t)safe->presetBox.getSelectedItemIndex()].settings;
                    safe->syncControls();safe->restartAudio();
                } else if(choice==2) safe->refreshDevices();
                else if(choice==3) juce::AlertWindow::showMessageBoxAsync(juce::AlertWindow::InfoIcon,
                    "FxSound Mac", "Unofficial FxSound macOS port · AGPL-3.0-or-later");
            });
    }
    void timerCallback() override {
        if(!snapshotWritten && snapshotPath.isNotEmpty()){
            snapshotWritten=true;
            auto image=createComponentSnapshot(getLocalBounds(),true,1.0f);
            juce::File file(snapshotPath);
            if(auto stream=file.createOutputStream()){
                juce::PNGImageFormat png;
                png.writeImageToStream(image,*stream);
            }
        }
        if(audio && fxport::outputChanged(audio)){refreshDevices();restartAudio();}
    }
public:
    MainComponent() {
        setLookAndFeel(&look);
        setSize(1050,580);
        if(const char* requested=std::getenv("FXSOUND_SNAPSHOT_PATH"))snapshotPath=requested;
        auto arguments=juce::JUCEApplication::getCommandLineParameterArray();
        for(int i=0;i+1<arguments.size();++i)if(arguments[i]=="--snapshot")snapshotPath=arguments[i+1];
        auto base=[[[NSBundle mainBundle] resourcePath] UTF8String];
        presets=fxport::loadFactoryPresets(base?base:"");
        addAndMakeVisible(presetBox);
        int id=1;for(const auto& preset:presets)presetBox.addItem(preset.name,id++);
        if(!presets.empty()){
            int selected=1;for(size_t i=0;i<presets.size();++i)if(presets[i].name=="Voice")selected=(int)i+1;
            presetBox.setSelectedId(selected,juce::dontSendNotification);
            settings=presets[(size_t)selected-1].settings;
        }
        presetBox.onChange=[this]{
            int index=presetBox.getSelectedItemIndex();
            if(index>=0 && (size_t)index<presets.size()){
                settings=presets[(size_t)index].settings;syncControls();restartAudio();
            }
        };
        addAndMakeVisible(deviceBox);refreshDevices();
        deviceBox.onChange=[this]{
            int index=deviceBox.getSelectedItemIndex();
            selectedUID=index>=0 && (size_t)index<devices.size()?devices[(size_t)index].uid:"";
            restartAudio();
        };
        addAndMakeVisible(power);
        power.onClick=[this]{settings.power=!settings.power;restartAudio();repaint();};
        addAndMakeVisible(menu);menu.onClick=[this]{showMenu();};
        addAndMakeVisible(status);status.setJustificationType(juce::Justification::centredRight);
        setStatus("Starting audio…");
        for(size_t i=0;i<effects.size();++i){
            auto& slider=effects[i];addAndMakeVisible(slider);
            slider.setName("effect"+juce::String((int)i));
            slider.setSliderStyle(juce::Slider::LinearHorizontal);
            slider.setTextBoxStyle(juce::Slider::NoTextBox,false,0,0);
            slider.setRange(0,10,1);
            slider.onValueChange=[this]{repaint();};
            slider.onDragEnd=[this]{restartAudio();};
        }
        for(size_t i=0;i<eqGains.size();++i){
            auto& slider=eqGains[i];addAndMakeVisible(slider);
            slider.setName("eq"+juce::String((int)i));
            slider.setSliderStyle(juce::Slider::LinearVertical);
            slider.setTextBoxStyle(juce::Slider::NoTextBox,false,0,0);
            slider.setRange(-12,12,1);
            slider.onValueChange=[this]{repaint();};
            slider.onDragEnd=[this]{restartAudio();};
            auto& freq=frequencies[i];addAndMakeVisible(freq);
            freq.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
            freq.setTextBoxStyle(juce::Slider::NoTextBox,false,0,0);
            freq.setRange(20,20000,1);
            freq.setSkewFactorFromMidPoint(1000);
            freq.onValueChange=[this]{repaint();};
            freq.onDragEnd=[this]{restartAudio();};
        }
        syncControls();
        startTimer(1000);
        juce::MessageManager::callAsync([safe=juce::Component::SafePointer<MainComponent>(this)]{
            if(safe)safe->restartAudio();
        });
    }
    ~MainComponent() override {
        stopTimer();
        if(audio)fxport::stopAudio(audio);
        setLookAndFeel(nullptr);
    }
    void resized() override {
        presetBox.setBounds(52,89,470,40);
        deviceBox.setBounds(542,89,470,40);
        power.setBounds(874,9,37,37);
        menu.setBounds(152,10,36,35);
        status.setBounds(675,530,338,24);
        for(size_t i=0;i<effects.size();++i)effects[i].setBounds(69,316+(int)i*43,112,20);
        for(size_t i=0;i<eqGains.size();++i){
            int center=290+(int)i*74;
            eqGains[i].setBounds(center-20,315,40,148);
            frequencies[i].setBounds(center-18,501,36,36);
        }
    }
    void paint(juce::Graphics& g) override {
        g.fillAll(background);
        g.setColour(juce::Colours::white);
        const float logoX=34.f;
        const float heights[]={7.f,13.f,19.f,11.f,5.f};
        for(int i=0;i<5;++i)g.fillRoundedRectangle(logoX+i*4.f,29.f-heights[i]*0.5f,2.5f,heights[i],1.2f);
        g.setFont(juce::Font(juce::FontOptions(20.f).withStyle("Bold")));
        g.drawText("FxSound",57,10,95,38,juce::Justification::centredLeft);
        g.setColour(panel);g.fillRoundedRectangle(32,72,1002,489,9.f);
        g.setColour(black);g.fillRoundedRectangle(52,149,960,120,8.f);
        g.fillRoundedRectangle(52,285,168,256,8.f);
        g.fillRoundedRectangle(237,285,775,256,8.f);
        g.setColour(dimPink);
        for(int x=80;x<986;x+=8)g.fillRect(x,208,3,1);
        g.setFont(juce::Font(juce::FontOptions(12.f)));
        for(size_t i=0;i<effects.size();++i){
            const int y=300+(int)i*43;
            g.setColour(labelColour);g.drawText(effectNames[i],69,y,123,16,juce::Justification::centredLeft);
            g.drawText(juce::String((int)effects[i].getValue()),181,y+16,20,18,juce::Justification::centredLeft);
        }
        juce::Path line;
        for(size_t i=0;i<eqGains.size();++i){
            const float cx=290.f+(float)i*74.f;
            const float cy=390.f-(float)eqGains[i].getValue()*6.f;
            g.setColour(dimPink);
            for(int y=317;y<459;y+=5)g.fillRect((int)cx,y,1,3);
            if(i==0)line.startNewSubPath(cx,cy);else line.lineTo(cx,cy);
        }
        g.setColour(pink.withAlpha(0.28f));
        auto fill=line;fill.lineTo(956,462);fill.lineTo(290,462);fill.closeSubPath();g.fillPath(fill);
        g.setColour(pink);g.strokePath(line,juce::PathStrokeType(2.f));
        for(size_t i=0;i<eqGains.size();++i){
            const float cx=290.f+(float)i*74.f;
            const float cy=390.f-(float)eqGains[i].getValue()*6.f;
            g.fillEllipse(cx-8,cy-8,16,16);g.setColour(black);g.fillEllipse(cx-3,cy-3,6,6);
            g.setColour(labelColour);g.drawText(juce::String((int)eqGains[i].getValue()),(int)cx-17,(int)cy-27,34,18,juce::Justification::centred);
            const float hz=(float)frequencies[i].getValue();
            juce::String label=hz>=1000?juce::String(hz/1000.f,2)+" kHz":juce::String((int)std::round(hz))+" Hz";
            g.drawText(label,(int)cx-32,478,64,18,juce::Justification::centred);
            g.setColour(pink);
        }
    }
};

class FxApplication final : public juce::JUCEApplication {
    std::unique_ptr<juce::DocumentWindow> window;
public:
    const juce::String getApplicationName() override {return "FxSound Mac";}
    const juce::String getApplicationVersion() override {return "0.1.0";}
    void initialise(const juce::String&) override {
        window=std::make_unique<juce::DocumentWindow>("FxSound Mac",background,juce::DocumentWindow::allButtons);
        window->setUsingNativeTitleBar(true);
        window->setContentOwned(new MainComponent(),true);
        window->centreWithSize(1050,580);
        window->setVisible(true);
    }
    void shutdown() override {window.reset();}
    void systemRequestedQuit() override {quit();}
};
}
START_JUCE_APPLICATION(FxApplication)
