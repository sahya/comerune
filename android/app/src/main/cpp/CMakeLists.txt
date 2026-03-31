cmake_minimum_required(VERSION 3.18)
project(voicevox_jni)

add_library(voicevox_jni SHARED voicevox_jni.cpp)

target_include_directories(voicevox_jni PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)

<<<<<<< HEAD
# Link against voicevox_core by SONAME (not absolute path) to avoid
# embedding the build machine's filesystem path in the ELF NEEDED entry.
# The library is pre-loaded from Java via System.loadLibrary() at runtime.
target_link_directories(voicevox_jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}
)

=======
# Link against the pre-built voicevox_core shared library
target_link_directories(voicevox_jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}
)
>>>>>>> ba3a524 (fix(speech): レビュー指摘のMust Fix/Should Fix修正)
target_link_libraries(voicevox_jni -lvoicevox_core log)
