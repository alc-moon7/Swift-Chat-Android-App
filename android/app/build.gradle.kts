plugins {
    id("com.android.application")
    id("com.google.gms.google-services") 
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin") 
}

android {
    namespace = "com.example.swift_chat" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.13113456"

    defaultConfig {
        applicationId = "com.example.swift_chat"  
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true 
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") 
        }
    }
}

dependencies {
    // Required for Java 8+ APIs on lower API levels
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // If needed, add your other dependencies here
    // implementation("...")
}

flutter {
    source = "../.."  
}
