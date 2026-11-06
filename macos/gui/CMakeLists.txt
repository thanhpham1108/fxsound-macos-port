cmake_minimum_required(VERSION 3.22)
project(FxSoundMac VERSION 0.1.2 LANGUAGES C CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.2" CACHE STRING "Minimum macOS version")

include(FetchContent)
FetchContent_Declare(JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG 9.0.4
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(JUCE)

juce_add_gui_app(FxSoundMac
    PRODUCT_NAME "FxSound Mac"
    COMPANY_NAME "FxSound macOS port"
    BUNDLE_ID "dev.fxsound.port.app")

target_sources(FxSoundMac PRIVATE
    Main.mm
    ../FxTap.mm
    ../FxJsDsp.mm
    ../FxPreset.mm
    ../../native/FxEq.cpp)
set_source_files_properties(Main.mm ../FxTap.mm ../FxJsDsp.mm ../FxPreset.mm
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_include_directories(FxSoundMac PRIVATE .. ../../native/include)
target_compile_definitions(FxSoundMac PRIVATE FXTAP_NO_MAIN=1 JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
target_link_libraries(FxSoundMac PRIVATE
    juce::juce_gui_extra
    juce::juce_recommended_config_flags
    "-framework CoreAudio"
    "-framework Foundation"
    "-framework JavaScriptCore")

set_target_properties(FxSoundMac PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist")
add_custom_command(TARGET FxSoundMac POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/dsp"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/../dsp" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/dsp"
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/presets"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../presets/factory.json" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/presets/factory.json"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/AGPL-3.0.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${juce_SOURCE_DIR}/LICENSE.md" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/JUCE-LICENSE.md"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../APPLE_SAMPLE_LICENSE.txt" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/APPLE_SAMPLE_LICENSE.txt")
