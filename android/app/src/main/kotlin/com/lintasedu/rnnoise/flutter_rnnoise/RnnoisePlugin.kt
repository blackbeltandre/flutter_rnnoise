package com.lintasedu.rnnoise.flutter_rnnoise

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.media.AudioManager

/** RnnoisePlugin */
class RnnoisePlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var audioRecord: AudioRecord? = null
    private var isRecording = AtomicBoolean(false)
    private var rnnoiseStatePtr: Long = 0L

    private val SAMPLES_PER_FRAME = 480 // Setara dengan 20ms pada 24kHz
    private val SAMPLE_RATE = 24000
    private val BYTES_PER_SAMPLE = 2 // Untuk PCM 16-bit (16 bits / 8 bits/byte = 2 bytes)

    private val TAG = "RnnoisePlugin" // Untuk memfilter log di Logcat

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine: Plugin terpasang.")
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_rnnoise")
        channel.setMethodCallHandler(this)
        this.applicationContext = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "createRnnoiseProcessor" -> {
                // Pastikan hanya satu prosesor yang aktif pada satu waktu
                if (rnnoiseStatePtr != 0L) {
                    Log.w(TAG, "Prosesor RNNoise sudah ada. Menghancurkan yang lama.")
                    nativeDestroyRnnoise(rnnoiseStatePtr)
                    rnnoiseStatePtr = 0L
                }
                rnnoiseStatePtr = nativeCreateRnnoise() // Panggil fungsi native untuk membuat prosesor
                if (rnnoiseStatePtr == 0L) {
                    result.error("RNNOISE_ERROR", "Gagal membuat prosesor RNNoise (native mengembalikan 0)", null)
                    Log.e(TAG, "Gagal membuat prosesor RNNoise, nativeCreateRnnoise mengembalikan 0.")
                } else {
                    result.success(rnnoiseStatePtr)
                    Log.d(TAG, "Prosesor RNNoise dibuat dengan pointer: $rnnoiseStatePtr")
                }
            }
            "destroyRnnoiseProcessor" -> {
                stopProcessingInternal() // Hentikan perekaman dan pemrosesan sebelum menghancurkan
                if (rnnoiseStatePtr != 0L) {
                    nativeDestroyRnnoise(rnnoiseStatePtr) // Panggil fungsi native untuk menghancurkan prosesor
                    Log.d(TAG, "Prosesor RNNoise dihancurkan untuk pointer: $rnnoiseStatePtr")
                }
                this.rnnoiseStatePtr = 0L
                result.success(null)
            }
            "startAudioProcessing" -> {
                // Pastikan prosesor sudah dibuat sebelum memulai pemrosesan
                if (rnnoiseStatePtr == 0L) {
                    result.error("STATE_ERROR", "Prosesor RNNoise belum dibuat. Panggil createRnnoiseProcessor dulu.", null)
                    return
                }
                // Pastikan konteks aplikasi tersedia
                if (applicationContext == null) {
                    result.error("INIT_ERROR", "Konteks aplikasi belum diinisialisasi.", null)
                    Log.e(TAG, "Konteks aplikasi null saat mencoba memulai pemrosesan audio.")
                    return
                }
                startProcessingInternal(rnnoiseStatePtr) // Mulai perekaman dan pemrosesan audio
                result.success(null)
            }
            "stopAudioProcessing" -> {
                stopProcessingInternal() // Hentikan perekaman dan pemrosesan audio
                result.success(null)
            }
            "getDenoisedAudioTrackId" -> {
                Log.w(TAG, "getDenoisedAudioTrackId dipanggil, ini adalah placeholder. Implementasi ADM nyata diperlukan.")
                result.success(null) // Ini adalah placeholder untuk integrasi WebRTC di masa depan
            }
            else -> result.notImplemented() // Jika metode tidak dikenal
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine: Plugin dilepaskan.")
        channel.setMethodCallHandler(null) // Lepaskan handler channel
        stopProcessingInternal() // Hentikan semua pemrosesan
        if (rnnoiseStatePtr != 0L) {
            nativeDestroyRnnoise(rnnoiseStatePtr) // Hancurkan prosesor RNNoise jika masih ada
            Log.d(TAG, "Prosesor RNNoise dihancurkan selama onDetachedFromEngine: $rnnoiseStatePtr")
        }
        this.applicationContext = null // Bersihkan konteks
        this.rnnoiseStatePtr = 0L
    }

    // --- Fungsionalitas Pemrosesan Audio Internal ---
    private fun startProcessingInternal(statePtr: Long) {
        if (isRecording.get()) {
            Log.d(TAG, "startProcessingInternal: Sudah merekam, mengabaikan panggilan.")
            return
        }

        val currentContext = applicationContext ?: run {
            mainHandler.post { channel.invokeMethod("onAudioError", "Konteks aplikasi null untuk pemrosesan audio.") }
            Log.e(TAG, "startProcessingInternal: Konteks aplikasi null, tidak dapat memulai pemrosesan audio.")
            return
        }

        // Periksa izin RECORD_AUDIO
        if (ActivityCompat.checkSelfPermission(
                currentContext,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            val msg = "Izin RECORD_AUDIO tidak diberikan oleh sistem Android."
            mainHandler.post { channel.invokeMethod("onAudioError", msg) }
            Log.e(TAG, msg)
            return
        } else {
            Log.d(TAG, "Izin RECORD_AUDIO sudah diberikan.")
        }

        // Hitung ukuran buffer yang diperlukan untuk AudioRecord
        val minBufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        // Gunakan buffer size minimal dikalikan 2 atau 4 untuk stabilitas yang lebih baik
        val bufferSize = minBufferSize * 2 // atau * 4 jika masih ada underrun/overrun issues

        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            val msg = "Ukuran buffer audio minimal tidak valid: $minBufferSize"
            mainHandler.post { channel.invokeMethod("onAudioError", msg) }
            Log.e(TAG, msg)
            return
        } else {
            Log.d(TAG, "Min buffer size: $minBufferSize bytes")
            Log.d(TAG, "Actual buffer size used: $bufferSize bytes (Min * 2)")
        }

        try {
            // Inisialisasi AudioRecord
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            // Periksa status inisialisasi AudioRecord
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                val msg = "Inisialisasi AudioRecord gagal. Status: ${audioRecord?.state}"
                mainHandler.post { channel.invokeMethod("onAudioError", msg) }
                Log.e(TAG, msg)
                audioRecord?.release()
                audioRecord = null
                return
            } else {
                Log.d(TAG, "AudioRecord berhasil diinisialisasi. Status: ${audioRecord?.state}")
            }

            audioRecord?.startRecording() // Mulai perekaman
            isRecording.set(true)
            Log.d(TAG, "AudioRecord mulai merekam.")

            // Log volume perangkat saat ini
            val audioManager = currentContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            Log.d(TAG, "Volume perangkat saat ini: $currentVolume / $maxVolume")
            if (currentVolume == 0) {
                mainHandler.post { channel.invokeMethod("onAudioError", "Volume perangkat sangat rendah atau nol. Periksa volume media Anda.") }
            }

            // Memulai thread terpisah untuk pemrosesan audio
            Thread {
                // Set prioritas thread ke prioritas audio untuk mengurangi latensi
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
                val pcmBuffer = ShortArray(SAMPLES_PER_FRAME) // Buffer untuk PCM 16-bit dari AudioRecord
                val floatInputBuffer = FloatArray(SAMPLES_PER_FRAME) // Buffer input untuk RNNoise (float)
                val floatOutputBuffer = FloatArray(SAMPLES_PER_FRAME) // Buffer output dari RNNoise (float)

                var framesReadCounter = 0 // Counter untuk logging periodik

                while (isRecording.get()) {
                    // Baca sampel audio dari mikrofon
                    val bytesRead = audioRecord?.read(pcmBuffer, 0, SAMPLES_PER_FRAME) ?: 0

                    // Deklarasikan nonZeroRawSamples di sini agar dapat diakses oleh kedua blok log
                    var nonZeroRawSamples = 0

                    if (bytesRead > 0) {
                        framesReadCounter++
                        nonZeroRawSamples = pcmBuffer.count { it != 0.toShort() } // Hitung jumlah sampel non-nol

                        // --- KIRIM AUDIO MENTAH KE FLUTTER ---
                        val rawByteBuffer = ByteBuffer.allocate(pcmBuffer.size * BYTES_PER_SAMPLE)
                        rawByteBuffer.order(ByteOrder.LITTLE_ENDIAN) // Pastikan byte order
                        rawByteBuffer.asShortBuffer().put(pcmBuffer)
                        mainHandler.post {
                            channel.invokeMethod("onRawAudioFrame", rawByteBuffer.array())
                        }
                        // --- AKHIR KIRIM AUDIO MENTAH ---

                        // Log untuk verifikasi audio mentah yang dibaca
                        if (framesReadCounter % 50 == 0) { // Log setiap ~1 detik
                            Log.d(TAG, "Native: AudioRecord membaca $bytesRead sampel mentah. Non-nol: $nonZeroRawSamples. Total frame: $framesReadCounter")
                            if (nonZeroRawSamples == 0) {
                                Log.w(TAG, "Native: AudioRecord membaca frame mentah yang semuanya nol. Periksa input mikrofon atau sensitivitas.")
                            }
                        }

                        // Konversi PCM 16-bit (short) ke float untuk RNNoise
                        for (i in 0 until bytesRead) {
                            floatInputBuffer[i] = pcmBuffer[i] / 32768.0f // Normalisasi ke [-1.0, 1.0]
                        }

                        // Panggil RNNoise untuk memproses audio
                        if (statePtr != 0L) {
                            nativeProcessRnnoise(statePtr, floatInputBuffer, floatOutputBuffer)
                        } else {
                            // Fallback jika prosesor RNNoise tidak valid (gunakan input asli sebagai output)
                            Log.w(TAG, "Native: Melewati nativeProcessRnnoise: rnnoiseStatePtr adalah 0L, menggunakan input asli sebagai output.")
                            floatInputBuffer.copyInto(floatOutputBuffer)
                        }

                        // Konversi float output dari RNNoise kembali ke PCM 16-bit (short)
                        val denoisedPcmBuffer = ShortArray(SAMPLES_PER_FRAME)
                        for (i in 0 until bytesRead) {
                            val value = (floatOutputBuffer[i] * 32767.0f).toInt()
                            denoisedPcmBuffer[i] = when {
                                value > Short.MAX_VALUE -> Short.MAX_VALUE
                                value < Short.MIN_VALUE -> Short.MIN_VALUE
                                else -> value.toShort()
                            }
                        }

                        // Log untuk verifikasi audio yang di-denoise
                        if (framesReadCounter % 50 == 0) { // Log setiap ~1 detik
                            val nonZeroDenoisedSamples = denoisedPcmBuffer.count { it != 0.toShort() }
                            Log.d(TAG, "Native: RNNoise menghasilkan $nonZeroDenoisedSamples sampel denoised. (Input non-nol: $nonZeroRawSamples)")
                            if (nonZeroDenoisedSamples == 0 && nonZeroRawSamples > 0) {
                                Log.w(TAG, "Native: RNNoise menghasilkan frame yang semuanya nol meskipun ada input. Denoising terlalu agresif?")
                            }
                        }

                        // Kirim data audio yang di-denoise kembali ke Flutter
                        val byteBuffer = ByteBuffer.allocate(denoisedPcmBuffer.size * BYTES_PER_SAMPLE)
                        byteBuffer.order(ByteOrder.LITTLE_ENDIAN) // Pastikan byte order sesuai dengan Flutter
                        byteBuffer.asShortBuffer().put(denoisedPcmBuffer)

                        mainHandler.post {
                            channel.invokeMethod("onDenoisedAudioFrame", byteBuffer.array())
                        }
                    } else if (bytesRead == AudioRecord.ERROR_INVALID_OPERATION || bytesRead == AudioRecord.ERROR_BAD_VALUE) {
                        val msg = "Native: AudioRecord read error: $bytesRead"
                        Log.e(TAG, msg)
                        mainHandler.post { channel.invokeMethod("onAudioError", msg) }
                        break // Keluar dari loop perekaman jika ada error fatal
                    } else {
                        // Jika bytesRead <= 0 tapi bukan error, mungkin karena buffer kosong sementara
                        // Tambahkan sleep singkat untuk mencegah loop terlalu cepat membuang CPU
                        // try { Thread.sleep(1); } catch (e: InterruptedException) {}
                    }
                }
                Log.d(TAG, "Native: Thread pemrosesan audio berhenti.")
            }.start()
        } catch (e: Exception) {
            val msg = "Native: Pengecualian AudioRecord: ${e.message}"
            mainHandler.post { channel.invokeMethod("onAudioError", msg) }
            Log.e(TAG, "Native: Kesalahan saat menginisialisasi atau merekam audio: ${e.message}", e)
            stopProcessingInternal() // Hentikan pemrosesan jika terjadi pengecualian
        }
    }

    private fun stopProcessingInternal() {
        if (isRecording.getAndSet(false)) { // Set isRecording ke false dan periksa nilai sebelumnya
            Log.d(TAG, "stopProcessingInternal: Menghentikan perekaman audio.")
            audioRecord?.stop() // Hentikan AudioRecord
            audioRecord?.release() // Lepaskan sumber daya AudioRecord
            audioRecord = null
        } else {
            Log.d(TAG, "stopProcessingInternal: Audio tidak merekam.")
        }
    }

    // Objek pendamping untuk memuat pustaka native
    companion object {
        init {
            // Pastikan nama pustaka native sesuai dengan yang Anda buat (lib[nama].so)
            System.loadLibrary("rnnoise_jni")
            Log.d("RnnoisePluginCompanion", "Pustaka native rnnoise_jni dimuat.")
        }
    }

    // Deklarasi fungsi native yang akan dipanggil dari Kotlin
    external fun nativeCreateRnnoise(): Long
    external fun nativeProcessRnnoise(statePtr: Long, input: FloatArray, output: FloatArray)
    external fun nativeDestroyRnnoise(statePtr: Long)
}