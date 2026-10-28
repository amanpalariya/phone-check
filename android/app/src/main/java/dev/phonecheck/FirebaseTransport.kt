package dev.phonecheck

import android.os.Handler
import org.json.JSONObject
import java.util.UUID

/** Project binding, scoped to one authorized pair/session. Callbacks are asynchronous on main.
 * Observe emits the current value, including null, after connecting. Writes acknowledge the server.
 * Cancellation detaches the listener. Offline persistence must remain disabled. */
internal interface FirebaseMailbox {
    fun observe(path: String, changed: (Result<String?>) -> Unit): () -> Unit
    fun write(path: String, value: String, completion: (Exception?) -> Unit)
    fun close()
}

/** Fresh session provisioned after BOTH paired devices authorize it. Never reuse an ID. */
internal class FirebaseSession(val id: String, secret: ByteArray, val expiresAt: Long, now: Long) {
    val secret = secret.clone()
    init {
        require(UUID.fromString(id).toString() == id && secret.size == 32)
        require(expiresAt > now && expiresAt <= now + 900_000)
    }
}

/** Same encrypted envelope and direction keys as PhoneCheckCore.FirebaseConnection. */
internal class FirebaseFrameCodec(private val session: FirebaseSession, isPhone: Boolean) {
    private val sendLane = if (isPhone) "phoneToMac" else "macToPhone"
    private val receiveLane = if (isPhone) "macToPhone" else "phoneToMac"
    private val outgoing = SessionCipher(Wire.derive(session.secret, "firebase-$sendLane", session.id.toByteArray()))
    private val incoming = SessionCipher(Wire.derive(session.secret, "firebase-$receiveLane", session.id.toByteArray()))
    var received = 0L
        private set
    fun encode(message: JSONObject, sequence: Long, now: Long): String {
        require(now < session.expiresAt && sequence > 0)
        val payload = JSONObject().put("session", session.id).put("sequence", sequence)
            .put("expiresAt", minOf(now + 30_000, session.expiresAt)).put("message", message)
        val encrypted = outgoing.apply(payload.toString().toByteArray(Charsets.UTF_8), true)
        require(encrypted.size <= Wire.MAX_FRAME)
        return JSONObject().put("sequence", sequence).put("payload", Wire.b64(encrypted)).toString()
    }
    /** null means an already accepted frame. Re-ACK it without repeating any side effects. */
    fun decode(value: String, now: Long): JSONObject? {
        require(value.toByteArray().size <= Wire.MAX_FRAME * 2 && now < session.expiresAt)
        val packet = JSONObject(value)
        val sequence = packet.getLong("sequence")
        if (sequence == received && received > 0) return null
        require(received < Long.MAX_VALUE && sequence == received + 1)
        val encrypted = Wire.unbase64(packet.getString("payload"))
        require(encrypted.size <= Wire.MAX_FRAME)
        val payload = JSONObject(String(incoming.apply(encrypted, false), Charsets.UTF_8))
        require(payload.getString("session") == session.id && payload.getLong("sequence") == sequence)
        require(payload.getLong("expiresAt") > now &&
            payload.getLong("expiresAt") <= minOf(now + 40_000, session.expiresAt))
        val message = payload.getJSONObject("message")
        received = sequence
        return message
    }
}

/** Stop-and-wait mailboxes prevent RTDB value coalescing from losing frames. Bounded memory,
 * no disk queue, no replay across sessions, and a new snapshot after every reconnect. */
internal class FirebaseTransport(
    private val main: Handler,
    private val mailbox: FirebaseMailbox,
    private val session: FirebaseSession,
    private val onConnected: () -> Unit,
    private val onMessage: (JSONObject) -> Unit,
    private val onDisconnected: () -> Unit,
    private val now: () -> Long = System::currentTimeMillis
) : NotificationTransport {
    private val codec = FirebaseFrameCodec(session, isPhone = true)
    private val cancellations = mutableListOf<() -> Unit>()
    private val queue = ArrayDeque<String>()
    private var queuedBytes = 0
    private var sent = 0L
    private var pending: Long? = null
    private var started = false
    private var closed = false
    private var ready = false
    private var sawInbox = false
    private var sawAck = false
    private var firstPacket: String? = null
    private val timeout = Runnable { disconnect() }

    override fun start() {
        if (started || closed || now() >= session.expiresAt) { disconnect(); return }
        started = true; armDeadline()
        cancellations += mailbox.observe("macToPhone") { result ->
            if (!closed) result.fold(onSuccess = { value ->
                sawInbox = true
                if (!ready) { firstPacket = value; becomeReady() }
                else if (value != null) receive(value)
            }, onFailure = { disconnect() })
        }
        cancellations += mailbox.observe("phoneToMacAck") { result ->
            if (!closed) result.fold(onSuccess = { value ->
                sawAck = true
                if (!ready && value != null) { disconnect(); return@fold }
                becomeReady()
                if (value != null) acknowledge(value)
            }, onFailure = { disconnect() })
        }
    }
    private fun becomeReady() {
        if (ready || !sawInbox || !sawAck) return
        ready = true; onConnected()
        firstPacket?.let { firstPacket = null; receive(it) }
        pump()
    }
    override fun send(message: JSONObject) = sendBatch(listOf(message))
    override fun sendBatch(messages: List<JSONObject>) {
        // Capture immutable data on the caller's ordered notification worker.
        val batch = messages.map { it.toString() }
        main.post {
            if (!closed) {
                val sizes = batch.map { it.toByteArray().size }
                if (queue.size + batch.size > 256 || sizes.any { it > Wire.MAX_FRAME - 4096 } ||
                    sizes.sum().toLong() + queuedBytes > 32 * 1024 * 1024) {
                    disconnect(); return@post
                }
                queue.addAll(batch); queuedBytes += sizes.sum(); pump()
            }
        }
    }
    private fun pump() {
        if (!ready || closed || pending != null || queue.isEmpty()) return
        runCatching {
            check(sent < Long.MAX_VALUE)
            sent++; pending = sent
            write("phoneToMac", codec.encode(JSONObject(queue.first()), sent, now()))
        }.onFailure { disconnect() }
    }
    private fun receive(value: String) {
        runCatching {
            val message = codec.decode(value, now())
            if (message != null) { armDeadline(); onMessage(message) }
            if (!closed) write("macToPhoneAck", codec.received.toString())
        }.onFailure { disconnect() }
    }
    private fun acknowledge(value: String) {
        val sequence = value.toLongOrNull()
        if (sequence == null || sequence <= 0 || sequence > sent) { disconnect(); return }
        if (sequence != pending) return
        pending = null; queuedBytes -= queue.removeFirst().toByteArray().size
        armDeadline(); pump()
    }
    private fun write(path: String, value: String) {
        mailbox.write(path, value) { if (it != null && !closed) disconnect() }
    }
    private fun armDeadline() {
        main.removeCallbacks(timeout)
        val delay = minOf(45_000, session.expiresAt - now())
        if (delay <= 0) disconnect() else main.postDelayed(timeout, delay)
    }
    override fun disconnect() {
        // Command validation can disconnect from the notification worker.
        if (android.os.Looper.myLooper() != main.looper) { main.post { disconnect() }; return }
        if (closed) return
        stop(); onDisconnected()
    }
    override fun stop() {
        if (closed) return
        closed = true; main.removeCallbacks(timeout)
        cancellations.forEach { it() }; cancellations.clear(); mailbox.close()
        queue.clear(); queuedBytes = 0; pending = null; firstPacket = null
    }
    override fun close() = stop()
}
