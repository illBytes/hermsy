import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push needs the Firebase config downloaded from the console. Without it the
// app still builds; push simply stays off.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// A release key of your own, if android/key.properties names one (it and
// the keystore stay out of git). Without it, release builds are signed with
// this computer's debug key, which installs over a debug build in place.
val releaseKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.hermes.hermes_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Hermsy's permanent ID on Google Play, under illbytes. It can never
        // change once published. (The Kotlin package stays com.hermes.)
        applicationId = "com.illbytes.hermsy_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKey.getProperty("storeFile") != null) {
            create("release") {
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    // prod is Hermsy for daily use and Google Play, a release build: not
    // debuggable, so a computer on USB cannot read its files or attach to
    // it. dev is "Hermsy Dev", installed beside it for `flutter run`, with
    // its own data.
    // Each flavor names its app ("Hermsy", "Hermsy Dev").
    buildFeatures {
        resValues = true
    }
    flavorDimensions += "app"
    productFlavors {
        create("prod") {
            dimension = "app"
            resValue("string", "app_name", "Hermsy")
        }
        create("dev") {
            dimension = "app"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Hermsy Dev")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

// Push needs each app registered in Firebase. An app the downloaded
// google-services.json does not list yet builds without push; once it is
// registered and the file downloaded again, push turns on by itself.
val firebaseApps = file("google-services.json").let { config ->
    if (config.exists()) config.readText() else ""
}
fun firebaseKnows(packageName: String) =
    firebaseApps.contains("\"package_name\": \"$packageName\"")
tasks.configureEach {
    if (name.startsWith("process") && name.endsWith("GoogleServices")) {
        val dev = name.contains("Dev")
        val packageName = "com.illbytes.hermsy_app" + if (dev) ".dev" else ""
        if (!firebaseKnows(packageName)) {
            enabled = false
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
