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

/** Revalidates active capabilities; media actions are independent of presentation revisions. */
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

    fun reset() {
        epoch++
        pending.clear()
        ledger.clear()
    }

    fun onRemoved(key: String) {
        pending.values.filter { it.key == key }.toList().forEach { complete(it.id, "removed") }
    }

    fun handle(message: JSONObject) {
        val command = NotificationCommand.parse(message) ?: run {
            onProtocolError()
            return
        }
        when (val admission = ledger.accept(command, SystemClock.elapsedRealtime())) {
            CommandLedger.Admission.Rejected -> {
                onProtocolError()
                return
            }
            is CommandLedger.Admission.Repeated -> {
                admission.status?.let { onResult(command.id, it) }
                return
            }
            CommandLedger.Admission.New -> Unit
        }
        if (!command.isFresh(System.currentTimeMillis())) {
            complete(command.id, "expired")
            return
        }
        if (!isReady()) {
            complete(command.id, "unavailable")
            return
        }
        try {
            execute(command)
        } catch (_: PendingIntent.CanceledException) {
            complete(command.id, "unavailable")
        } catch (_: SecurityException) {
            complete(command.id, "access_denied")
        } catch (_: Exception) {
            complete(command.id, "failed")
        }
    }

    private fun execute(command: NotificationCommand) {
        val active = activeNotifications() ?: run {
            complete(command.id, "unavailable")
            return
        }
        val notification = active.firstOrNull { it.key == command.key }
        if (notification == null) {
            complete(command.id, if (command.kind == CommandKind.DISMISS) "removed" else "gone")
            return
        }
        val current = capture.capture(notification) ?: run {
            complete(command.id, "gone")
            return
        }
        val revision = capabilityRevision(command, current)
        if (revision != command.revision) {
            onChanged(current.json)
            complete(command.id, "changed")
            return
        }
        if (!isReady() || !command.isFresh(System.currentTimeMillis())) {
            complete(command.id, "expired")
            return
        }
        if (command.kind == CommandKind.DISMISS) dismiss(command, notification)
        else dispatch(command, current)
    }

    private fun capabilityRevision(command: NotificationCommand, current: CapturedNotice): String {
        val mediaAction = if (command.kind == CommandKind.ACTION) current.actions.firstOrNull {
            it.id == command.actionId && (it.media != null || current.json.optString("kind") == "media")
        } else null
        return mediaAction?.let { mediaCapabilityRevision(it.id) } ?: current.json.optString("revision")
    }

    private fun dismiss(command: NotificationCommand, notification: StatusBarNotification) {
        if (!notification.isClearable) {
            complete(command.id, "blocked")
            return
        }
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
        val handle = current.actions.firstOrNull { it.id == command.actionId }
        if (command.kind == CommandKind.ACTION && handle?.media != null) {
            dispatchMedia(command, handle.media)
            return
        }
        if (command.position != null) {
            complete(command.id, "unsupported_input")
            return
        }
        val action = handle?.action
        if (command.kind == CommandKind.ACTION && action == null) {
            complete(command.id, "changed")
            return
        }
        val intent = (if (command.kind == CommandKind.OPEN) current.content else action?.actionIntent)
            ?: run { complete(command.id, "unavailable"); return }
        val requiresUnlock = command.kind == CommandKind.OPEN ||
            (Build.VERSION.SDK_INT >= 31 && (action?.isAuthenticationRequired == true || intent.isActivity))
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        if (requiresUnlock && (keyguard.isDeviceLocked || keyguard.isKeyguardLocked)) {
            complete(command.id, "requires_unlock")
            return
        }
        val fillIn = inputIntent(action?.allInputs().orEmpty(), command.text)
            ?: run { complete(command.id, "unsupported_input"); return }
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 34) {
            options.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        }
        intent.send(context, 0, fillIn, null, null, null, options.toBundle())
        // This confirms dispatch only. A target app's update/removal is a separate event.
        complete(command.id, "sent")
    }

    private fun dispatchMedia(command: NotificationCommand, media: MediaCapability) {
        val seeking = media.operation == "seek"
        val duration = media.controller.metadata?.getLong(android.media.MediaMetadata.METADATA_KEY_DURATION) ?: 0
        val validPosition = if (seeking) command.position != null && command.position in 0..duration
            else command.position == null
        if (command.text != null || !validPosition) {
            complete(command.id, "unsupported_input")
            return
        }
        media.execute(command.position)
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
        pending.remove(id)
        ledger.complete(id, status)
        onResult(id, status)
    }
}
