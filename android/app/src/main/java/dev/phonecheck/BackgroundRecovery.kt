package dev.phonecheck

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.PowerManager

/** Owned by the system-bound listener, never by the activity. No polling or wake lock. */
internal class BackgroundRecovery(
    private val context: Context,
    private val main: Handler,
    private val recover: (networkChanged: Boolean) -> Unit
) : AutoCloseable {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private var network: Network? = null
    private var closed = true
    private var networkChanged = false
    private val pending = Runnable {
        val changed = networkChanged; networkChanged = false
        if (!closed) recover(changed)
    }
    private fun schedule(changed: Boolean) {
        if (closed) return
        networkChanged = networkChanged || changed
        main.removeCallbacks(pending)
        main.postDelayed(pending, 750)
    }
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(next: Network) {
            if (network != next) { network = next; schedule(true) }
        }
        override fun onLost(previous: Network) {
            if (network == previous) { network = null; schedule(true) }
        }
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val power = context.getSystemService(PowerManager::class.java)
            if (!power.isDeviceIdleMode) schedule(intent.action == PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
        }
    }
    fun start() {
        if (!closed) return
        closed = false
        network = connectivity.activeNetwork
        connectivity.registerDefaultNetworkCallback(callback, main)
        val filter = IntentFilter().apply {
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") context.registerReceiver(receiver, filter)
    }
    override fun close() {
        if (closed) return
        closed = true
        main.removeCallbacks(pending)
        connectivity.unregisterNetworkCallback(callback)
        context.unregisterReceiver(receiver)
    }
}
