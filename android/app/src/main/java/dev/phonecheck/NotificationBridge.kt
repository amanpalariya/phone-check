package dev.phonecheck

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject

internal object BridgeState {
    var status by mutableStateOf("Not paired")
    var paired by mutableStateOf(false)
    var listenerReady by mutableStateOf(false)
    var service: NotificationBridge? = null
}

/** Listener callbacks hand work to one ordered worker; content providers never block the UI. */
class NotificationBridge : NotificationListenerService() {
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("notification-sync").apply { start() }
    private val worker = Handler(thread.looper)
    @Volatile private var ready = false
    @Volatile private var snapshotSent = false
    @Volatile private var session = 0
    private val active = mutableMapOf<String, JSONObject>()
    private val capture by lazy { NotificationCapture(this) }
    private val transport: NotificationTransport by lazy {
        LanTransport(main, ::allowed,
            onConnecting = { BridgeState.status = "Connecting…" },
            onConnected = { inSession { synchronize() } },
            onMessage = { message -> inSession { if (ready) handle(message) } },
            onDisconnected = {
                session++; snapshotSent = false; resetWorker()
                BridgeState.status = if (allowed()) "Disconnected · retrying" else "Allow local network"
            })
    }
    private val commands by lazy {
        NotificationCommandHandler(this, capture, worker,
            isReady = { ready && snapshotSent }, activeNotifications = { activeNotifications },
            cancel = { cancelNotification(it) },
            onResult = { id, status -> send(JSONObject().put("type", "result").put("command", id).put("status", status)) },
            onProtocolError = { transport.disconnect() }, onChanged = { publish(it) })
    }
    override fun onCreate() { super.onCreate(); BridgeState.service = this }
    override fun onListenerConnected() {
        super.onListenerConnected(); ready = true; BridgeState.listenerReady = true; restart()
    }
    override fun onListenerDisconnected() {
        ready = false; BridgeState.listenerReady = false
        stopLink(); BridgeState.status = "Notification access disconnected"
        super.onListenerDisconnected()
        requestRebind(ComponentName(this, NotificationBridge::class.java))
    }
    override fun onDestroy() {
        ready = false; BridgeState.listenerReady = false; BridgeState.service = null
        stopLink(); transport.close(); thread.quitSafely(); super.onDestroy()
    }
    private fun allowed() = Build.VERSION.SDK_INT < 37 ||
        checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED
    fun restart() {
        check(Looper.myLooper() == Looper.getMainLooper())
        stopLink()
        val pairing = PairingStore(this).load()
        BridgeState.paired = pairing != null
        when {
            pairing == null -> BridgeState.status = "Not paired"
            !ready -> BridgeState.status = "Allow notification access"
            !allowed() -> BridgeState.status = "Allow local network"
            else -> transport.start(pairing)
        }
    }
    private fun inSession(action: () -> Unit) {
        val expected = session
        worker.post { if (expected == session) action() }
    }
    private fun resetWorker() { worker.post { commands.reset(); capture.clear(); active.clear() } }
    private fun stopLink() {
        session++; snapshotSent = false; transport.stop(); resetWorker()
    }
    private fun synchronize() {
        if (!ready) { transport.disconnect(); return }
        val expected = session
        runCatching {
            active.clear(); capture.clear()
            val current = activeNotifications ?: error("Listener unavailable")
            current.forEach { sbn -> capture.capture(sbn)?.let { active[sbn.key] = it.json } }
            if (session != expected || !ready) return
            transport.sendBatch(NotificationSnapshot.frames(active.values))
            snapshotSent = true
            main.post { if (session == expected) BridgeState.status = "Connected" }
        }.onFailure { transport.disconnect() }
    }
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        inSession { if (ready) capture.capture(sbn)?.let { publish(it.json) } }
    }
    private fun publish(item: JSONObject) {
        val key = item.getString("key")
        if (active[key]?.toString() == item.toString()) return
        active[key] = item
        if (snapshotSent) send(JSONObject().put("type", "upsert").put("item", item))
    }
    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        inSession {
            if (!ready) return@inSession
            active.remove(sbn.key); capture.remove(sbn.key)
            if (sbn.packageName == packageName && (sbn.tag == TestNotifications.TAG || sbn.id == DemoScenario.CALL.number)) {
                main.post { TestbedState.record("removed") }
            }
            if (snapshotSent) send(JSONObject().put("type", "remove").put("key", sbn.key))
            commands.onRemoved(sbn.key)
        }
    }
    private fun send(message: JSONObject) = transport.send(message)
    private fun handle(message: JSONObject) {
        when (message.optString("type")) {
            "ping" -> send(JSONObject().put("type", "pong"))
            "dismiss", "action", "open" -> commands.handle(message)
            else -> transport.disconnect()
        }
    }
}
