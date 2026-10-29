package dev.phonecheck

import android.app.NotificationManager
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TestbedActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val operation = intent.getStringExtra("operation") ?: return
        val scenario = runCatching { DemoScenario.valueOf(intent.getStringExtra("scenario").orEmpty()) }.getOrNull() ?: return
        val reply = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(TestNotifications.REPLY_KEY)?.toString()
        TestbedState.record(operation, reply)
        if (operation == "deleted") return
        if (operation in listOf("archive", "decline", "answer")) {
            if (scenario == DemoScenario.CALL) context.stopService(Intent(context, TestbedCallService::class.java))
            else context.getSystemService(NotificationManager::class.java).cancel(TestNotifications.TAG, scenario.number)
        } else TestNotifications.post(context, scenario, if (operation == "reply") "Reply received" else "$operation received")
    }
}
