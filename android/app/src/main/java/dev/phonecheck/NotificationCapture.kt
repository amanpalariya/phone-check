package dev.phonecheck

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.os.Build
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

internal data class CapturedAction(val id: String, val action: Notification.Action, val media: MediaCapability? = null)
internal data class CapturedNotice(val json: JSONObject, val actions: List<CapturedAction>, val content: PendingIntent?, val contentToken: String? = null)

// Only active notices and their opaque action handles live here. No Intent or RemoteViews
// crosses the wire. Commands must match a fresh capture before any PendingIntent is sent.
internal class NotificationCapture(
    private val context: Context,
    handler: android.os.Handler = android.os.Handler(android.os.Looper.getMainLooper()),
    onMediaChanged: (String) -> Unit = {}
) {
    private val media = MediaNotificationCapture(context, handler, onMediaChanged)
    private val captured = mutableMapOf<String, CapturedNotice>()
    private val images = NotificationImages(context)
    fun clear() { captured.clear(); images.clear(); media.clear() }
    fun remove(key: String) {
        media.remove(key)
        val packageName = captured.remove(key)?.json?.optString("packageName") ?: return
        if (captured.values.none { it.json.optString("packageName") == packageName }) images.removeIcon(packageName)
    }
    fun current(key: String) = captured[key]

    fun capture(sbn: StatusBarNotification): CapturedNotice? {
        if (sbn.packageName == context.packageName && !DevelopmentFeatures.capturesOwnNotification(sbn)) return null
        return try { extract(sbn) } catch (_: Exception) {
            val json = JSONObject().put("key", sbn.key).put("app", sbn.packageName).put("title", "Notification")
                .put("body", "").put("postedAt", sbn.postTime).put("dismissible", sbn.isClearable).put("kind", "custom")
            val revision = MessageDigest.getInstance("SHA-256").digest(json.toString().toByteArray()).joinToString("") { "%02x".format(it) }
            json.put("revision", revision)
            CapturedNotice(json, emptyList(), null).also { captured[sbn.key] = it }
        }
    }
    private fun extract(sbn: StatusBarNotification): CapturedNotice? {
        if (sbn.packageName == context.packageName && !DevelopmentFeatures.capturesOwnNotification(sbn)) return null
        val n = sbn.notification
        val extras = n.extras
        val previous = captured[sbn.key]
        val notificationActions = n.actions.orEmpty().take(6).mapIndexed { index, action ->
            val old = previous?.actions?.getOrNull(index)
            val same = old != null && old.media == null && old.action.actionIntent == action.actionIntent &&
                old.action.title?.toString() == action.title?.toString() &&
                old.action.allInputs().map { it.resultKey } ==
                    action.allInputs().map { it.resultKey }
            CapturedAction(if (same) old!!.id else UUID.randomUUID().toString(), action)
        }
        val session = media.read(sbn, previous?.actions.orEmpty(), images)
        val actions = session?.actions?.takeIf { it.isNotEmpty() } ?: notificationActions
        val app = runCatching {
            context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        }.getOrDefault(sbn.packageName).take(256)
        val template = extras.getString(Notification.EXTRA_TEMPLATE).orEmpty()
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES).orEmpty().take(20).map { it.toString().take(1024) }
        @Suppress("DEPRECATION")
        val bundles = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        val chat = bundles?.let { Notification.MessagingStyle.Message.getMessagesFromBundleArray(it) }.orEmpty()
        val messaging = template.endsWith("MessagingStyle") || chat.isNotEmpty()
        val messages = chat.takeLast(12).map {
            JSONObject().put("sender", (it.senderPerson?.name ?: "You").toString().take(256))
                .put("text", it.text?.toString().orEmpty().take(2048)).put("time", it.timestamp)
                .put("attachment", it.dataMimeType != null)
        }
        val max = extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0).coerceAtLeast(0)
        val progress = extras.getInt(Notification.EXTRA_PROGRESS, 0).coerceIn(0, max.coerceAtLeast(1))
        val indeterminate = extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE, false)
        val kind = when {
            session != null -> "media"
            messaging -> "messaging"
            template.endsWith("BigPictureStyle") -> "picture"
            template.endsWith("InboxStyle") -> "inbox"
            (template.endsWith("MediaStyle") || template.endsWith("DecoratedMediaCustomViewStyle")) || n.category == Notification.CATEGORY_TRANSPORT -> "media"
            template.endsWith("CallStyle") || n.category == Notification.CATEGORY_CALL -> "call"
            max > 0 || indeterminate -> "progress"
            template.endsWith("BigTextStyle") -> "bigText"
            n.contentView != null || n.bigContentView != null -> "custom"
            else -> "basic"
        }
        val title = (extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE) ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString().orEmpty().take(2048)
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty().take(8192)
        val json = JSONObject().put("key", sbn.key).put("app", app).put("packageName", sbn.packageName)
            .put("title", title).put("body", body).put("postedAt", sbn.postTime).put("dismissible", sbn.isClearable)
            .put("kind", kind).put("lines", JSONArray(lines)).put("messages", JSONArray(messages))
            .put("ongoing", n.flags and Notification.FLAG_ONGOING_EVENT != 0)
            .put("groupSummary", n.flags and Notification.FLAG_GROUP_SUMMARY != 0)
            .put("openable", n.contentIntent != null).put("actions", JSONArray(actions.map { describe(it, kind == "media") }))
        if (kind == "media") {
            session?.let {
                json.put("media", it.json)
                it.title?.let { title -> json.put("title", title) }
                it.artist?.let { artist -> json.put("body", artist) }
                it.artwork?.let { artwork -> json.put("image", artwork) }
            }
            if (!json.has("image")) images.actionArtwork(n)?.let { json.put("image", it) }
        }
        images.appIcon(sbn.packageName)?.let { json.put("appIcon", it) }
        if (sbn.isGroup) json.put("groupKey", sbn.groupKey.take(4096))
        if (max > 0 || indeterminate) json.put("progress", JSONObject().put("value", progress).put("max", max).put("indeterminate", indeterminate))
        if (kind == "picture") images.picture(n)?.let { json.put("image", it) }
        val contentToken = if (n.contentIntent == null) null else if (previous?.content == n.contentIntent) previous.contentToken else UUID.randomUUID().toString()
        // Automatic grouping and icon rendering can change without changing a capability.
        // Keep those presentation-only fields out of command revision checks.
        val version = JSONObject(json.toString())
        version.remove("groupKey"); version.remove("appIcon")
        version.put("contentToken", contentToken)
        val bytes = MessageDigest.getInstance("SHA-256").digest(version.toString().toByteArray())
        json.put("revision", bytes.joinToString("") { "%02x".format(it) })
        return CapturedNotice(json, actions, n.contentIntent, contentToken).also { captured[sbn.key] = it }
    }
    private fun describe(handle: CapturedAction, includeIcon: Boolean): JSONObject {
        val action = handle.action
        if (handle.media != null) return handle.media.describe(handle.id, images)
        val inputs = action.allInputs()
        val text = inputs.filter { !it.isDataOnly }
        val input = text.singleOrNull()
        val supported = inputs.isEmpty() || (text.size == 1 && inputs.none { it.isDataOnly } &&
            (input!!.allowFreeFormInput || !input.choices.isNullOrEmpty()))
        return JSONObject().put("revision", if (includeIcon) mediaCapabilityRevision(handle.id) else null).put("icon", if (includeIcon) images.actionIcon(action.getIcon()) else null).put("id", handle.id).put("title", action.title?.toString().orEmpty().take(128))
            .put("input", input != null).put("freeform", input?.allowFreeFormInput ?: false)
            .put("choices", JSONArray(input?.choices.orEmpty().take(8).map { it.toString().take(256) }))
            .put("enabled", action.actionIntent != null && supported)
            .put("requiresUnlock", Build.VERSION.SDK_INT >= 31 && action.isAuthenticationRequired)
            .put("destructive", action.semanticAction == Notification.Action.SEMANTIC_ACTION_DELETE)
    }
}

internal fun Notification.Action.allInputs(): List<RemoteInput> =
    remoteInputs.orEmpty().toList() + dataOnlyRemoteInputs.orEmpty().toList()
