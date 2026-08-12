import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.exists()) {
        FileInputStream(releaseSigningPropertiesFile).use(::load)
    }
}
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (isReleaseBuild && !releaseSigningPropertiesFile.exists()) {
    throw GradleException(
        "Missing android/key.properties required for a signed release build.",
    )
}

android {
    namespace = "com.bird.fluidtext"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.bird.fluidtext"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "FluidText"
    }

    signingConfigs {
        create("release") {
            if (releaseSigningPropertiesFile.exists()) {
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
                storeFile = rootProject.file(
                    releaseSigningProperties.getProperty("storeFile"),
                )
                storePassword = releaseSigningProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["appLabel"] = "FluidText Debug"
        }
        maybeCreate("profile").apply {
            initWith(getByName("debug"))
            applicationIdSuffix = ".profile"
            versionNameSuffix = "-profile"
            manifestPlaceholders["appLabel"] = "FluidText Profile"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
