import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.play.publisher)
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingSetting(name: String): String? =
    keystoreProperties.getProperty(name) ?: providers.gradleProperty("subtube.$name").orNull

android {
    namespace = "cc.hafa.subtube"
    compileSdk = 37

    defaultConfig {
        applicationId = "cc.hafa.subtube"
        minSdk = 26
        targetSdk = 37
        versionCode = 2
        versionName = "0.1.1"
    }

    // storeFile, storePassword, keyAlias and keyPassword come from android/keystore.properties
    // (git-ignored), or from -Psubtube.<name> in CI. Without them release is debug-signed, which
    // installs locally but Play won't accept.
    val uploadStoreFile = signingSetting("storeFile")
    signingConfigs {
        if (uploadStoreFile != null) {
            create("upload") {
                storeFile = rootProject.file(uploadStoreFile)
                storePassword = signingSetting("storePassword")
                keyAlias = signingSetting("keyAlias")
                keyPassword = signingSetting("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (uploadStoreFile != null) "upload" else "debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    testOptions {
        unitTests {
            // Robolectric draws the real screens, so it needs the app's resources
            isIncludeAndroidResources = true
            all { test ->
                test.systemProperty("roborazzi.test.record", "true")
                test.systemProperty(
                    "subtube.screenshots",
                    providers.gradleProperty("screenshots").orNull ?: layout.buildDirectory.dir("screenshots").get().asFile.path,
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// publishReleaseBundle uploads to Play; credentials come from ANDROID_PUBLISHER_CREDENTIALS (.github/workflows/android-publish.yml).
play {
    track.set("internal")
    defaultToAppBundles.set(true)
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.webkit)
    implementation(libs.play.services.auth)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.okhttp.coroutines)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
}
