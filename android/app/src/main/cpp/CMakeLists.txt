cmake_minimum_required(VERSION 3.18)
project(voicevox_jni)

add_library(voicevox_jni SHARED voicevox_jni.cpp)

target_include_directories(voicevox_jni PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Link against the pre-built voicevox_core shared library
add_library(voicevox_core SHARED IMPORTED)
set_target_properties(voicevox_core PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libvoicevox_core.so
)

target_link_libraries(voicevox_jni voicevox_core log)
