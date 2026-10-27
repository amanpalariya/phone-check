package dev.phonecheck

internal enum class CommandKind(val wireName: String) { DISMISS("dismiss"), ACTION("action"), OPEN("open") }

internal data class NotificationCommand(
    val id: String,
    val key: String,
    val revision: String,
    val kind: CommandKind,
    val actionId: String?,
    val text: String?,
    val sentAt: Long,
    val expiresAt: Long
) {
    fun isFresh(now: Long): Boolean = sentAt in (now - 10000)..(now + 1000) &&
        expiresAt in (sentAt + 1)..(sentAt + 10000) && now <= expiresAt
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
