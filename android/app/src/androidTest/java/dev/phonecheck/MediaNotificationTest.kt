package dev.phonecheck

import android.app.Notification
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual OS controller binder, with no paired devices or notification permission needed. */
@RunWith(AndroidJUnit4::class)
class MediaNotificationTest {
    @Test fun controlsSurvivePresentationUpdatesAndSeekingRemainsTrackBound() {
        lateinit var session: MediaSession
        lateinit var capture: NotificationCapture
        lateinit var sbn: StatusBarNotification
        lateinit var first: CapturedNotice
        lateinit var commands: NotificationCommandHandler
        var setup = false
        var skips = 0
        var seeks = 0
        var soughtPosition = -1L
        var updates = 0
        val results = mutableListOf<String>()
        fun metadata(title: String) = MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, 100000).build()
        fun state(position: Long) = PlaybackState.Builder().setState(PlaybackState.STATE_PAUSED, position, 0f)
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SEEK_TO).build()
        fun command(id: String, handle: CapturedAction, position: Long? = null, revision: String = mediaCapabilityRevision(handle.id)): JSONObject {
            val now = System.currentTimeMillis()
            return JSONObject().put("type", "action").put("command", id).put("key", sbn.key)
                .put("revision", revision).put("action", handle.id).put("sentAt", now).put("expiresAt", now + 8000)
                .also { if (position != null) it.put("position", position) }
        }
        try {
            onMain {
                session = MediaSession(target, "Media capture test")
                session.setCallback(object : MediaSession.Callback() {
                    override fun onSkipToNext() { skips++; session.setMetadata(metadata("Second track")) }
                    override fun onSeekTo(pos: Long) { seeks++; soughtPosition = pos; session.setPlaybackState(state(pos)) }
                }, Handler(Looper.getMainLooper()))
                session.setMetadata(metadata("First track")); session.setPlaybackState(state(1000)); session.isActive = true
                val notification = Notification.Builder(target, "test").setSmallIcon(R.drawable.ic_bell)
                    .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken)).build()
                fun notice(postedAt: Long) = StatusBarNotification(target.packageName, target.packageName, 111, TestNotifications.TAG,
                    Process.myUid(), 0, 0, notification, Process.myUserHandle(), postedAt)
                sbn = notice(1000)
                capture = NotificationCapture(target, Handler(Looper.getMainLooper())) { updates++ }; setup = true
                first = capture.capture(sbn)!!
                assertEquals("First track", first.json.getString("title"))
                assertEquals(listOf("play", "next", "seek"), first.actions.map { it.media?.operation })
                assertEquals(first.json.getString("revision"), capture.capture(sbn)!!.json.getString("revision"))
                commands = NotificationCommandHandler(target, capture, Handler(Looper.getMainLooper()),
                    { true }, { arrayOf(sbn) }, {}, { _, status -> results += status }, { fail("Protocol error") })
                val next = first.actions.first { it.media?.operation == "next" }
                // Reproduce continuous playback and notification reposts between display and click.
                session.setPlaybackState(state(2500)); sbn = notice(2000)
                assertNotEquals(first.json.getString("revision"), capture.capture(sbn)!!.json.getString("revision"))
                commands.handle(command("stale", next, revision = "0".repeat(64)))
                val skip = command("skip", next)
                commands.handle(skip); commands.handle(skip)
                assertEquals(listOf("changed", "sent", "sent"), results)
            }
            waitFor("exactly one skip and metadata callback", 5000) {
                var done = false; onMain { done = skips == 1 && updates > 0 }; done
            }
            onMain {
                val changed = capture.capture(sbn)!!
                assertEquals("Second track", changed.json.getString("title"))
                val oldSeek = first.actions.first { it.media?.operation == "seek" }
                val seek = changed.actions.first { it.media?.operation == "seek" }
                assertNotEquals(oldSeek.id, seek.id)
                assertEquals(first.actions.first { it.media?.operation == "next" }.id, changed.actions.first { it.media?.operation == "next" }.id)
                commands.handle(command("old-track", oldSeek, 40000))
                assertEquals("changed", results.last())
                commands.handle(command("out-of-range", seek, 100001))
                assertEquals("unsupported_input", results.last())
                session.setPlaybackState(state(3000)) // Presentation changes again before seeking.
                val seekCommand = command("seek", seek, 40000)
                commands.handle(seekCommand); commands.handle(seekCommand)
                assertEquals(listOf("sent", "sent"), results.takeLast(2))
            }
            waitFor("exactly one seek", 5000) {
                var done = false; onMain { done = seeks == 1 }; done
            }
            onMain { assertEquals(40000L, soughtPosition) }
        } finally { onMain { if (setup) { capture.clear(); session.release() } } }
    }
}
