package dev.phonecheck

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap

internal enum class PhoneSettingsPage(val title: String) {
    MAIN("Settings"), ADVANCED("Advanced")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PhoneSettingsScreen(
    page: PhoneSettingsPage,
    signedIn: Boolean,
    signingIn: Boolean,
    accountName: String?,
    accountEmail: String?,
    paired: Boolean,
    localOnly: Boolean,
    access: Boolean,
    network: Boolean,
    networkBlocked: Boolean,
    listenerReady: Boolean,
    status: String,
    error: String?,
    onBack: () -> Unit,
    onNavigate: (PhoneSettingsPage) -> Unit,
    onSetup: () -> Unit,
    onSignIn: () -> Unit,
    onSignOut: () -> Unit,
    onNotificationAccess: () -> Unit,
    onNetworkAccess: () -> Unit,
    onReconnect: () -> Unit,
    onTestbed: () -> Unit,
    onUnpair: () -> Unit
) {
    var confirmSignOut by remember { mutableStateOf(false) }
    val name = accountName?.takeIf { it.isNotBlank() } ?: "Google account"
    val canReconnect = paired && access && (!localOnly || network) && (localOnly || signedIn)
    val connected = canReconnect && listenerReady && status == "Connected"
    val deviceDetail = when {
        !paired -> "Scan the QR code on your Mac."
        !localOnly && !signedIn -> "Sign in to connect."
        !access -> "Allow notification access to sync."
        localOnly && !network -> "Allow local network access to connect."
        connected -> "Connected"
        else -> status
    }
    Scaffold(
        topBar = {
            TopAppBar(title = { Text(page.title) }, navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Back")
                }
            })
        }
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Column(Modifier.widthIn(max = 520.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                when (page) {
                    PhoneSettingsPage.MAIN -> {
                        AppDetails()
                        SettingsGroup("General") {
                            SettingsRow(
                                title = if (signedIn) name else "Google account",
                                detail = if (signedIn) accountEmail ?: "Signed in with Google" else "Optional for cloud sync.",
                                icon = R.drawable.ic_person,
                                containerColor = MaterialTheme.colorScheme.primaryContainer,
                                iconColor = MaterialTheme.colorScheme.onPrimaryContainer,
                                action = {
                                    TextButton(onClick = if (signedIn) ({ confirmSignOut = true }) else onSignIn,
                                        enabled = !signingIn) {
                                        Text(if (signedIn) "Sign out" else if (signingIn) "Signing in…" else "Sign in")
                                    }
                                }
                            )
                            SettingsDivider()
                            SettingsRow(
                                title = if (paired) "Mac" else "Pair your Mac",
                                detail = deviceDetail,
                                icon = R.drawable.ic_laptop,
                                containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                                iconColor = MaterialTheme.colorScheme.onTertiaryContainer,
                                action = {
                                    if (paired) TextButton(onClick = onUnpair) { Text("Unpair") }
                                    else Button(onClick = onSetup) { Text("Pair Mac") }
                                }
                            )
                            if (canReconnect && !connected) {
                                TextButton(onClick = onReconnect, modifier = Modifier.padding(start = 60.dp, bottom = 8.dp)) {
                                    Text("Reconnect")
                                }
                            }
                        }
                        if (!access || (paired && !network)) SettingsCard {
                            if (!access) SettingsRow(
                                "Notification access", "Required to mirror notifications.", R.drawable.ic_bell,
                                action = { FilledTonalButton(onClick = onNotificationAccess) { Text("Allow") } }
                            )
                            if (!access && paired && !network) SettingsDivider()
                            if (paired && !network) SettingsRow(
                                "Local network", if (localOnly) "Connect to your Mac over Wi-Fi." else "Use Wi-Fi nearby to save cloud data.",
                                R.drawable.ic_wifi,
                                action = {
                                    TextButton(onClick = onNetworkAccess) { Text(if (networkBlocked) "Settings" else "Allow") }
                                }
                            )
                        }
                        Row(Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(painterResource(R.drawable.ic_lock), contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                            Text("Notification content is encrypted between your devices.",
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (DevelopmentFeatures.enabled) TextButton(onClick = { onNavigate(PhoneSettingsPage.ADVANCED) }) {
                            Text("Advanced")
                        }
                    }
                    PhoneSettingsPage.ADVANCED -> if (DevelopmentFeatures.enabled) SettingsGroup("Developer") {
                        SettingsRow("Notification testbed", "Try sample notifications and actions.", R.drawable.ic_bell,
                            action = { TextButton(onClick = onTestbed) { Text("Open") } })
                    }
                }
                if (error != null) Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
    if (confirmSignOut) AlertDialog(onDismissRequest = { confirmSignOut = false },
        title = { Text("Sign out of Phone Check?") },
        text = { Text("Cloud sync will stop. Local-only pairing stays connected.") },
        confirmButton = { TextButton(onClick = { confirmSignOut = false; onSignOut() },
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Sign out") } },
        dismissButton = { TextButton(onClick = { confirmSignOut = false }) { Text("Cancel") } })
}

@Composable
private fun AppDetails() {
    val context = LocalContext.current
    val version = remember(context) {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull()
    }
    val icon = remember(context) {
        context.packageManager.getApplicationIcon(context.packageName).toBitmap(128, 128).asImageBitmap()
    }
    Row(Modifier.padding(horizontal = 4.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Image(icon, contentDescription = null, modifier = Modifier.size(56.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Phone Check", style = MaterialTheme.typography.titleLarge)
            version?.let { Text("Version $it", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable
private fun SettingsCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow) { Column(content = content) }
}

@Composable
private fun SettingsGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(start = 16.dp))
        SettingsCard(content = content)
    }
}

@Composable
private fun SettingsDivider() {
    HorizontalDivider(Modifier.padding(start = 68.dp, end = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
private fun SettingsRow(
    title: String,
    detail: String,
    icon: Int,
    containerColor: Color = MaterialTheme.colorScheme.secondaryContainer,
    iconColor: Color = MaterialTheme.colorScheme.onSecondaryContainer,
    action: @Composable () -> Unit
) {
    val stackedAction = LocalDensity.current.fontScale >= 1.3f
    Column(Modifier.padding(vertical = 6.dp)) {
        ListItem(
            headlineContent = { Text(title, style = MaterialTheme.typography.titleSmall) },
            supportingContent = { Text(detail) },
            leadingContent = {
                Box(Modifier.size(36.dp).background(containerColor, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                    Icon(painterResource(icon), contentDescription = null, modifier = Modifier.size(22.dp), tint = iconColor)
                }
            },
            trailingContent = if (stackedAction) null else action,
            colors = ListItemDefaults.colors(containerColor = Color.Transparent)
        )
        if (stackedAction) Box(Modifier.padding(start = 68.dp, end = 16.dp, bottom = 8.dp)) { action() }
    }
}
