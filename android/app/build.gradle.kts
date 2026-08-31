import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing material lives outside every repository and is never committed
// (issue 0005). The path arrives through the environment so a checkout alone
// can never produce a build that claims to be ours.
val signingPropertiesPath: String? = System.getenv("MFA_ANDROID_KEY_PROPERTIES")
val signingProperties = Properties().apply {
    if (signingPropertiesPath != null) {
        val source = file(signingPropertiesPath)
        if (!source.exists()) {
            throw GradleException(
                "MFA_ANDROID_KEY_PROPERTIES points at a missing file: " +
                    signingPropertiesPath
            )
        }
        source.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = signingProperties.isNotEmpty()

// Refused loudly rather than falling back to the debug key. Falling back is
// exactly what issue 0005 was: a release that looked delivered and could never
// update an installed copy from another machine.
if (!hasReleaseSigning &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    throw GradleException(
        "A release build needs MFA_ANDROID_KEY_PROPERTIES pointing at the " +
            "signing properties kept outside this repository."
    )
}

android {
    namespace = "com.mobilefinanceassistant.mobile_finance_assistant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mobilefinanceassistant.mobile_finance_assistant"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Present whenever a release task runs at all: the guard above
            // refuses the build otherwise.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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
