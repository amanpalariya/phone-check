package dev.phonecheck

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Optional foreground Mac test. Only synthetic notifications reach the test app's center. */
@RunWith(AndroidJUnit4::class)
class NativeAlertSmokeTest {
    @Test fun nativeCenterReceivesTextImageAndReplyCategories() {
        val previous = host().getInt("connections")
        shell("cmd notification disallow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        shell("cmd notification allow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        waitFor("listener ready") { var ready = false; onMain { ready = BridgeState.listenerReady }; ready }
        onMain {
            if (PairingStore(target).load() == null) PairingStore(target).save(Pairing.parse(File(target.filesDir, "e2e-pairing").readText()))
            TestNotifications.clear(target)
            BridgeState.service!!.restart()
        }
        // A post included in the initial snapshot is intentionally silent. Test live delivery
        // only after this instrumentation process has established its own new session.
        waitFor("fresh live session") {
            var connected = false; onMain { connected = BridgeState.status == "Connected" }
            connected && host().getBoolean("connected") && host().getInt("connections") > previous
        }
        host("authorize")
        var allowed = false
        val end = android.os.SystemClock.elapsedRealtime() + 45000
        while (android.os.SystemClock.elapsedRealtime() < end) {
            if (host().getBoolean("alertsAllowed")) { allowed = true; break }
            android.os.SystemClock.sleep(250)
        }
        assumeTrue("Mac test-app notification authorization was not granted", allowed)
        // Native alert delivery is intentionally suppressed while the phone is in use.
        val device = UiDevice.getInstance(instrumentation)
        device.sleep()
        waitFor("phone no longer in use") { !PhoneAttention(target).isInUse() }
        try {
            onMain { TestNotifications.post(target, DemoScenario.BASIC) }
            waitFor("native text notification delivered") { host().getJSONArray("delivered").length() >= 1 }
            onMain { TestNotifications.post(target, DemoScenario.PICTURE) }
            waitFor("native image attachment delivered") { host().getBoolean("deliveredImage") }
            onMain { TestNotifications.post(target, DemoScenario.CHAT) }
            waitFor("native text-input action registered") { host().getBoolean("nativeReply") }
            val actions = host().getJSONArray("nativeButtons")
            assertTrue((0 until actions.length()).any { actions.getString(it) == "Dismiss on phone" })
            host("native", "Sample chat", "Reply", "Native smoke reply")
            waitFor("native reply handler dispatches RemoteInput") {
                var received = false; onMain { received = TestbedState.lastReply == "Native smoke reply" }; received
            }
            host("dismiss", "Basic")
            waitFor("native delivered copy withdrawn on phone removal") {
                val keys = host().getJSONArray("delivered")
                (0 until keys.length()).none { keys.getString(it).contains("|101|") }
            }
            onMain { TestNotifications.clear(target) }
            waitFor("native test notifications cleared") { host().getJSONArray("delivered").length() == 0 }
        } finally { device.wakeUp() }
    }
}
