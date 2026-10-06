import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：从 android/key.properties 读取（真实密钥不要提交到仓库）。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "peli.lcyk.cc"
    compileSdk = flutter.compileSdkVersion
    // 固定 NDK：Android 16 KB page size 合规要求 NDK r28+ 与 AGP >= 8.5.1。
    // 写死版本避免不同机器解析到不同 NDK 导致 .so 对齐行为不一致。
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "peli.lcyk.cc"
        // 沿用 Flutter 的默认 minSdk（当前为 24）；两个加密插件的要求都低于它。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 只打 64 位 ARM：2019 年后的 Android 设备都是 arm64，可显著减小包体。
        //
        // 注意：这条过滤只在 `android/gradle.properties` 里设了
        // `disable-abi-filtering=true` 时才生效 —— 否则 Flutter 的 Gradle 插件会
        // 按 target-platform 推导出三种 ABI 并把这里的选择清掉（见该文件的说明）。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 暂不开启 R8 代码压缩：Flutter embedding 引用了 Play Core 的延迟组件类，
            // 缺少对应依赖时 R8 会直接失败。等接入 Play Feature Delivery 或补上
            // `com.google.android.play:feature-delivery` 依赖后再打开。
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
