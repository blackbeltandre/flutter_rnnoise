plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
kotlin {
    jvmToolchain(17)
}

android {
    namespace = "com.lintasedu.rnnoise.flutter_rnnoise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.lintasedu.rnnoise.flutter_rnnoise"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ⬇️ Ini diperlukan jika native code perlu akses header JNI
        externalNativeBuild {
            cmake {
                cppFlags += ""
            }
        }

        ndk {
            // Untuk menghindari error ABI
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false       // ❗ Harus true jika shrinkResources = true
            isShrinkResources = false     // ✅ Ubah ini jadi false agar aman
        }
    }


    // ⬇️ Tambahkan ini agar CMakeLists.txt dibaca
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    // ⬇️ Pastikan semua ABI dibangun
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }
}

flutter {
    source = "../.."
}
// Sinkronisasi jvmTarget Kotlin ke 17 agar cocok dengan Java
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions {
        jvmTarget = "17"
    }
}