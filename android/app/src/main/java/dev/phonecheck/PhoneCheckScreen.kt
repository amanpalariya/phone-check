package dev.phonecheck

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import android.os.Build
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
internal fun PhoneCheckTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val colors = when {
        Build.VERSION.SDK_INT >= 31 && dark -> dynamicDarkColorScheme(context)
        Build.VERSION.SDK_INT >= 31 -> dynamicLightColorScheme(context)
        dark -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = colors, content = content)
}

@Composable
internal fun PhoneCheckScreen(
    signedIn: Boolean = true,
    signingIn: Boolean = false,
    accountName: String? = null,
    accountEmail: String? = null,
    onSignIn: () -> Unit = {},
    onSignOut: () -> Unit = {},
    paired: Boolean,
    access: Boolean,
    network: Boolean,
    networkBlocked: Boolean,
    listenerReady: Boolean,
    status: String,
    code: String,
    error: String?,
    scanning: Boolean,
    onCodeChange: (String) -> Unit,
    onPair: () -> Unit,
    onScan: () -> Unit,
    onNotificationAccess: () -> Unit,
    onNetworkAccess: () -> Unit,
    onReconnect: () -> Unit,
    onTestbed: () -> Unit,
    onUnpair: () -> Unit
) {
    var settingsPage by rememberSaveable { mutableStateOf<PhoneSettingsPage?>(null) }
    BackHandler(enabled = settingsPage != null) {
        settingsPage = if (settingsPage == PhoneSettingsPage.MAIN) null else PhoneSettingsPage.MAIN
    }
    var confirmUnpair by remember { mutableStateOf(false) }
    var manualPairing by rememberSaveable { mutableStateOf(false) }
    val connected = paired && access && network && status == "Connected"
    val symbol = when {
        !paired -> R.drawable.ic_laptop
        !access -> R.drawable.ic_bell
        !network -> R.drawable.ic_wifi
        else -> R.drawable.ic_phone
    }
    val heading = when {
        !signedIn -> "Connect your devices"
        !paired -> "Pair your Mac"
        !access -> "Notification access"
        !network -> "Connect over Wi-Fi"
        connected -> "Connected"
        status.contains("Disconnected") -> "Reconnecting"
        else -> "Connecting"
    }
    val detail = when {
        !signedIn -> "Use the same Google account on your Mac."
        !paired -> "Scan the QR code in Phone Check on your Mac."
        !access -> "Mirror notifications and use their actions on your Mac."
        !network -> "Allow access to your Mac on the local network."
        connected -> "Notifications appear on your Mac."
        else -> "Make sure both devices are online."
    }

    Surface(Modifier.fillMaxSize()) {
        if (settingsPage != null) {
            PhoneSettingsScreen(
                page = settingsPage!!, signedIn = signedIn, signingIn = signingIn,
                accountName = accountName, accountEmail = accountEmail,
                paired = paired, access = access, listenerReady = listenerReady, status = status, error = error,
                onBack = { settingsPage = if (settingsPage == PhoneSettingsPage.MAIN) null else PhoneSettingsPage.MAIN },
                onNavigate = { settingsPage = it }, onSetup = { settingsPage = null },
                onSignIn = onSignIn, onSignOut = onSignOut, onNotificationAccess = onNotificationAccess,
                onReconnect = onReconnect, onTestbed = onTestbed, onUnpair = { confirmUnpair = true }
            )
        } else Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
            Column(
                Modifier.align(Alignment.TopCenter).widthIn(max = 440.dp).fillMaxWidth()
                    .verticalScroll(rememberScrollState()).padding(horizontal = 28.dp)
            ) {
                Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(painterResource(R.drawable.ic_phone), contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(23.dp))
                    Text("Phone Check", style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(start = 9.dp).weight(1f))
                    IconButton(onClick = { settingsPage = PhoneSettingsPage.MAIN }) {
                        Icon(painterResource(R.drawable.ic_settings), contentDescription = "Settings",
                            modifier = Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }

                Column(Modifier.fillMaxWidth().padding(top = 52.dp, bottom = 34.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(76.dp).background(
                        MaterialTheme.colorScheme.primaryContainer, CircleShape),
                        contentAlignment = Alignment.Center) {
                        Icon(painterResource(symbol), contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(34.dp))
                    }
                    Text(heading, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center, modifier = Modifier.padding(top = 24.dp))
                    Text(detail, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 10.dp).widthIn(max = 290.dp))
                }

                if (!signedIn) {
                    PrimaryButton(if (signingIn) "Signing in…" else "Sign in with Google", enabled = !signingIn, onClick = onSignIn)
                } else if (!paired) {
                    if (!manualPairing) {
                        PrimaryButton(if (scanning) "Opening scanner…" else "Scan QR code",
                            enabled = !scanning, onClick = onScan)
                        TextButton(onClick = { manualPairing = true }, enabled = !scanning,
                            modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("Enter code instead") }
                    } else {
                        TextField(value = code, onValueChange = onCodeChange,
                            label = { Text("Mac pairing code") }, minLines = 2, maxLines = 4,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                            modifier = Modifier.fillMaxWidth(), isError = error != null,
                            shape = MaterialTheme.shapes.medium)
                        Spacer(Modifier.height(16.dp))
                        PrimaryButton("Pair Mac", enabled = code.isNotBlank(), onClick = onPair)
                        TextButton(onClick = { manualPairing = false },
                            modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("Scan QR code instead") }
                    }
                } else if (!access) {
                    PrimaryButton("Allow notification access", onClick = onNotificationAccess)
                } else if (!network) {
                    PrimaryButton(if (networkBlocked) "Open settings" else "Allow local network", onClick = onNetworkAccess)
                } else if (!listenerReady) {
                    PrimaryButton("Reconnect", onClick = onReconnect)
                }
                error?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 14.dp).fillMaxWidth(), textAlign = TextAlign.Center)
                }
                Spacer(Modifier.height(32.dp))
            }
        }
        if (confirmUnpair) AlertDialog(onDismissRequest = { confirmUnpair = false },
            title = { Text("Unpair Mac?") },
            confirmButton = { TextButton(onClick = { onUnpair(); confirmUnpair = false }) { Text("Unpair") } },
            dismissButton = { TextButton(onClick = { confirmUnpair = false }) { Text("Cancel") } })
    }
}

@Composable
private fun PrimaryButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp)) {
        Text(text, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
    }
}
