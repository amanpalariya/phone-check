package dev.phonecheck

import android.content.Context
import android.content.Intent
import android.service.notification.StatusBarNotification

// Variant boundary: production capture and screens never depend on testbed types.
internal object DevelopmentFeatures {
    const val enabled = true
    fun openTestbed(context: Context) {
        context.startActivity(Intent(context, NotificationTestbedActivity::class.java))
    }
    fun capturesOwnNotification(sbn: StatusBarNotification) =
        sbn.tag == TestNotifications.TAG || sbn.id == DemoScenario.CALL.number

    fun notificationRemoved(sbn: StatusBarNotification) {
        if (sbn.tag == TestNotifications.TAG && sbn.id == DemoScenario.MEDIA.number) TestbedMediaSession.clear()
        if (capturesOwnNotification(sbn)) TestbedState.record("removed")
    }
}
