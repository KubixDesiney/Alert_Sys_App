import java.util.Properties

val flutterSdkPath: String = run {
    val properties = Properties()
    file("local.properties").inputStream().use { properties.load(it) }
    properties.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")
}

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

rootProject.name = "alertsysapp"
include(":app")
