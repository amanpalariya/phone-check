package dev.phonecheck

import android.app.NotificationManager
import android.content.ComponentName
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileInputStream
import java.net.Socket
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class PermissionUiTest {
    @Test fun pairingAndDeniedPermissionStates() {
        val manager = target.getSystemService(NotificationManager::class.java)
        assertFalse(manager.isNotificationListenerAccessGranted(ComponentName(target, NotificationBridge::class.java)))
        onMain { PairingStore(target).clear(); BridgeState.paired = false }
        val device = UiDevice.getInstance(instrumentation)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            assertTrue(device.wait(Until.hasObject(By.text("Pair Mac")), 10000))
            assertTrue(device.hasObject(By.text("Mac pairing code")))
            device.takeScreenshot(File(target.filesDir, "pairing-screen.png"))
            device.findObject(By.clazz("android.widget.EditText")).text = File(target.filesDir, "e2e-pairing").readText()
            device.wait(Until.findObject(By.text("Pair Mac").enabled(true)), 5000)!!.click()
            assertTrue(device.wait(Until.hasObject(By.text("Allow notification access")), 10000))
            device.takeScreenshot(File(target.filesDir, "notification-access-screen.png"))
            shell("cmd notification allow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
            waitFor("listener connected") {
                var ready = false; onMain { ready = BridgeState.listenerReady }; ready
            }
            scenario.recreate()
            assertTrue(device.wait(Until.hasObject(By.text("Allow local network")), 10000))
            var status = ""; onMain { status = BridgeState.status }
            assertEquals("Allow local network", status)
            device.takeScreenshot(File(target.filesDir, "local-network-screen.png"))
        }
    }
}

@RunWith(AndroidJUnit4::class)
class NotificationFlowTest {
    @Test fun realListenerMirrorUpdateDismissAndReconnect() {
        shell("am broadcast -f 0x20 -n dev.phonecheck.fixture/.FixtureReceiver -a fixture.CLEAR_ALL")
        waitFor("listener connected") {
            var ready = false; onMain { ready = BridgeState.listenerReady }; ready
        }
        onMain { assertNotNull(PairingStore(target).load()); BridgeState.service!!.restart() }
        waitFor("authenticated snapshot") { host().getBoolean("connected") }
        assertTrue(host().getBoolean("paired"))

        post(1, "Alpha")
        waitFor("post mirrored") { titles() == listOf("Alpha") }
        post(1, "Beta")
        waitFor("update replaces stable key") { titles() == listOf("Beta") }
        post(1, "Beta")
        SystemClock.sleep(500)
        assertEquals(1, host().getInt("count"))

        host("dismiss", "Beta")
        waitFor("Mac dismissal confirmed") { titles().isEmpty() && host().getInt("pending") == 0 }
        assertEquals("", host().getString("error"))
        var phoneRemoved = false
        onMain { phoneRemoved = BridgeState.service!!.activeNotifications.none { it.packageName == "dev.phonecheck.fixture" } }
        assertTrue("Actual phone notification removed", phoneRemoved)

        post(2, "PhoneClear")
        waitFor("second post") { titles() == listOf("PhoneClear") }
        clear(2)
        waitFor("phone removal clears Mac") { titles().isEmpty() }

        post(3, "Reconnect")
        waitFor("pre-reconnect notification") { titles() == listOf("Reconnect") }
        val previousConnections = host().getInt("connections")
        onMain { BridgeState.service!!.restart() }
        waitFor("reconnect snapshot") {
            val state = host()
            state.getInt("connections") > previousConnections && state.getBoolean("connected") && titles() == listOf("Reconnect")
        }
        assertEquals(1, host().getInt("count"))
        clear(3)
        waitFor("removal after reconnect") { titles().isEmpty() }

        post(4, "Ongoing", ongoing = true)
        waitFor("ongoing mirrored") { titles() == listOf("Ongoing") }
        assertEquals("Non-clearable metadata", 1, host().getInt("blocked"))
        host("dismiss", "Ongoing")
        SystemClock.sleep(500)
        assertEquals(listOf("Ongoing"), titles())
        assertEquals(0, host().getInt("pending"))
        clear(4)
        waitFor("fixture cleanup") { titles().isEmpty() }

        // Revoking special notification access must tear down the real listener link.
        shell("cmd notification disallow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        waitFor("revocation disconnects Mac") { !host().getBoolean("connected") }
        shell("cmd notification allow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        waitFor("restore reconciles") { host().getBoolean("connected") }
        assertEquals(0, host().getInt("count"))
    }
}
