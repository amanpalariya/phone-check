package dev.phonecheck

import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager

/** A conservative proxy for phone use. No usage access, polling or app tracking. */
internal class PhoneAttention(context: Context) {
    private val power = context.getSystemService(PowerManager::class.java)
    private val keyguard = context.getSystemService(KeyguardManager::class.java)
    fun isInUse(): Boolean = power.isInteractive && !keyguard.isKeyguardLocked
}
