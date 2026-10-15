import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing: android/key.properties (storeFile relative to android/app)
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
// CI test packages must opt in explicitly. A normal release build never
// silently falls back to the debug key.
val allowTestSigning = providers.gradleProperty("overtoneAllowTestSigning")
    .map { it == "true" }.getOrElse(false)
// CI uses environment variables instead of writing passwords into key.properties.
val releaseSigning = mapOf(
    "storeFile" to "OVERTONE_KEYSTORE_FILE",
    "storePassword" to "OVERTONE_STORE_PASSWORD",
    "keyAlias" to "OVERTONE_KEY_ALIAS",
    "keyPassword" to "OVERTONE_KEY_PASSWORD",
).mapValues { (property, environment) ->
    keystoreProperties.getProperty(property)
        ?: providers.environmentVariable(environment).orNull
}
val hasReleaseSigning = releaseSigning.values.all { !it.isNullOrBlank() }
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (isReleaseTask && !hasReleaseSigning && !allowTestSigning) {
    throw GradleException(
        "Release signing is missing or incomplete. Configure key.properties or OVERTONE_* signing environment variables, or explicitly " +
        "use -PovertoneAllowTestSigning=true for a TEST-ONLY artifact."
    )
}

android {
    namespace = "com.kugo.kugo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = releaseSigning.getValue("keyAlias")
                keyPassword = releaseSigning.getValue("keyPassword")
                storeFile = file(releaseSigning.getValue("storeFile")!!)
                storePassword = releaseSigning.getValue("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.kugo.kugo"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else if (allowTestSigning) {
                signingConfigs.getByName("debug")
            } else {
                null
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
