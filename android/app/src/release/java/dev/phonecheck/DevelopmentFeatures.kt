package dev.phonecheck

import android.content.Context
import android.service.notification.StatusBarNotification

internal object DevelopmentFeatures {
    const val enabled = false
    fun openTestbed(context: Context) = Unit
    fun capturesOwnNotification(sbn: StatusBarNotification) = false
    fun notificationRemoved(sbn: StatusBarNotification) = Unit
}
