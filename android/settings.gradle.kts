// android/settings.gradle.kts
pluginManagement {
    // Resolve Flutter SDK path from local.properties
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        val path = props.getProperty("flutter.sdk")
        require(path != null) { "flutter.sdk not set in local.properties" }
        path
    }

    // Required for Flutter integration
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

/**
 * Pin plugin versions here so subprojects can "apply" them without
 * re-specifying versions (avoids classpath conflicts).
 */
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.25" apply false
}

include(":app")
