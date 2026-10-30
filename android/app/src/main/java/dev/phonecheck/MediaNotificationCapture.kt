package dev.phonecheck

import android.app.Notification
import android.content.Context
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.util.UUID

/** Local-only capability. Session tokens and custom command IDs never cross the wire. */
internal data class MediaCapability(
    val controller: MediaController,
    val operation: String,
    val title: String,
    val custom: PlaybackState.CustomAction? = null,
    val itemIdentity: String? = null
) {
    fun matches(other: MediaCapability) = controller.sessionToken == other.controller.sessionToken &&
        operation == other.operation && itemIdentity == other.itemIdentity && custom?.action == other.custom?.action && title == other.title
    fun describe(id: String, images: NotificationImages): JSONObject = JSONObject()
        .put("id", id).put("title", title).put("input", false).put("freeform", false)
        .put("choices", org.json.JSONArray()).put("enabled", true)
        .put("revision", mediaCapabilityRevision(id)).put("requiresUnlock", false).put("destructive", false).put("mediaControl", operation)
        .also { json -> custom?.let {
            if (it.icon != 0) images.actionIcon(Icon.createWithResource(controller.packageName, it.icon))?.let { icon -> json.put("icon", icon) }
        } }
    fun execute(position: Long? = null) {
        val controls = controller.transportControls
        when (operation) {
            "play" -> controls.play()
            "pause" -> controls.pause()
            "previous" -> controls.skipToPrevious()
            "next" -> controls.skipToNext()
            "rewind" -> controls.rewind()
            "fastForward" -> controls.fastForward()
            "stop" -> controls.stop()
            "seek" -> controls.seekTo(requireNotNull(position))
            "custom" -> custom?.let { controls.sendCustomAction(it.action, it.extras) }
        }
    }
}

internal data class CapturedMedia(
    val json: JSONObject, val actions: List<CapturedAction>, val title: String?, val artist: String?, val artwork: String?
)

/** Read the exact session attached to a notification, never a package-wide guessed player. */
internal class MediaNotificationCapture(
    private val context: Context, private val handler: Handler, private val changed: (String) -> Unit
) {
    private data class Binding(val controller: MediaController, val callback: MediaController.Callback)
    private val clockOffset = System.currentTimeMillis() - SystemClock.elapsedRealtime()
    private val bindings = mutableMapOf<String, Binding>()
    private val destroyed = mutableMapOf<String, MediaSession.Token>()
    fun clear() { bindings.keys.toList().forEach(::remove); destroyed.clear() }
    fun remove(key: String) {
        bindings.remove(key)?.let { runCatching { it.controller.unregisterCallback(it.callback) } }
        destroyed.remove(key)
    }
    @Suppress("DEPRECATION")
    fun read(sbn: StatusBarNotification, previous: List<CapturedAction>, images: NotificationImages): CapturedMedia? = runCatching {
        val extras = sbn.notification.extras
        val token = if (Build.VERSION.SDK_INT >= 33) extras.getParcelable(Notification.EXTRA_MEDIA_SESSION, MediaSession.Token::class.java)
            else extras.getParcelable<MediaSession.Token>(Notification.EXTRA_MEDIA_SESSION)
        if (token == null) { remove(sbn.key); return null }
        if (destroyed[sbn.key] == token) return null
        var binding = bindings[sbn.key]
        if (binding?.controller?.sessionToken != token) {
            remove(sbn.key)
            val controller = MediaController(context, token)
            // An unrelated token must never give this notification another app's controls.
            if (controller.packageName != sbn.packageName) return null
            val callback = object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) { if (bindings[sbn.key]?.controller?.sessionToken == token) changed(sbn.key) }
                override fun onMetadataChanged(metadata: MediaMetadata?) { if (bindings[sbn.key]?.controller?.sessionToken == token) changed(sbn.key) }
                override fun onSessionDestroyed() {
                    if (bindings[sbn.key]?.controller?.sessionToken != token) return
                    remove(sbn.key); destroyed[sbn.key] = token; changed(sbn.key)
                }
            }
            controller.registerCallback(callback, handler)
            binding = Binding(controller, callback)
            bindings[sbn.key] = binding
        }
        val controller = binding.controller
        val state = controller.playbackState ?: return null // Legacy notification-action fallback.
        val metadata = controller.metadata
        val playing = state.state in listOf(PlaybackState.STATE_PLAYING, PlaybackState.STATE_FAST_FORWARDING, PlaybackState.STATE_REWINDING, PlaybackState.STATE_SKIPPING_TO_NEXT, PlaybackState.STATE_SKIPPING_TO_PREVIOUS, PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM)
        val buffering = state.state == PlaybackState.STATE_BUFFERING || state.state == PlaybackState.STATE_CONNECTING
        val capabilities = mutableListOf<MediaCapability>()
        fun add(flag: Long, operation: String, title: String) {
            if (state.actions and flag != 0L) capabilities += MediaCapability(controller, operation, title)
        }
        add(PlaybackState.ACTION_SKIP_TO_PREVIOUS, "previous", "Previous")
        if (playing || buffering) add(PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE, "pause", "Pause")
        else add(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PLAY_PAUSE, "play", "Play")
        add(PlaybackState.ACTION_SKIP_TO_NEXT, "next", "Next")
        add(PlaybackState.ACTION_REWIND, "rewind", "Rewind")
        add(PlaybackState.ACTION_FAST_FORWARD, "fastForward", "Fast forward")
        add(PlaybackState.ACTION_STOP, "stop", "Stop")
        state.customActions.take(5).forEach {
            capabilities += MediaCapability(controller, "custom", it.name.toString().take(128), it)
        }
        if (state.actions and PlaybackState.ACTION_SEEK_TO != 0L && (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0) > 0) {
            val identity = listOf(MediaMetadata.METADATA_KEY_MEDIA_ID, MediaMetadata.METADATA_KEY_TITLE,
                MediaMetadata.METADATA_KEY_ARTIST).map { metadata?.getText(it)?.toString() }
                .joinToString("\u0000") + ":" + metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION)
            capabilities += MediaCapability(controller, "seek", "Seek", itemIdentity = identity)
        }
        val actions = capabilities.map { capability ->
            val old = previous.firstOrNull { it.media?.matches(capability) == true }
            CapturedAction(old?.id ?: UUID.randomUUID().toString(),
                Notification.Action.Builder(null, capability.title, null).build(), capability)
        }
        val json = JSONObject().put("playing", playing).put("buffering", buffering)
            .put("position", state.position.coerceAtLeast(0)).put("duration", metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION)?.coerceAtLeast(0) ?: 0)
            .put("speed", if (playing) state.playbackSpeed.toDouble() else 0.0)
            .put("updatedAt", clockOffset + state.lastPositionUpdateTime)
        fun text(key: String) = metadata?.getText(key)?.toString()?.take(2048)?.takeIf { it.isNotBlank() }
        CapturedMedia(json, actions, text(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: text(MediaMetadata.METADATA_KEY_TITLE),
            text(MediaMetadata.METADATA_KEY_ARTIST) ?: text(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: text(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE),
            images.artwork(metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART) ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)))
    }.getOrNull()
}

// Media commands bind to a live opaque capability, independently of presentation revisions.
internal fun mediaCapabilityRevision(id: String): String = java.security.MessageDigest.getInstance("SHA-256")
    .digest(("phonecheck-media/" + id).toByteArray()).joinToString("") { "%02x".format(it) }
