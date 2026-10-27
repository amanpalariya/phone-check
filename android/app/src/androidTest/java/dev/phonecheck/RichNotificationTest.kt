package dev.phonecheck

import android.app.Notification
import android.app.NotificationManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class RichNotificationTest {
    private var screen: ActivityScenario<NotificationTestbedActivity>? = null
    @After fun closeTestbed() {
        onMain { TestNotifications.clear(target) }
        screen?.onActivity { it.finish() }
        screen = null
    }
    @Before fun connectAndClearSamples() {
        shell("cmd notification disallow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        shell("cmd notification allow_listener dev.phonecheck/dev.phonecheck.NotificationBridge")
        waitFor("listener ready") { var ready = false; onMain { ready = BridgeState.listenerReady }; ready }
        onMain {
            if (PairingStore(target).load() == null) PairingStore(target).save(Pairing.parse(File(target.filesDir, "e2e-pairing").readText()))
            BridgeState.service!!.restart()
        }
        waitFor("connected") { host().getBoolean("connected") }
        onMain { TestNotifications.clear(target) }
        waitFor("clean testbed") { samples().isEmpty() }
        screen = ActivityScenario.launch(NotificationTestbedActivity::class.java)
    }
    @Test fun allScenariosExposeExpectedContentIconsAndCapabilities() {
        onMain { DemoScenario.entries.forEach { TestNotifications.post(target, it) } }
        waitFor("all samples mirrored") { samples().size >= DemoScenario.entries.size + 2 }
        val notices = samples()
        val kinds = notices.map { it.getString("kind") }.toSet()
        assertTrue(kinds.containsAll(setOf("basic", "bigText", "inbox", "messaging", "picture", "progress", "media", "call", "custom")))
        assertTrue(notices.all { it.getBoolean("hasIcon") })
        assertTrue(sample("Expanded text").getInt("bodyLength") > 400)
        assertEquals(3, sample("Inbox").getInt("lineCount"))
        assertEquals(2, sample("Sample chat").getInt("messageCount"))
        assertTrue(sample("Picture").getBoolean("hasImage"))
        assertTrue(sample("Grouped").getBoolean("summary"))
        assertEquals(3, notices.count { it.getBoolean("grouped") && it.getString("title").startsWith("Grouped") })
        assertFalse(sample("Non-dismissible").getBoolean("dismissible"))
        assertTrue(sample("Attachment action").getInt("disabledActions") > 0)
        assertTrue(sample("Multiple inputs").getInt("disabledActions") > 0)
        assertEquals(1, sample("Suggested replies").getInt("replyActions"))
        onMain { TestNotifications.clear(target) }
        waitFor("all samples removed") { samples().isEmpty() }
    }
    @Test fun buttonsAndInlineRepliesExecuteRealPendingIntents() {
        onMain { TestNotifications.post(target, DemoScenario.ACTIONS); TestNotifications.post(target, DemoScenario.CHAT) }
        waitFor("action notices") { samples().size == 2 }
        val archiveBefore = operationCount("archive")
        host("native", "Action buttons", "Archive")
        waitFor("archive receiver ran") {
            val error = host().getString("error")
            if (error.isNotEmpty()) fail("Archive feedback: $error")
            operationCount("archive") > archiveBefore
        }
        waitFor("archive removal mirrored") { samples().none { it.getString("title") == "Action buttons" } }
        val replyBefore = operationCount("reply")
        host("native", "Sample chat", "Reply", "Test reply ✓")
        waitFor("RemoteInput received") { operationCount("reply") > replyBefore }
        var replyCorrect = false
        onMain { replyCorrect = TestbedState.lastReply == "Test reply ✓" }
        assertTrue("The receiver got the exact RemoteInput text", replyCorrect)
        waitFor("reply command finished") { host().getInt("pending") == 0 }
        onMain { TestNotifications.post(target, DemoScenario.CHOICES) }
        waitFor("suggestions mirrored") { samples().any { it.getString("title") == "Suggested replies" } }
        val choiceBefore = operationCount("reply")
        host("reply", "Suggested replies", "Respond", "Later")
        waitFor("choice response received") { operationCount("reply") > choiceBefore }
        onMain { replyCorrect = TestbedState.lastReply == "Later" }
        assertTrue("Fixed choices use the original result key", replyCorrect)
    }
    @Test fun mediaAndCallControlsReachTheirReceivers() {
        onMain { TestNotifications.post(target, DemoScenario.MEDIA); TestNotifications.post(target, DemoScenario.CALL) }
        waitFor("media and call mirrored") { samples().size == 2 }
        for (action in listOf("Play", "Pause", "Next")) {
            val revision = sample("Media").getString("revision")
            val operation = action.lowercase()
            val before = operationCount(operation)
            host("perform", "Media", action)
            waitFor("media control received") { operationCount(operation) > before }
            waitFor("media update and result") { host().getInt("pending") == 0 && sample("Media").getString("revision") != revision }
        }
        val call = samples().first { it.getString("kind") == "call" }
        val actions = call.getJSONArray("actions")
        val answer = (0 until actions.length()).map { actions.getString(it) }.first { it.contains("Answer", ignoreCase = true) }
        val before = operationCount("answer")
        host("perform", call.getString("title"), answer)
        waitFor("call action received") { operationCount("answer") > before }
        waitFor("call removed") { samples().none { it.getString("kind") == "call" } }
    }
    @Test fun progressAndImageSnapshotsReconcileAcrossReconnect() {
        onMain {
            TestbedState.progress = 25; TestNotifications.post(target, DemoScenario.PROGRESS)
        }
        waitFor("initial progress") { samples().any { it.optInt("progress") == 25 } }
        onMain { TestbedState.progress = 75; TestNotifications.post(target, DemoScenario.PROGRESS) }
        waitFor("updated progress") { samples().size == 1 && samples().first().getInt("progress") == 75 }
        // Force a reconnect payload larger than one transport frame using real picture notifications.
        onMain {
            val manager = target.getSystemService(NotificationManager::class.java)
            val image = Bitmap.createBitmap(480, 240, Bitmap.Config.ARGB_8888)
            val random = java.util.Random(1234)
            val pixels = IntArray(480 * 240) { Color.rgb(random.nextInt(256), random.nextInt(256), random.nextInt(256)) }
            image.setPixels(pixels, 0, 480, 0, 0, 480, 240)
            repeat(60) { index ->
                manager.notify(TestNotifications.TAG, 3000 + index, Notification.Builder(target, "testbed").setSmallIcon(R.drawable.ic_bell)
                    .setContentTitle("Snapshot picture $index").setContentText("Synthetic image")
                    .setStyle(Notification.BigPictureStyle().bigPicture(image)).build())
            }
        }
        waitFor("picture notices posted", 30000) { samples().size == 61 }
        if (samples().none { it.getBoolean("hasImage") }) {
            onMain {
                val extras = BridgeState.service!!.activeNotifications.first { it.id == 3000 }.notification.extras
                val bitmap = extras.getParcelable(Notification.EXTRA_PICTURE, Bitmap::class.java)
                val icon = extras.getParcelable(Notification.EXTRA_PICTURE_ICON, android.graphics.drawable.Icon::class.java)
                instrumentation.sendStatus(2, android.os.Bundle().apply {
                    putString("stream", "\nImage metadata: bitmap=${bitmap?.config}, iconType=${icon?.type}, keys=${extras.keySet().filter { it.contains("picture", true) }}\n")
                })
            }
        }
        waitFor("picture batch", 10000) { samples().count { it.getBoolean("hasImage") } == 60 }
        assertTrue("Snapshot exceeds a single frame", host().getInt("snapshotBytes") > 1048576)
        val previous = host().getInt("connections")
        onMain { BridgeState.service!!.restart() }
        waitFor("atomic rich snapshot", 30000) {
            val state = host()
            state.getBoolean("connected") && state.getInt("connections") > previous && samples().size == 61
        }
        assertEquals(60, samples().count { it.getBoolean("hasImage") })
        assertEquals(75, samples().first { it.getString("kind") == "progress" }.getInt("progress"))
    }
    @Test fun canceledIntentsAndStaleOrExpiredCommandsDoNotExecute() {
        onMain { TestNotifications.post(target, DemoScenario.EXPIRED) }
        waitFor("expired action mirrored") { samples().isNotEmpty() }
        host("perform", "Expired action", "Expired action")
        waitFor("canceled intent failure surfaced") { host().getString("error") == "Action no longer available" }
        assertEquals(0, operationCount("expired"))
        val readBefore = operationCount("read")
        onMain { TestNotifications.post(target, DemoScenario.ACTIONS) }
        waitFor("action available for policy checks") { samples().any { it.getString("title") == "Action buttons" } }
        onMain {
            val service = BridgeState.service!!
            val source = { service.activeNotifications }
            val capture = NotificationCapture(target)
            val notice = source().first { it.tag == TestNotifications.TAG && it.id == DemoScenario.ACTIONS.number }
            val captured = capture.capture(notice)!!
            val action = captured.actions.first { it.action.title == "Mark read" }
            val results = mutableListOf<String>()
            val handler = NotificationCommandHandler(target, capture, Handler(Looper.getMainLooper()), { true }, source,
                { service.cancelNotification(it) }, { _, result -> results += result }, { fail("Unexpected protocol error") })
            val now = System.currentTimeMillis()
            fun command(id: String, revision: String, sent: Long, expires: Long) = JSONObject().put("type", "action")
                .put("command", id).put("key", notice.key).put("revision", revision).put("action", action.id)
                .put("sentAt", sent).put("expiresAt", expires)
            handler.handle(command("expired-check", captured.json.getString("revision"), now - 20000, now - 10000))
            handler.handle(command("stale-check", "0".repeat(64), now, now + 8000))
            val repeated = command("repeat-check", captured.json.getString("revision"), now, now + 8000)
            handler.handle(repeated); handler.handle(repeated)
            assertEquals(listOf("expired", "changed", "sent", "sent"), results)
        }
        waitFor("exactly one side effect for a duplicate command") { operationCount("read") == readBefore + 1 }
        android.os.SystemClock.sleep(200)
        assertEquals(readBefore + 1, operationCount("read"))
    }
    @Test fun contentIntentOpensThePhoneTargetAndDismissalConfirmsRemoval() {
        onMain { TestNotifications.post(target, DemoScenario.BASIC) }
        waitFor("tap notification mirrored") { samples().size == 1 }
        val before = operationCount("open")
        host("open", "Basic")
        waitFor("content PendingIntent reached its Activity") { operationCount("open") > before }
        val device = UiDevice.getInstance(instrumentation)
        assertTrue(device.wait(Until.hasObject(By.text("Notification testbed")), 10000))
        host("dismiss", "Basic")
        waitFor("dismissed on Mac") { samples().isEmpty() }
        var absent = false
        onMain { absent = BridgeState.service!!.activeNotifications.none { it.tag == TestNotifications.TAG && it.id == DemoScenario.BASIC.number } }
        assertTrue("Removal is confirmed by Android active state", absent)
    }
    @Test fun testbedScreenAndAndroidAdaptiveIconArePresent() {
        assertTrue("The Mac host has the packaged app icon", host().getBoolean("appIconPresent"))
        val info = target.packageManager.getApplicationInfo(target.packageName, 0)
        assertTrue(info.icon != 0)
        assertTrue(target.packageManager.getApplicationIcon(target.packageName) is android.graphics.drawable.AdaptiveIconDrawable)
        val device = UiDevice.getInstance(instrumentation)
        assertTrue(device.wait(Until.hasObject(By.text("Notification testbed")), 10000))
        assertTrue(device.hasObject(By.text("Post all samples")))
        device.takeScreenshot(File(target.filesDir, "testbed-screen.png"))
    }
    private fun samples(): List<JSONObject> {
        val data = host().getJSONArray("samples")
        return (0 until data.length()).map { data.getJSONObject(it) }
    }
    private fun sample(title: String) = samples().first { it.getString("title") == title }
    private fun operationCount(name: String): Int {
        var count = 0; onMain { count = TestbedState.operations[name] ?: 0 }; return count
    }
}
