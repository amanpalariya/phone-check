package dev.phonecheck

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class BatterySyncTest {
    @Test fun batteryUpdatesReconnectsAndClearsWithTheSession() {
        try {
            shell("dumpsys battery unplug")
            shell("cmd power set-mode 0")
            shell("dumpsys battery set level 73")
            shell("dumpsys battery set status 3")
            waitFor("listener ready") { var ready = false; onMain { ready = BridgeState.listenerReady }; ready }
            onMain {
                PairingStore(target).save(Pairing.parse(File(target.filesDir, "e2e-pairing").readText()))
                BridgeState.service!!.restart()
            }
            waitFor("initial battery") { host().optInt("batteryPercentage", -1) == 73 && host().getBoolean("connected") }
            assertFalse(host().getBoolean("batteryCharging"))
            val count = host().getInt("count")
            shell("cmd power set-mode 1")
            waitFor("Battery Saver enabled") { host().getBoolean("batteryPowerSaving") }
            val saverConnections = host().getInt("connections")
            onMain { BridgeState.service!!.restart() }
            waitFor("Battery Saver on reconnect") {
                host().getInt("connections") > saverConnections && host().getBoolean("connected") &&
                    host().getBoolean("batteryPowerSaving")
            }
            shell("cmd power set-mode 0")
            waitFor("Battery Saver disabled") { !host().getBoolean("batteryPowerSaving") }
            shell("dumpsys battery set status 2")
            waitFor("charging") { host().getBoolean("batteryCharging") }
            shell("dumpsys battery set level 19")
            waitFor("low battery") { host().getInt("batteryPercentage") == 19 }
            assertEquals(count, host().getInt("count"))
            val previous = host().getInt("connections")
            onMain { BridgeState.service!!.restart() }
            waitFor("fresh battery on reconnect") {
                val state = host()
                state.getInt("connections") > previous && state.getBoolean("connected") &&
                    state.getInt("batteryPercentage") == 19 && state.getBoolean("batteryCharging")
            }
            shell("cmd notification disallow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
            waitFor("disconnect clears battery") { !host().getBoolean("connected") && host().getInt("batteryPercentage") == -1 }
            shell("dumpsys battery set level 100")
            shell("dumpsys battery set status 5")
            shell("cmd notification allow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
            waitFor("full battery after restore") { host().getBoolean("connected") && host().getInt("batteryPercentage") == 100 }
            assertTrue(host().getBoolean("batteryCharging"))
        } finally {
            shell("cmd power set-mode 0")
            shell("dumpsys battery reset")
            shell("cmd notification allow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        }
    }
}
