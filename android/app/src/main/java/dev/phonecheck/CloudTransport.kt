package dev.phonecheck

import android.os.Handler
import com.google.firebase.database.*
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** SDK mailbox: memory cache only, no history, no command outbox. Server rules expire writes. */
internal class CloudMailbox(private val reference: DatabaseReference) : FirebaseMailbox {
    private val listeners = mutableListOf<Pair<DatabaseReference, ValueEventListener>>()
    private var closed = false
    override fun observe(path: String, changed: (Result<String?>) -> Unit): () -> Unit {
        val child = reference.child(path)
        val listener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                if (!closed) {
                    val value = snapshot.value
                    if (value == null || value is String) changed(Result.success(value as? String))
                    else changed(Result.failure(IllegalArgumentException("Invalid mailbox")))
                }
            }
            override fun onCancelled(error: DatabaseError) { if (!closed) changed(Result.failure(error.toException())) }
        }
        listeners += child to listener
        child.addValueEventListener(listener)
        return { child.removeEventListener(listener); listeners.remove(child to listener) }
    }
    override fun write(path: String, value: String, completion: (Exception?) -> Unit) {
        if (!closed) reference.child(path).setValue(value) { error, _ -> if (!closed) completion(error?.toException()) }
    }
    override fun close() {
        closed = true
        listeners.toList().forEach { (ref, listener) -> ref.removeEventListener(listener) }; listeners.clear()
    }
}

/** Each new request asks the Mac for a fresh signed offer. A cipher is never restarted. */
internal class CloudTransport(
    private val pairing: Pairing, private val main: Handler,
    private val callbacks: TransportCallbacks
) : NotificationTransport {
    private val uid = CloudAccount.auth.currentUser?.uid
    private val root = uid?.let(CloudAccount::root)
    private var listener: ValueEventListener? = null
    private var active: FirebaseTransport? = null
    private var requestID = ""
    private var sessionID: String? = null
    private var closed = false
    private val usedSessions = mutableSetOf<String>()
    private val reconnect = CloudReconnect(
        schedule = { delay, action ->
            val task = Runnable { action() }
            main.postDelayed(task, delay)
            val cancel: () -> Unit = { main.removeCallbacks(task) }
            cancel
        },
        retry = { if (!closed && active == null) requestSession() }
    )
    override fun start() {
        if (closed || uid == null || uid != pairing.ownerUID || pairing.pairID == null) {
            BridgeState.status = "Sign in to pair again"; return
        }
        BridgeState.status = "Connecting…"
        listener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                if (closed) return
                val pair = snapshot.child("pair")
                if (pair.child("id").getValue(String::class.java) != pairing.pairID) {
                    active?.stop(); active = null; callbacks.onDisconnected()
                    callbacks.onPairingRevoked(); return
                }
                val offer = snapshot.child("offer")
                if (offer.child("request").getValue(String::class.java) != requestID) return
                val id = offer.child("id").getValue(String::class.java) ?: return
                if (id == sessionID || id in usedSessions) return
                val expiry = offer.child("expiresAt").getValue(Long::class.java) ?: return
                val material = "$id|$requestID|${pairing.peer}|$expiry".toByteArray()
                val proof = offer.child("proof").getValue(String::class.java) ?: return
                runCatching {
                    require(MessageDigest.isEqual(Wire.unbase64(proof), Wire.derive(pairing.secret, "cloud-offer", material)))
                    val session = FirebaseSession(id, pairing.secret, expiry, System.currentTimeMillis())
                    reconnect.accepted()
                    active?.stop(); active = null; callbacks.onDisconnected()
                    sessionID = id; usedSessions += id
                    val mailboxRef = root!!.child("mailboxes").child(id)
                    mailboxRef.onDisconnect().removeValue()
                    active = FirebaseTransport(main, CloudMailbox(mailboxRef), session,
                        onConnected = {
                            active?.send(JSONObject().put("type", "device_info").put("deviceName", android.os.Build.MODEL.take(128)))
                            callbacks.onConnected()
                        }, onMessage = callbacks.onMessage,
                        onDisconnected = {
                            mailboxRef.removeValue()
                            active = null; callbacks.onDisconnected()
                            reconnect.failed()
                        }).also { it.start() }
                }.onFailure {
                    active?.stop(); active = null; callbacks.onDisconnected()
                    reconnect.failed()
                }
            }
            override fun onCancelled(error: DatabaseError) {
                active?.stop(); active = null; callbacks.onDisconnected(); BridgeState.status = "Cloud access unavailable"
            }
        }
        root!!.child("control").addValueEventListener(listener!!)
        requestSession()
    }
    private fun requestSession() {
        if (closed || root == null) return
        requestID = UUID.randomUUID().toString(); usedSessions.clear()
        val proof = Wire.b64(Wire.derive(pairing.secret, "cloud-request", "$requestID|${pairing.peer}".toByteArray()))
        val attempt = requestID
        root.child("control/request").setValue(mapOf("id" to requestID, "peer" to pairing.peer, "proof" to proof)) { error, _ ->
            if (!closed && error != null && requestID == attempt && active == null) {
                BridgeState.status = "Connecting…"
                reconnect.failed()
            }
        }
    }
    override fun send(message: JSONObject) { active?.send(message) }
    override fun sendBatch(messages: List<JSONObject>) { active?.sendBatch(messages) }
    override fun disconnect() { active?.disconnect() }
    override fun stop() {
        if (closed) return
        closed = true; reconnect.stop()
        listener?.let { root?.child("control")?.removeEventListener(it) }; listener = null
        active?.stop(); active = null
    }
    override fun close() = stop()
}
