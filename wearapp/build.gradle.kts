plugins {
}

    android {
    namespace = "com.example.calmguardwear"

    defaultConfig {
      applicationId = "com.example.calmguardwear"
    minSdk = 30
    targetSdk = 36
    versionCode = 1
    versionName = "1.0"

    }

    buildTypes {
       release {
           isMinifyEnabled = false
           proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
       }
    }
    }

  dependencies {
  }