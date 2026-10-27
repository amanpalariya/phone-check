package dev.phonecheck

import android.app.ActivityOptions
import android.app.KeyguardManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.SystemClock
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/** Executes only capabilities belonging to the current, matching notification revision. */
internal class NotificationCommandHandler(
    private val context: Context,
    private val capture: NotificationCapture,
    private val handler: Handler,
    private val isReady: () -> Boolean,
    private val activeNotifications: () -> Array<StatusBarNotification>?,
    private val cancel: (String) -> Unit,
    private val onResult: (String, String) -> Unit,
    private val onProtocolError: () -> Unit,
    private val onChanged: (JSONObject) -> Unit = {}
) {
    private val ledger = CommandLedger()
    private val pending = mutableMapOf<String, NotificationCommand>()
    private var epoch = 0

    fun reset() { epoch++; pending.clear(); ledger.clear() }
    fun onRemoved(key: String) {
        pending.values.filter { it.key == key }.toList().forEach { complete(it.id, "removed") }
    }
    fun handle(message: JSONObject) {
        val command = parse(message) ?: run { onProtocolError(); return }
        when (val admission = ledger.accept(command, SystemClock.elapsedRealtime())) {
            CommandLedger.Admission.Rejected -> { onProtocolError(); return }
            is CommandLedger.Admission.Repeated -> { admission.status?.let { onResult(command.id, it) }; return }
            CommandLedger.Admission.New -> Unit
        }
        if (!command.isFresh(System.currentTimeMillis())) { complete(command.id, "expired"); return }
        if (!isReady()) { complete(command.id, "unavailable"); return }
        try {
            val active = activeNotifications() ?: run { complete(command.id, "unavailable"); return }
            val notification = active.firstOrNull { it.key == command.key }
            if (notification == null) {
                complete(command.id, if (command.kind == CommandKind.DISMISS) "removed" else "gone"); return
            }
            val current = capture.capture(notification)
            if (current?.json?.optString("revision") != command.revision) {
                current?.let { onChanged(it.json) }; complete(command.id, "changed"); return
            }
            if (!isReady() || !command.isFresh(System.currentTimeMillis())) { complete(command.id, "expired"); return }
            if (command.kind == CommandKind.DISMISS) dismiss(command, notification)
            else dispatch(command, current)
        } catch (_: PendingIntent.CanceledException) { complete(command.id, "unavailable") }
        catch (_: SecurityException) { complete(command.id, "access_denied") }
        catch (_: Exception) { complete(command.id, "failed") }
    }
    private fun dismiss(command: NotificationCommand, notification: StatusBarNotification) {
        if (!notification.isClearable) { complete(command.id, "blocked"); return }
        pending[command.id] = command
        val session = epoch
        cancel(command.key)
        handler.postDelayed({
            if (epoch == session && pending[command.id] == command) {
                val absent = isReady() && runCatching { activeNotifications()?.none { it.key == command.key } == true }.getOrDefault(false)
                complete(command.id, if (absent) "removed" else "unconfirmed")
            }
        }, 8000)
    }
    private fun dispatch(command: NotificationCommand, current: CapturedNotice) {
        val action = current.actions.firstOrNull { it.id == command.actionId }?.action
        if (command.kind == CommandKind.ACTION && action == null) { complete(command.id, "changed"); return }
        val intent = (if (command.kind == CommandKind.OPEN) current.content else action?.actionIntent)
            ?: run { complete(command.id, "unavailable"); return }
        val requiresUnlock = command.kind == CommandKind.OPEN ||
            (Build.VERSION.SDK_INT >= 31 && (action?.isAuthenticationRequired == true || intent.isActivity))
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        if (requiresUnlock && (keyguard.isDeviceLocked || keyguard.isKeyguardLocked)) {
            complete(command.id, "requires_unlock"); return
        }
        val fillIn = inputIntent(action?.allInputs().orEmpty(), command.text)
            ?: run { complete(command.id, "unsupported_input"); return }
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 34) options.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        intent.send(context, 0, fillIn, null, null, null, options.toBundle())
        // This confirms dispatch only. A target app's update/removal is a separate event.
        complete(command.id, "sent")
    }
    private fun inputIntent(inputs: List<RemoteInput>, text: String?): Intent? {
        val intent = Intent()
        if (inputs.isEmpty()) return intent
        val input = inputs.singleOrNull { !it.isDataOnly } ?: return null
        if (inputs.any { it.isDataOnly } || text.isNullOrBlank() ||
            (!input.allowFreeFormInput && input.choices.orEmpty().none { it.toString() == text })) return null
        RemoteInput.addResultsToIntent(arrayOf(input), intent, Bundle().apply { putCharSequence(input.resultKey, text) })
        RemoteInput.setResultsSource(intent, if (input.allowFreeFormInput) RemoteInput.SOURCE_FREE_FORM_INPUT else RemoteInput.SOURCE_CHOICE)
        return intent
    }
    private fun complete(id: String, status: String) {
        pending.remove(id); ledger.complete(id, status); onResult(id, status)
    }
    private fun parse(message: JSONObject): NotificationCommand? {
        val kind = CommandKind.entries.firstOrNull { it.wireName == message.optString("type") } ?: return null
        val id = message.optString("command")
        val key = message.optString("key")
        val revision = message.optString("revision")
        val action = if (kind == CommandKind.ACTION) message.optString("action") else null
        val text = if (message.has("text")) message.optString("text") else null
        if (id.length !in 1..64 || key.length !in 1..4096 || revision.length != 64 ||
            (action != null && action.length !in 1..64) || (text?.length ?: 0) > 4000) return null
        return NotificationCommand(id, key, revision, kind, action, text, message.optLong("sentAt"), message.optLong("expiresAt"))
    }
}
