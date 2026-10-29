package dev.phonecheck

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private val attention by lazy { PhoneAttention(this) }
    private val attentionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            inSession { if (snapshotSent) send(attentionMessage()) }
        }
    }
    private val battery: PhoneBattery by lazy { PhoneBattery(this) {
        inSession { if (snapshotSent) send(deviceStatusMessage()) }
    } }
    private var transport: NotificationTransport? = null
    private var requiresLocalNetwork = true
    private val callbacks = TransportCallbacks(::transportConnected, ::transportMessage, ::transportDisconnected)
    private var createTransport: (Pairing, TransportCallbacks) -> NotificationTransport = { pairing, callbacks ->
        LanTransport(pairing, main, ::allowed,
            onConnecting = { BridgeState.status = "Connecting…" },
            onConnected = callbacks.onConnected,
            onMessage = callbacks.onMessage,
            onDisconnected = callbacks.onDisconnected)
    }
    private fun transportConnected() = inSession { synchronize() }
    private fun transportMessage(message: JSONObject) = inSession { if (ready) handle(message) }
    private fun transportDisconnected() {
        session++; snapshotSent = false; resetWorker()
        BridgeState.status = if (!requiresLocalNetwork) "Disconnected"
            else if (allowed()) "Disconnected · retrying" else "Allow local network"
    }
    /** Composition point for an explicitly selected transport. Each restart creates a fresh instance. */
    internal fun useTransport(
        needsLocalNetwork: Boolean,
        factory: (Pairing, TransportCallbacks) -> NotificationTransport
    ) {
        stopLink(); transport?.close(); transport = null
        requiresLocalNetwork = needsLocalNetwork
        createTransport = factory
        restart()
    }
    private val commands by lazy {
        NotificationCommandHandler(this, capture, worker,
            isReady = { ready && snapshotSent }, activeNotifications = { activeNotifications },
            cancel = { cancelNotification(it) },
            onResult = { id, status -> send(JSONObject().put("type", "result").put("command", id).put("status", status)) },
            onProtocolError = { transport?.disconnect() }, onChanged = { publish(it) })
    }
    override fun onCreate() {
        super.onCreate(); BridgeState.service = this
        battery.start()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(attentionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(attentionReceiver, filter)
    }
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
        unregisterReceiver(attentionReceiver); battery.close()
        stopLink(); transport?.close(); thread.quitSafely(); super.onDestroy()
    }
    private fun allowed() = !requiresLocalNetwork || Build.VERSION.SDK_INT < 37 ||
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
            else -> {
                transport?.close()
                transport = createTransport(pairing, callbacks)
                transport?.start()
            }
        }
    }
    private fun inSession(action: () -> Unit) {
        val expected = session
        worker.post { if (expected == session) action() }
    }
    private fun resetWorker() { worker.post { commands.reset(); capture.clear(); active.clear() } }
    private fun stopLink() {
        session++; snapshotSent = false; transport?.stop(); resetWorker()
    }
    private fun synchronize() {
        if (!ready) { transport?.disconnect(); return }
        val expected = session
        runCatching {
            active.clear(); capture.clear()
            val current = activeNotifications ?: error("Listener unavailable")
            current.forEach { sbn -> capture.capture(sbn)?.let { active[sbn.key] = it.json } }
            if (session != expected || !ready) return
            transport?.sendBatch(listOf(attentionMessage(), deviceStatusMessage()) + NotificationSnapshot.frames(active.values))
            snapshotSent = true
            main.post { if (session == expected) BridgeState.status = "Connected" }
        }.onFailure { transport?.disconnect() }
    }
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        inSession { if (ready) capture.capture(sbn)?.let { publish(it.json) } }
    }
    private fun publish(item: JSONObject) {
        val key = item.getString("key")
        if (active[key]?.toString() == item.toString()) return
        active[key] = item
        if (snapshotSent) send(JSONObject().put("type", "upsert").put("item", item)
            .put("phoneInUse", attention.isInUse()).put("sentAt", System.currentTimeMillis()))
    }
    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        inSession {
            if (!ready) return@inSession
            active.remove(sbn.key); capture.remove(sbn.key)
            if (sbn.packageName == packageName) {
                main.post { DevelopmentFeatures.notificationRemoved(sbn) }
            }
            if (snapshotSent) send(JSONObject().put("type", "remove").put("key", sbn.key))
            commands.onRemoved(sbn.key)
        }
    }
    private fun deviceStatusMessage() = JSONObject().put("type", "device_status")
        .put("battery", battery.current.json())
    private fun attentionMessage() = JSONObject().put("type", "attention")
        .put("phoneInUse", attention.isInUse()).put("sentAt", System.currentTimeMillis())
    private fun send(message: JSONObject) = transport?.send(message)
    private fun handle(message: JSONObject) {
        when (message.optString("type")) {
            "ping" -> send(JSONObject().put("type", "pong"))
            "dismiss", "action", "open" -> commands.handle(message)
            else -> transport?.disconnect()
        }
    }
}
