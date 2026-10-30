package dev.phonecheck

import android.app.NotificationManager
import android.os.Bundle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in two-device check: operate the synthetic player from the paired Mac panel. */
@RunWith(AndroidJUnit4::class)
class PhysicalMediaTest {
    @Test fun controlsFromPairedMacReachSessionAndLegacyActions() {
        org.junit.Assume.assumeTrue(androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("physicalMedia") == "true")
        val screen = ActivityScenario.launch(NotificationTestbedActivity::class.java)
        val manager = target.getSystemService(NotificationManager::class.java)
        fun status(phase: String) = instrumentation.sendStatus(2, Bundle().apply { putString("stream", "\nMedia check: $phase\n") })
        try {
            onMain { assertTrue("Allow testbed notifications in Phone Check first", manager.areNotificationsEnabled()) }
            waitFor("notification listener", 20000) { var ready = false; onMain { ready = BridgeState.listenerReady }; ready }
            val sessionOperations = listOf("play", "pause", "next", "previous", "like", "seek")
            var baseline = emptyMap<String, Int>()
            onMain {
                baseline = sessionOperations.associateWith { TestbedState.operations[it] ?: 0 }
                TestNotifications.post(target, DemoScenario.MEDIA)
            }
            status("session ready; use Play, Pause, Next, Previous, Me gusta, seek on Mac")
            waitFor("Mac session controls", 180000) {
                var done = false
                onMain { done = sessionOperations.all { (TestbedState.operations[it] ?: 0) > baseline.getValue(it) } }
                done
            }
            onMain {
                manager.cancel(TestNotifications.TAG, DemoScenario.MEDIA.number)
                TestbedMediaSession.clear()
                baseline = sessionOperations.associateWith { TestbedState.operations[it] ?: 0 }
                TestNotifications.post(target, DemoScenario.MEDIA_LEGACY)
            }
            status("legacy ready; use Anterior, Reproducir, Siguiente on Mac")
            waitFor("Mac legacy controls", 180000) {
                var done = false
                onMain { done = listOf("play", "next", "previous").all { (TestbedState.operations[it] ?: 0) > baseline.getValue(it) } }
                done
            }
            status("all session and legacy actions received")
        } finally {
            onMain {
                manager.cancel(TestNotifications.TAG, DemoScenario.MEDIA.number)
                manager.cancel(TestNotifications.TAG, DemoScenario.MEDIA_LEGACY.number)
                TestbedMediaSession.clear()
            }
            screen.close()
        }
    }
}
