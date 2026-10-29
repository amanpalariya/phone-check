package dev.phonecheck

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.enableEdgeToEdge
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import android.app.NotificationManager

class MainActivity : ComponentActivity() {
    private var access by mutableStateOf(false)
    private var network by mutableStateOf(false)
    private var networkBlocked by mutableStateOf(false)
    private val networkPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        networkBlocked = !granted && !shouldShowRequestPermissionRationale("android.permission.ACCESS_LOCAL_NETWORK")
        refresh(); BridgeState.service?.restart()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        refresh()
        setContent {
            var code by remember { mutableStateOf("") }
            var error by remember { mutableStateOf<String?>(null) }
            var scanning by remember { mutableStateOf(false) }
            val pair: (String) -> Unit = { value ->
                runCatching { Pairing.parse(value) }
                    .onSuccess { pairing ->
                        runCatching { PairingStore(this).save(pairing) }
                            .onSuccess {
                                code = ""; error = null
                                BridgeState.paired = true; BridgeState.status = "Allow notification access"
                                BridgeState.service?.restart()
                            }.onFailure { error = "Could not save pairing. Try again." }
                    }.onFailure { error = "Invalid pairing code. Use the code shown on your Mac." }
            }
            PhoneCheckTheme {
                PhoneCheckScreen(
                    paired = BridgeState.paired, access = access, network = network,
                    networkBlocked = networkBlocked, listenerReady = BridgeState.listenerReady,
                    status = BridgeState.status, code = code, error = error, scanning = scanning,
                    onCodeChange = { code = it; error = null },
                    onPair = { pair(code) },
                    onScan = {
                        scanning = true; error = null
                        scanPairingCode(this) { value, failure ->
                            scanning = false
                            if (!BridgeState.paired) {
                                error = failure
                                if (value != null) pair(value)
                            }
                        }
                    },
                    onNotificationAccess = { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) },
                    onNetworkAccess = {
                        if (networkBlocked) {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName")))
                        } else if (Build.VERSION.SDK_INT >= 37) {
                            networkPermission.launch("android.permission.ACCESS_LOCAL_NETWORK")
                        }
                    },
                    onReconnect = {
                        android.service.notification.NotificationListenerService.requestRebind(
                            ComponentName(this, NotificationBridge::class.java))
                    },
                    onTestbed = { DevelopmentFeatures.openTestbed(this) },
                    onUnpair = {
                        runCatching { PairingStore(this).clear() }.onSuccess {
                            BridgeState.paired = false; BridgeState.service?.restart()
                        }.onFailure { error = "Could not unpair" }
                    }
                )
            }
        }
    }
    override fun onResume() { super.onResume(); refresh(); BridgeState.service?.restart() }
    private fun refresh() {
        access = getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(
            ComponentName(this, NotificationBridge::class.java))
        network = Build.VERSION.SDK_INT < 37 || checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED
        BridgeState.paired = PairingStore(this).load() != null
        if (!access && BridgeState.paired) BridgeState.status = "Allow notification access"
        else if (!network && BridgeState.paired) BridgeState.status = "Allow local network"
    }
}
