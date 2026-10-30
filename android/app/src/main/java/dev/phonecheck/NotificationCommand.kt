package dev.phonecheck

import org.json.JSONObject

internal enum class CommandKind(val wireName: String) { DISMISS("dismiss"), ACTION("action"), OPEN("open") }

internal data class NotificationCommand(
    val id: String,
    val key: String,
    val revision: String,
    val kind: CommandKind,
    val actionId: String?,
    val text: String?,
    val sentAt: Long,
    val expiresAt: Long,
    val position: Long? = null
) {
    fun isFresh(now: Long): Boolean = sentAt in (now - 10000)..(now + 1000) &&
        expiresAt in (sentAt + 1)..(sentAt + 10000) && now <= expiresAt

    companion object {
        fun parse(message: JSONObject): NotificationCommand? {
            val kind = CommandKind.entries.firstOrNull { it.wireName == message.optString("type") } ?: return null
            val id = message.optString("command")
            val key = message.optString("key")
            val revision = message.optString("revision")
            val action = if (kind == CommandKind.ACTION) message.optString("action") else null
            val position = if (message.has("position")) {
                val value = message.opt("position")
                if (value !is Number || !value.toString().matches(Regex("[0-9]{1,19}"))) return null
                value.toString().toLongOrNull() ?: return null
            } else null
            val text = if (message.has("text")) message.optString("text") else null
            if (id.length !in 1..64 || key.length !in 1..4096 || revision.length != 64 ||
                (action != null && action.length !in 1..64) || (text?.length ?: 0) > 4000) return null
            return NotificationCommand(id, key, revision, kind, action, text, message.optLong("sentAt"), message.optLong("expiresAt"), position)
        }
    }
}

/** A short-lived receipt ledger prevents retrying a side effect, including after a notice updates. */
internal class CommandLedger(private val capacity: Int = 512) {
    private data class Entry(val command: NotificationCommand, val receivedAt: Long, var status: String? = null)
    sealed interface Admission {
        data object New : Admission
        data class Repeated(val status: String?) : Admission
        data object Rejected : Admission
    }
    private val entries = mutableMapOf<String, Entry>()
    fun accept(command: NotificationCommand, elapsed: Long): Admission {
        entries.entries.removeAll { elapsed - it.value.receivedAt > 30000 }
        entries[command.id]?.let {
            return if (it.command == command) Admission.Repeated(it.status) else Admission.Rejected
        }
        if (entries.size >= capacity) return Admission.Rejected
        entries[command.id] = Entry(command, elapsed)
        return Admission.New
    }
    fun complete(id: String, status: String) { entries[id]?.status = status }
    fun clear() = entries.clear()
}
