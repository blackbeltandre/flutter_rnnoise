cmake_minimum_required(VERSION 3.18.1)

project("flutter_rnnoise_android_native")

add_library(rnnoise_jni
        SHARED
        rnnoise_processor.cpp
        # File-file dari kloningan rnnoise xiph/rnnoise (tag v0.1)
        src/celt_lpc.c
        src/denoise.c
        src/kiss_fft.c
        src/pitch.c
        src/rnn.c
        src/rnn_data.c      # <-- PASTIKAN INI ADALAH rnn_data.c
)

find_library(log-lib log)

target_link_libraries(
        rnnoise_jni
        ${log-lib}
        -latomic
        -lm
)

target_include_directories(rnnoise_jni PRIVATE
        ${CMAKE_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/src
)
# Hapus baris `target_compile_definitions` yang tidak perlu jika ada.