// Test-only notification producer. Never included in the Phone Check application.
plugins { id("com.android.application") }
android {
    namespace = "dev.phonecheck.fixture"
    compileSdk { version = release(37) { minorApiLevel = 0 } }
    defaultConfig {
        applicationId = "dev.phonecheck.fixture"
        minSdk = 30
        targetSdk = 37
        versionCode = 1
        versionName = "1"
    }
}
