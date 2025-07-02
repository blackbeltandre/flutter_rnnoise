#ifndef RNNOISE_PROCESSOR_H
#define RNNOISE_PROCESSOR_H

// Wrapper untuk rnnoise.h agar bisa diakses dari C++ dengan C linkage
#ifdef __cplusplus
extern "C" {
#endif

// Include header RNNoise asli di sini
#include "rnnoise.h" // Pastikan path ini benar relatif terhadap rnnoise_processor.h

#ifdef __cplusplus
}
#endif

// Deklarasi fungsi-fungsi C++ wrapper yang akan Anda panggil dari JNI
// Ini adalah fungsi-fungsi yang Anda definisikan di rnnoise_processor.cpp
void* create_rnnoise_state_cpp(); // Ubah nama agar tidak bentrok dengan wrapper JNI di Java
void process_rnnoise_frame_cpp(void* state, float* out, const float* in); // Sesuai dengan rnnoise_process_frame asli
void destroy_rnnoise_state_cpp(void* state); // Ubah nama agar tidak bentrok

// Jika Anda memiliki fungsi lain yang di-expose ke JNI, deklarasikan di sini:
// Contoh: Fungsi JNI actual, walaupun biasanya ini di native-lib.cpp
// extern "C" JNIEXPORT jlong JNICALL Java_com_example_yourpackage_YourClass_nativeCreateRnnoise(JNIEnv*, jobject);
// extern "C" JNIEXPORT void JNICALL Java_com_example_yourpackage_YourClass_nativeProcessRnnoise(JNIEnv*, jobject, jlong, jfloatArray, jfloatArray);
// extern "C" JNIEXPORT void JNICALL Java_com_example_yourpackage_YourClass_nativeDestroyRnnoise(JNIEnv*, jobject, jlong);


#endif // RNNOISE_PROCESSOR_H