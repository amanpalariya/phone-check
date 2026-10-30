package dev.phonecheck

import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/** Synthetic settings states: no sign-in, pairing, or permission changes. */
@RunWith(AndroidJUnit4::class)
class SettingsUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val signIns = AtomicInteger()
    private val signOuts = AtomicInteger()
    private val unpairs = AtomicInteger()
    private val accessRequests = AtomicInteger()

    @Test fun connectedControlsStayOnGeneral() {
        fixture(signedIn = true, paired = true, access = true).use {
            expect("alex@example.com")
            expect("Mac")
            expect("Connected")
            assertFalse(device.hasObject(By.text("Notification access")))
            screenshot("settings-connected")
            device.findObject(By.text("Sign out")).click()
            expect("Sign out of Phone Check?")
            device.findObject(By.text("Cancel")).click()
            assertEquals(0, signOuts.get())
            device.findObject(By.text("Unpair")).click()
            expect("Unpair Mac?")
            device.findObject(By.text("Cancel")).click()
            assertEquals(0, unpairs.get())
            device.findObject(By.text("Advanced")).click()
            expect("Notification testbed")
            device.findObject(By.desc("Back")).click()
            expect("alex@example.com")
        }
    }

    @Test fun signedOutAndMissingAccessHaveInlineActions() {
        fixture(signedIn = false, paired = false, access = false).use {
            expect("Google account")
            expect("Pair Mac")
            expect("Notification access")
            screenshot("settings-setup")
            device.findObject(By.text("Sign in")).click()
            assertEquals(1, signIns.get())
            device.findObject(By.text("Allow")).click()
            assertEquals(1, accessRequests.get())
        }
    }

    private fun fixture(signedIn: Boolean, paired: Boolean, access: Boolean): ActivityScenario<MainActivity> {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { activity ->
            activity.setContent {
                PhoneCheckTheme {
                    PhoneCheckScreen(
                        signedIn = signedIn, accountName = "Alex Parker", accountEmail = "alex@example.com",
                        onSignIn = { signIns.incrementAndGet() }, onSignOut = { signOuts.incrementAndGet() },
                        paired = paired, localOnly = true, access = access, network = true, networkBlocked = false,
                        listenerReady = true, status = "Connected", code = "", error = null, scanning = false,
                        onCodeChange = {}, onPair = {}, onScan = {}, onNotificationAccess = { accessRequests.incrementAndGet() },
                        onNetworkAccess = {}, onReconnect = {}, onTestbed = {}, onUnpair = { unpairs.incrementAndGet() }
                    )
                }
            }
        }
        expect("Settings", description = true)
        device.findObject(By.desc("Settings")).click()
        expect("General")
        return scenario
    }

    private fun expect(text: String, description: Boolean = false) {
        assertTrue("Missing settings control: $text", device.wait(Until.hasObject(if (description) By.desc(text) else By.text(text)), 10000))
    }

    private fun screenshot(name: String) {
        device.waitForIdle()
        val suffix = InstrumentationRegistry.getArguments().getString("screenshotSuffix", "default")
        assertTrue(device.takeScreenshot(File(instrumentation.targetContext.filesDir, "$name-$suffix.png")))
    }
}
