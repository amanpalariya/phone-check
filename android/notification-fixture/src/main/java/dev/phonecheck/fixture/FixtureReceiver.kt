package dev.phonecheck.fixture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class FixtureReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = intent.getIntExtra("id", 1)
        when (intent.action) {
            "fixture.CLEAR" -> manager.cancel(id)
            "fixture.CLEAR_ALL" -> manager.cancelAll()
            "fixture.POST" -> {
                manager.createNotificationChannel(NotificationChannel("test", "Test", NotificationManager.IMPORTANCE_DEFAULT))
                val notification = Notification.Builder(context, "test")
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(intent.getStringExtra("title") ?: "Alpha")
                    .setContentText("Synthetic test notification")
                    .setOnlyAlertOnce(true)
                    .setOngoing(intent.getBooleanExtra("ongoing", false))
                    .build()
                manager.notify(id, notification)
            }
        }
    }
}
