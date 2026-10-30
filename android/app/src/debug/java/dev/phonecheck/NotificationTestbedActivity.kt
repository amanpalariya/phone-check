package dev.phonecheck

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

class NotificationTestbedActivity : ComponentActivity() {
    private val previewHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var previewTask: Runnable? = null
    private var previewScheduled by mutableStateOf(false)
    private var pending: (() -> Unit)? = null
    private var denied by mutableStateOf(false)
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        denied = !granted
        if (granted) pending?.let(::safelyPost)
        pending = null
    }
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(); receiveTap(intent)
        setContent {
            PhoneCheckTheme {
                Scaffold(topBar = {
                    TopAppBar(title = { Text("Notification testbed") },
                        navigationIcon = { TextButton(onClick = { finish() }) { Text("Back") } },
                        actions = { TextButton(onClick = { cancelPreview(); TestNotifications.clear(this@NotificationTestbedActivity) }) { Text("Clear") } })
                }) { padding ->
                    LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(bottom = 24.dp)) {
                        item {
                            Column(Modifier.padding(horizontal = 24.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(BridgeState.status, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                                Text("Post on Android. Check appearance and actions on your Mac.", style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                FilledTonalButton(onClick = { postWithPermission { DemoScenario.entries.forEach { TestNotifications.post(this@NotificationTestbedActivity, it) } } }) { Text("Post all samples") }
                                OutlinedButton(onClick = { postWithPermission { schedulePreview() } }, enabled = !previewScheduled) {
                                    Text(if (previewScheduled) "Scheduled" else "Post preview in 7s")
                                }
                                Text("Lock your phone and close the Mac list before it arrives.", style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(TestbedState.lastReceipt, style = MaterialTheme.typography.bodyMedium)
                                if (denied) {
                                    Text("Notifications are off", color = MaterialTheme.colorScheme.error)
                                    TextButton(onClick = {
                                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                                    }) { Text("Notification settings") }
                                }
                            }
                        }
                        items(DemoScenario.entries) { scenario ->
                            ListItem(headlineContent = { Text(scenario.label) }, supportingContent = { Text(scenario.detail) },
                                trailingContent = {
                                    Row {
                                        if (scenario == DemoScenario.PROGRESS) TextButton(onClick = {
                                            TestbedState.progress = (TestbedState.progress + 25).let { if (it > 100) 0 else it }
                                            postWithPermission { TestNotifications.post(this@NotificationTestbedActivity, scenario) }
                                        }) { Text("Update") }
                                        OutlinedButton(onClick = { postWithPermission { TestNotifications.post(this@NotificationTestbedActivity, scenario) } }) { Text("Post") }
                                    }
                                })
                        }
                    }
                }
            }
        }
    }
    private fun cancelPreview() {
        previewTask?.let(previewHandler::removeCallbacks)
        previewTask = null; previewScheduled = false
    }
    private fun schedulePreview() {
        cancelPreview()
        // Remove this synthetic sample first so ONLY_ALERT_ONCE cannot suppress the test.
        getSystemService(NotificationManager::class.java).cancel(TestNotifications.TAG, DemoScenario.BASIC.number)
        val context = applicationContext
        previewScheduled = true
        TestbedState.lastReceipt = "Preview scheduled. Lock your phone."
        previewTask = Runnable {
            previewTask = null; previewScheduled = false
            safelyPost { TestNotifications.post(context, DemoScenario.BASIC) }
        }.also { previewHandler.postDelayed(it, 7_000) }
    }
    override fun onDestroy() { cancelPreview(); super.onDestroy() }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); receiveTap(intent) }
    private fun receiveTap(intent: Intent) {
        if (intent.getStringExtra("operation") == "open") {
            TestbedState.record("open")
            intent.removeExtra("operation")
        }
    }
    private fun postWithPermission(action: () -> Unit) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            pending = action; permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else if (!getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
            denied = true
        } else { denied = false; safelyPost(action) }
    }
    private fun safelyPost(action: () -> Unit) {
        runCatching(action).onFailure { TestbedState.lastReceipt = "Sample unavailable on this Android version" }
    }
}
