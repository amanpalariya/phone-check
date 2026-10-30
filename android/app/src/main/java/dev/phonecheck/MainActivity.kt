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
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var signedIn by mutableStateOf(false)
    private var signingIn by mutableStateOf(false)
    private var authError by mutableStateOf<String?>(null)
    private var access by mutableStateOf(false)
    private val authListener = com.google.firebase.auth.FirebaseAuth.AuthStateListener {
        signedIn = it.currentUser != null; refresh(); BridgeState.service?.restart()
    }
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
        CloudAccount.auth.addAuthStateListener(authListener)
        setContent {
            var code by remember { mutableStateOf("") }
            var error by remember { mutableStateOf<String?>(null) }
            var scanning by remember { mutableStateOf(false) }
            val pair: (String) -> Unit = { value ->
                runCatching {
                    val project = if (value.trim().startsWith("pc2|")) com.google.firebase.FirebaseApp.getInstance().options.projectId else null
                    Pairing.parse(value, project)
                }
                    .onSuccess { pairing ->
                        val savePairing = {
                            runCatching { PairingStore(this@MainActivity).save(pairing) }
                                .onSuccess {
                                    code = ""; error = null
                                    BridgeState.paired = true; BridgeState.localOnly = pairing.isLocalOnly
                                    BridgeState.status = "Allow notification access"
                                    BridgeState.service?.restart()
                                }.onFailure { error = "Could not save pairing. Pair again on your Mac." }
                            Unit
                        }
                        if (pairing.isLocalOnly) {
                            savePairing(); return@onSuccess
                        }
                        if (pairing.ownerUID != CloudAccount.auth.currentUser?.uid) {
                            error = "Sign in with the same Google account as your Mac."; return@onSuccess
                        }
                        CloudPairing.join(pairing) { joined ->
                            if (!joined) { error = "Pairing code expired or already used." }
                            else savePairing()
                        }
                    }.onFailure { error = "Invalid pairing code. Use the code shown on your Mac." }
            }
            PhoneCheckTheme {
                PhoneCheckScreen(
                    signedIn = signedIn, signingIn = signingIn,
                    accountName = CloudAccount.auth.currentUser?.displayName,
                    accountEmail = CloudAccount.auth.currentUser?.email,
                    onSignIn = {
                        lifecycleScope.launch {
                            signingIn = true; authError = null
                            try { CloudAccount.signIn(this@MainActivity) }
                            catch (_: androidx.credentials.exceptions.GetCredentialCancellationException) { }
                            catch (_: Exception) { authError = "Could not sign in. Try again." }
                            finally { signingIn = false }
                        }
                    },
                    onSignOut = {
                        val uid = CloudAccount.auth.currentUser?.uid
                        if (PairingStore(this).load()?.isLocalOnly == true) {
                            CloudAccount.auth.signOut()
                        } else if (uid != null) CloudAccount.root(uid).removeValue { failure, _ ->
                            if (failure != null) error = "Could not sign out. Try again."
                            else runCatching { PairingStore(this).clear() }.onSuccess {
                                CloudAccount.auth.signOut(); BridgeState.service?.restart()
                            }.onFailure { error = "Could not clear pairing" }
                        }
                    },
                    paired = BridgeState.paired, localOnly = BridgeState.localOnly, access = access, network = network,
                    networkBlocked = networkBlocked, listenerReady = BridgeState.listenerReady,
                    status = BridgeState.status, code = code, error = error ?: authError, scanning = scanning,
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
                        if (BridgeState.listenerReady) BridgeState.service?.restart()
                        else android.service.notification.NotificationListenerService.requestRebind(
                            ComponentName(this, NotificationBridge::class.java))
                    },
                    onTestbed = { DevelopmentFeatures.openTestbed(this) },
                    onUnpair = {
                        val saved = PairingStore(this).load()
                        val uid = CloudAccount.auth.currentUser?.uid
                        if (uid != null && uid == saved?.ownerUID) {
                            CloudAccount.root(uid).removeValue { failure, _ ->
                                if (failure != null) { error = "Could not unpair. Try again." }
                                else runCatching { PairingStore(this).clear() }.onSuccess {
                                    BridgeState.paired = false; BridgeState.service?.restart()
                                }.onFailure { error = "Could not clear pairing" }
                            }
                        } else runCatching { PairingStore(this).clear() }.onSuccess {
                            BridgeState.paired = false; BridgeState.service?.restart()
                        }.onFailure { error = "Could not clear pairing" }
                    }
                )
            }
        }
    }
    override fun onDestroy() { CloudAccount.auth.removeAuthStateListener(authListener); super.onDestroy() }
    override fun onResume() { super.onResume(); refresh(); BridgeState.service?.restart() }
    private fun refresh() {
        access = getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(
            ComponentName(this, NotificationBridge::class.java))
        network = Build.VERSION.SDK_INT < 37 || checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED
        val pairing = PairingStore(this).load()
        BridgeState.paired = pairing != null
        BridgeState.localOnly = pairing?.isLocalOnly == true
        if (!access && BridgeState.paired) BridgeState.status = "Allow notification access"

    }
}
