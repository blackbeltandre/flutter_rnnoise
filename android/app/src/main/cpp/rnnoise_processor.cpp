#include <jni.h>          // Untuk JNI
#include <android/log.h>  // Untuk logging Android (ANDROID_LOG_INFO, dll.)

// --- extern "C" block untuk RNNoise C Library ---
// Blok ini memberi tahu kompiler C++ untuk memperlakukan deklarasi dari rnnoise.h
// sebagai fungsi C, mencegah "name mangling" C++ agar linker bisa menemukannya.
#ifdef __cplusplus
extern "C" {
#endif

#include "rnnoise.h" // Ini adalah header asli dari pustaka RNNoise Anda

#ifdef __cplusplus
}
#endif
// --- Akhir extern "C" block ---

// Define TAG untuk logging Android yang lebih mudah
#define TAG "RNNoiseJNI"

// --- Implementasi Fungsi-fungsi C++ Wrapper untuk RNNoise ---
// Fungsi-fungsi ini adalah lapisan perantara antara JNI dan pustaka RNNoise asli.
// Mereka mengelola state RNNoise dan memanggil fungsi-fungsi intinya.

// Membuat instance DenoiseState RNNoise baru
void* create_rnnoise_state_cpp() {
    DenoiseState *st = rnnoise_create(); // Memanggil fungsi asli RNNoise (tanpa argumen di v0.1)
    if (st == NULL) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "Failed to create DenoiseState.");
    } else {
        __android_log_print(ANDROID_LOG_INFO, TAG, "DenoiseState created successfully.");
    }
    return st;
}

// Memproses satu frame audio menggunakan RNNoise
void process_rnnoise_frame_cpp(void* state, float* out, const float* in) {
    DenoiseState *st = static_cast<DenoiseState*>(state);
    if (st == NULL) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "DenoiseState is NULL in process_rnnoise_frame_cpp.");
        return;
    }
    // RNNoise v0.1 dirancang untuk memproses frame 480 sampel float.
    rnnoise_process_frame(st, out, in);
}

// Menghancurkan instance DenoiseState RNNoise
void destroy_rnnoise_state_cpp(void* state) {
    DenoiseState *st = static_cast<DenoiseState*>(state);
    if (st == NULL) {
        __android_log_print(ANDROID_LOG_WARN, TAG, "Attempted to destroy NULL DenoiseState.");
        return;
    }
    rnnoise_destroy(st); // Memanggil fungsi asli RNNoise
    __android_log_print(ANDROID_LOG_INFO, TAG, "DenoiseState destroyed successfully.");
}

// --- Implementasi Fungsi JNI (Yang Dipanggil Langsung dari Kotlin) ---
// Fungsi-fungsi ini adalah titik masuk dari Kotlin ke kode C++.
// Pastikan nama-nama ini sesuai persis dengan deklarasi 'external' di file Kotlin RnnoisePlugin.kt Anda.
// Ingat: underscore (_) di nama paket Java/Kotlin menjadi _1 di nama fungsi JNI.

extern "C" JNIEXPORT jlong JNICALL
Java_com_lintasedu_rnnoise_flutter_1rnnoise_RnnoisePlugin_nativeCreateRnnoise(JNIEnv *env, jobject thiz) {
    __android_log_print(ANDROID_LOG_INFO, TAG, "JNI: Called nativeCreateRnnoise");
    // Memanggil fungsi C++ wrapper untuk membuat state RNNoise
    return reinterpret_cast<jlong>(create_rnnoise_state_cpp());
}

extern "C" JNIEXPORT void JNICALL
Java_com_lintasedu_rnnoise_flutter_1rnnoise_RnnoisePlugin_nativeProcessRnnoise(JNIEnv *env, jobject thiz,
        jlong state_ptr,
jfloatArray input_array,
        jfloatArray output_array) {
__android_log_print(ANDROID_LOG_INFO, TAG, "JNI: Called nativeProcessRnnoise");

// Mendapatkan pointer ke data float dari array Java
float *input_buffer = env->GetFloatArrayElements(input_array, NULL);
float *output_buffer = env->GetFloatArrayElements(output_array, NULL);

// Mendapatkan panjang array (jumlah elemen float)
jsize input_len = env->GetArrayLength(input_array);
jsize output_len = env->GetArrayLength(output_array);

// Memberikan peringatan jika ukuran frame tidak sesuai ekspektasi RNNoise (480 sampel)
if (input_len != 480 || output_len != 480) {
__android_log_print(ANDROID_LOG_WARN, TAG, "Input/output array size is not 480. RNNoise expects 480 samples per frame (20ms at 24kHz).");
// Dalam aplikasi nyata, Anda perlu memecah/menggabungkan data menjadi frame 480 sampel jika berbeda.
}

// Memanggil fungsi C++ wrapper untuk melakukan denoise pada frame
process_rnnoise_frame_cpp(reinterpret_cast<void*>(state_ptr), output_buffer, input_buffer);

// Melepaskan buffer JNI.
// JNI_ABORT untuk input_array: tidak menyalin perubahan kembali ke array Java (input tidak diubah).
// 0 untuk output_array: menyalin perubahan (hasil denoise) kembali ke array Java.
env->ReleaseFloatArrayElements(input_array, input_buffer, JNI_ABORT);
env->ReleaseFloatArrayElements(output_array, output_buffer, 0);
}

extern "C" JNIEXPORT void JNICALL
Java_com_lintasedu_rnnoise_flutter_1rnnoise_RnnoisePlugin_nativeDestroyRnnoise(JNIEnv *env, jobject thiz,
        jlong state_ptr) {
__android_log_print(ANDROID_LOG_INFO, TAG, "JNI: Called nativeDestroyRnnoise");
// Memanggil fungsi C++ wrapper untuk menghancurkan state RNNoise
destroy_rnnoise_state_cpp(reinterpret_cast<void*>(state_ptr));
}