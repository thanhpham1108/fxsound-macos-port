cmake_minimum_required(VERSION 3.22)
project(FxSoundMac VERSION 0.1.3 LANGUAGES C CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
option(FXSOUND_VENTURA "Build the macOS 13 BlackHole routing edition" OFF)
if(FXSOUND_VENTURA)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version" FORCE)
    set(FXSOUND_PRODUCT_NAME "FxSound Mac Ventura")
    set(FXSOUND_BUNDLE_ID "dev.fxsound.port.ventura")
else()
    set(CMAKE_OSX_DEPLOYMENT_TARGET "14.2" CACHE STRING "Minimum macOS version" FORCE)
    set(FXSOUND_PRODUCT_NAME "FxSound Mac")
    set(FXSOUND_BUNDLE_ID "dev.fxsound.port.app")
endif()

include(FetchContent)
FetchContent_Declare(JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG 9.0.4
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(JUCE)

juce_add_gui_app(FxSoundMac
    PRODUCT_NAME "${FXSOUND_PRODUCT_NAME}"
    COMPANY_NAME "FxSound macOS port"
    BUNDLE_ID "${FXSOUND_BUNDLE_ID}")

target_sources(FxSoundMac PRIVATE
    Main.mm
    ../FxJsDsp.mm
    ../FxPreset.mm
    ../../native/FxEq.cpp)
if(FXSOUND_VENTURA)
    target_sources(FxSoundMac PRIVATE ../LegacyRoute.mm)
    target_compile_definitions(FxSoundMac PRIVATE FXSOUND_LEGACY_BACKEND=1)
    add_executable(FxRouteGuard ../FxRouteGuard.mm)
    set_source_files_properties(../FxRouteGuard.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
    target_link_libraries(FxRouteGuard PRIVATE "-framework CoreAudio" "-framework Foundation")
    add_dependencies(FxSoundMac FxRouteGuard)
    set_target_properties(FxSoundMac PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info-Ventura.plist")
    add_custom_command(TARGET FxSoundMac POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:FxRouteGuard>" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/MacOS/FxRouteGuard")
else()
    target_sources(FxSoundMac PRIVATE ../FxTap.mm)
    target_compile_definitions(FxSoundMac PRIVATE FXTAP_NO_MAIN=1)
    set_target_properties(FxSoundMac PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist")
endif()
set_source_files_properties(Main.mm ../FxTap.mm ../LegacyRoute.mm ../FxJsDsp.mm ../FxPreset.mm
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_include_directories(FxSoundMac PRIVATE .. ../../native/include)
target_compile_definitions(FxSoundMac PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
target_link_libraries(FxSoundMac PRIVATE
    juce::juce_gui_extra
    juce::juce_recommended_config_flags
    "-framework CoreAudio"
    "-framework Foundation"
    "-framework JavaScriptCore")

add_custom_command(TARGET FxSoundMac POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/dsp"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/../dsp" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/dsp"
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/presets"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../presets/factory.json" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/presets/factory.json"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/AGPL-3.0.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${juce_SOURCE_DIR}/LICENSE.md" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/JUCE-LICENSE.md"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../APPLE_SAMPLE_LICENSE.txt" "$<TARGET_BUNDLE_DIR:FxSoundMac>/Contents/Resources/APPLE_SAMPLE_LICENSE.txt")
