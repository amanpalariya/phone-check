package dev.phonecheck

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import org.json.JSONObject

/** Transport-independent battery value; a missing percentage means the OS has no reading. */
internal data class BatteryStatus(val percentage: Int?, val charging: Boolean, val powerSaving: Boolean = false) {
    fun json() = JSONObject().put("percentage", percentage ?: JSONObject.NULL).put("charging", charging)
        .put("powerSaving", powerSaving)

    companion object {
        fun from(level: Int, scale: Int, present: Boolean, charging: Boolean): BatteryStatus {
            val percentage = if (present && scale > 0 && level in 0..scale)
                (level.toLong() * 100 / scale).toInt() else null
            return BatteryStatus(percentage, present && charging)
        }
    }
}

/** OS broadcasts only, with duplicate readings suppressed. No polling or persisted telemetry. */
internal class PhoneBattery(private val context: Context, private val onChanged: () -> Unit) {
    private val power = context.getSystemService(PowerManager::class.java)
    @Volatile var current = BatteryStatus(null, false)
        private set
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_BATTERY_CHANGED) update(intent)
            else publish(current.copy(powerSaving = power.isPowerSaveMode))
        }
    }
    fun start() {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply {
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        }
        val initial = if (Build.VERSION.SDK_INT >= 33)
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") context.registerReceiver(receiver, filter)
        initial?.let(::update) ?: publish(current.copy(powerSaving = power.isPowerSaveMode))
    }
    fun close() { context.unregisterReceiver(receiver) }
    private fun update(intent: Intent) {
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
        val next = BatteryStatus.from(
            intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
            intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
            intent.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true),
            status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL)
            .copy(powerSaving = power.isPowerSaveMode)
        publish(next)
    }
    private fun publish(next: BatteryStatus) {
        if (current != next) { current = next; onChanged() }
    }
}
