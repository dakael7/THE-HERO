plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Base64
import java.util.Properties
import java.io.FileInputStream

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:-options")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val libEnvFile = rootProject.file("../lib/.env")
val envFileValues: Map<String, String> = if (libEnvFile.exists()) {
    libEnvFile.readLines()
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.startsWith("#") && it.contains("=") }
        .associate { line ->
            val parts = line.split("=", limit = 2)
            parts[0].trim() to parts.getOrElse(1) { "" }.trim()
        }
} else {
    emptyMap()
}

android {
    namespace = "com.theheroprojects.thehero"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Decode dart-defines to obtain GOOGLE_MAPS_API_KEY when passed via `flutter run --dart-define=...`
    val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as? String)
        ?.split(',')
        ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        ?.associate { define: String ->
            val parts = define.split('=', limit = 2)
            parts[0] to parts.getOrElse(1) { "" }
        }
        ?: emptyMap<String, String>()

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.theheroprojects.thehero"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val mapsApiKey =
            dartDefines["GOOGLE_MAPS_API_KEY"]?.trim()?.takeIf { it.isNotEmpty() }
                ?: envFileValues["GOOGLE_MAPS_API_KEY"]?.trim()?.takeIf { it.isNotEmpty() }
                ?: envFileValues["PLACES_API_KEY"]?.trim()?.takeIf { it.isNotEmpty() }
                ?: (project.findProperty("MAPS_API_KEY") as? String)?.trim()
                ?: ""

        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

}
