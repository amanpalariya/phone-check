package dev.phonecheck

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Production Compose view with synthetic state; no pairing or permission changes. */
@RunWith(AndroidJUnit4::class)
class ProductCaptureTest {
    @Test fun exportAndroidAppIcons() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val manager = instrumentation.context.packageManager
        mapOf("gmail" to "com.google.android.gm", "messages" to "com.google.android.apps.messaging",
            "youtube-music" to "com.google.android.apps.youtube.music").forEach { (name, packageName) ->
            val icon = manager.getApplicationIcon(packageName)
            val bitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888)
            icon.setBounds(0, 0, 192, 192)
            icon.draw(Canvas(bitmap))
            File(instrumentation.targetContext.filesDir, "product-$name.png").outputStream().use {
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
        }
    }

    @Test fun captureReadyState() = captureState(paired = true)
    @Test fun capturePairingState() = captureState(paired = false)
    @Test fun captureScannerState() = captureState(paired = false, scanner = true)

    private fun captureState(paired: Boolean, scanner: Boolean = false) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    PhoneCheckTheme {
                        PhoneCheckScreen(
                            signedIn = false, paired = paired, localOnly = true,
                            access = true, network = true, networkBlocked = false,
                            listenerReady = true, status = "Connected", code = "",
                            error = null, scanning = false, onCodeChange = {},
                            onPair = {}, onScan = { scanPairingCode(activity) { _, _ -> } }, onNotificationAccess = {},
                            onNetworkAccess = {}, onReconnect = {}, onTestbed = {}, onUnpair = {}
                        )
                    }
                }
            }
            assertTrue(device.wait(Until.hasObject(By.text(if (paired) "Connected" else "Pair your Mac")), 10000))
            if (scanner) {
                device.findObject(By.text("Scan QR code")).click()
                assertTrue("Google scanner must open", device.wait(Until.hasObject(By.pkg("com.google.android.gms")), 45000))
                device.waitForIdle()
                Thread.sleep(1200) // Allow the scanner's camera surface to initialize.
                device.dumpWindowHierarchy(File(instrumentation.targetContext.filesDir, "product-scanner.xml"))
            }
            device.waitForIdle()
            assertTrue(device.takeScreenshot(File(instrumentation.targetContext.filesDir, if (scanner) "product-android-scanner.png" else if (paired) "product-android.png" else "product-android-pairing.png")))
        }
    }
}
