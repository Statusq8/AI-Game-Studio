import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.3.10"
}

val godotVersion = providers.gradleProperty("godotVersion").getOrElse("4.5.1.stable")
val yandexAdsVersion = providers.gradleProperty("yandexAdsVersion").getOrElse("8.6.0")

android {
    namespace = "com.statusq8.yandexads"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    compileOnly("org.godotengine:godot:$godotVersion")
    implementation("com.yandex.android:mobileads:$yandexAdsVersion")
}
