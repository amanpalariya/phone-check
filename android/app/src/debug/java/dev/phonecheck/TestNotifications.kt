package dev.phonecheck

import android.app.ActivityOptions
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Build
import android.widget.RemoteViews
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

internal object TestNotifications {
    const val TAG = "phonecheck.demo"
    const val REPLY_KEY = "demo.reply"
    private const val CHANNEL = "testbed"
    private const val QUIET = "testbed.silent"
    fun clear(context: Context) {
        TestbedMediaSession.clear()
        context.stopService(Intent(context, TestbedCallService::class.java))
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.activeNotifications.filter { it.tag == TAG }.forEach { manager.cancel(TAG, it.id) }
    }
    fun post(context: Context, scenario: DemoScenario, receipt: String? = null) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Notification testbed", NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(NotificationChannel(QUIET, "Silent test notifications", NotificationManager.IMPORTANCE_LOW))
        if (scenario == DemoScenario.CALL) {
            context.startForegroundService(Intent(context, TestbedCallService::class.java))
            return
        }
        val builder = Notification.Builder(context, if (scenario == DemoScenario.SILENT) QUIET else CHANNEL)
            .setSmallIcon(R.drawable.ic_bell).setContentTitle(scenario.label)
            .setContentText(receipt ?: "Sample notification from the testbed.")
            .setOnlyAlertOnce(true).setAutoCancel(true)
            .setContentIntent(openIntent(context, scenario))
            .setDeleteIntent(actionIntent(context, scenario, "deleted"))
        when (scenario) {
            DemoScenario.LONG_TEXT -> builder.setStyle(Notification.BigTextStyle().bigText(
                "A longer notification should remain readable on your Mac.\n\n" +
                "Updates keep the same notification key. Expanded content, line breaks, emoji 🔔, and 日本語 are preserved.\n\n" +
                "This is synthetic test content. ".repeat(12)))
            DemoScenario.INBOX -> builder.setStyle(Notification.InboxStyle().addLine("First update")
                .addLine("Second update — 日本語").addLine("Third update 🔔").setSummaryText("3 updates"))
            DemoScenario.CHAT -> {
                val user = Person.Builder().setName("You").build()
                val sender = Person.Builder().setName("Sample sender").build()
                val style = Notification.MessagingStyle(user).setConversationTitle("Sample chat").setGroupConversation(true)
                    .addMessage("Can you see this on your Mac?", System.currentTimeMillis() - 1000, sender)
                    .addMessage(receipt ?: "Try the reply button.", System.currentTimeMillis(), sender)
                builder.setStyle(style).addAction(Notification.Action.Builder(null, "Reply", actionIntent(context, scenario, "reply", mutable = true))
                    .addRemoteInput(RemoteInput.Builder(REPLY_KEY).setLabel("Reply").build())
                    .setSemanticAction(Notification.Action.SEMANTIC_ACTION_REPLY).build())
            }
            DemoScenario.CHOICES -> builder.addAction(Notification.Action.Builder(null, "Respond", actionIntent(context, scenario, "reply", mutable = true))
                .addRemoteInput(RemoteInput.Builder(REPLY_KEY).setAllowFreeFormInput(false).setChoices(arrayOf("Yes", "Later")).build()).build())
            DemoScenario.ATTACHMENT_INPUT -> builder.addAction(Notification.Action.Builder(null, "Attach image", actionIntent(context, scenario, "attachment", mutable = true))
                .addRemoteInput(RemoteInput.Builder(REPLY_KEY).setAllowFreeFormInput(false).setAllowDataType("image/*", true).build()).build())
            DemoScenario.MULTIPLE_INPUTS -> builder.addAction(Notification.Action.Builder(null, "Complete form", actionIntent(context, scenario, "form", mutable = true))
                .addRemoteInput(RemoteInput.Builder("first").build()).addRemoteInput(RemoteInput.Builder("second").build()).build())
            DemoScenario.PICTURE -> builder.setStyle(Notification.BigPictureStyle().bigPicture(samplePicture()).setSummaryText("Sample landscape"))
            DemoScenario.PROGRESS -> builder.setProgress(100, TestbedState.progress, false).setOngoing(TestbedState.progress < 100)
                .setContentText("${TestbedState.progress}% complete").setAutoCancel(false)
            DemoScenario.INDETERMINATE -> builder.setProgress(0, 0, true).setOngoing(true).setAutoCancel(false)
            DemoScenario.GROUP -> {
                val group = "phonecheck.testbed.group"
                for (child in 1..2) {
                    manager.notify(TAG, 2000 + child, Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_bell)
                        .setContentTitle("Grouped update $child").setContentText("Child notification $child")
                        .setGroup(group).setOnlyAlertOnce(true).build())
                }
                builder.setGroup(group).setGroupSummary(true).setContentText("2 updates")
            }
            DemoScenario.ONGOING -> builder.setOngoing(true).setAutoCancel(false)
            DemoScenario.ACTIONS -> builder.addAction(action(context, scenario, "archive", "Archive", destructive = true))
                .addAction(action(context, scenario, "read", "Mark read"))
            DemoScenario.MEDIA -> builder.setStyle(Notification.MediaStyle().setMediaSession(TestbedMediaSession.token(context)))
                .setCategory(Notification.CATEGORY_TRANSPORT).setAutoCancel(false)
            DemoScenario.MEDIA_LEGACY -> builder.setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2))
                .setCategory(Notification.CATEGORY_TRANSPORT)
                .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(context, android.R.drawable.ic_media_previous), "Anterior", actionIntent(context, scenario, "previous")).build())
                .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(context, android.R.drawable.ic_media_play), "Reproducir", actionIntent(context, scenario, "play")).build())
                .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(context, android.R.drawable.ic_media_next), "Siguiente", actionIntent(context, scenario, "next")).build())
            DemoScenario.PRIVATE -> builder.setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(
                Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_bell)
                    .setContentTitle("Private notification").setContentText("Unlock to view").build())
            DemoScenario.CUSTOM -> builder.setCustomContentView(RemoteViews(context.packageName, R.layout.demo_notification))
                .setStyle(Notification.DecoratedCustomViewStyle()).setContentText("Custom Android layout — text fallback")
            DemoScenario.EXPIRED -> {
                val canceled = actionIntent(context, scenario, "expired")
                builder.addAction(Notification.Action.Builder(null, "Expired action", canceled).build())
                canceled.cancel()
            }
            DemoScenario.PROTECTED -> {
                val action = Notification.Action.Builder(null, "Protected action", actionIntent(context, scenario, "protected"))
                if (Build.VERSION.SDK_INT >= 31) action.setAuthenticationRequired(true)
                builder.addAction(action.build())
            }
            else -> Unit
        }
        manager.notify(TAG, scenario.number, builder.build())
    }
    fun callNotification(context: Context): Notification {
        val builder = Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_bell)
            .setContentTitle("Incoming call").setContentText("Synthetic call sample")
            .setOngoing(true).setCategory(Notification.CATEGORY_CALL)
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setStyle(Notification.CallStyle.forIncomingCall(Person.Builder().setName("Sample caller").setImportant(true).build(),
                actionIntent(context, DemoScenario.CALL, "decline"), actionIntent(context, DemoScenario.CALL, "answer")))
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        } else {
            builder.addAction(action(context, DemoScenario.CALL, "answer", "Answer"))
                .addAction(action(context, DemoScenario.CALL, "decline", "Decline"))
        }
        return builder.build()
    }
    private fun action(context: Context, scenario: DemoScenario, operation: String, label: String, destructive: Boolean = false) =
        Notification.Action.Builder(null, label, actionIntent(context, scenario, operation))
            .setSemanticAction(if (destructive) Notification.Action.SEMANTIC_ACTION_DELETE else Notification.Action.SEMANTIC_ACTION_NONE).build()
    private fun actionIntent(context: Context, scenario: DemoScenario, operation: String, mutable: Boolean = false): PendingIntent {
        val intent = Intent(context, TestbedActionReceiver::class.java).setAction("dev.phonecheck.TEST_ACTION")
            .putExtra("scenario", scenario.name).putExtra("operation", operation)
        return PendingIntent.getBroadcast(context, scenario.number * 100 + operation.hashCode(), intent,
            PendingIntent.FLAG_CANCEL_CURRENT or if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)
    }
    private fun openIntent(context: Context, scenario: DemoScenario): PendingIntent {
        val intent = Intent(context, NotificationTestbedActivity::class.java)
            .putExtra("operation", "open").putExtra("scenario", scenario.name)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 35) options.setPendingIntentCreatorBackgroundActivityStartMode(
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        return PendingIntent.getActivity(context, scenario.number, intent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE, options.toBundle())
    }
    private fun samplePicture(): Bitmap {
        val image = Bitmap.createBitmap(480, 240, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 480f, 240f, Color.rgb(86, 62, 160), Color.rgb(91, 179, 191), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, 480f, 240f, paint)
        paint.shader = null; paint.color = Color.rgb(250, 219, 151)
        canvas.drawCircle(365f, 60f, 28f, paint)
        paint.color = Color.rgb(47, 72, 104)
        val mountain = android.graphics.Path().apply { moveTo(0f, 240f); lineTo(150f, 80f); lineTo(290f, 240f); close() }
        canvas.drawPath(mountain, paint)
        return image
    }
}
