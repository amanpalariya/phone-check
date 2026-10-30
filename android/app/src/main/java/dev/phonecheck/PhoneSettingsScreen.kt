package dev.phonecheck

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

internal enum class PhoneSettingsPage(val title: String) {
    MAIN("Settings"), ACCOUNT("Account"), DEVICE("Devices"), ADVANCED("Advanced")
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
    access: Boolean,
    listenerReady: Boolean,
    status: String,
    error: String?,
    onBack: () -> Unit,
    onNavigate: (PhoneSettingsPage) -> Unit,
    onSetup: () -> Unit,
    onSignIn: () -> Unit,
    onSignOut: () -> Unit,
    onNotificationAccess: () -> Unit,
    onReconnect: () -> Unit,
    onTestbed: () -> Unit,
    onUnpair: () -> Unit
) {
    var confirmSignOut by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val version = remember(context) { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() }
    val name = accountName?.takeIf { it.isNotBlank() } ?: "Google account"
    val connected = paired && access && listenerReady && status == "Connected"
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
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Column(Modifier.widthIn(max = 520.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                when (page) {
                    PhoneSettingsPage.MAIN -> {
                        SettingsCard(onClick = { onNavigate(PhoneSettingsPage.ACCOUNT) }) {
                            Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                AccountAvatar(if (signedIn) accountName else null, 60.dp)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(if (signedIn) name else "Your account", style = MaterialTheme.typography.titleMedium)
                                    Text(if (signedIn) accountEmail ?: "Signed in with Google" else "Sign in with Google",
                                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                                SettingsChevron()
                            }
                        }
                        SettingsGroup("General") {
                            SettingsRow("Notification access", if (access) "Allowed" else "Required to mirror notifications",
                                R.drawable.ic_bell, onNotificationAccess)
                        }
                        SettingsGroup("Devices") {
                            SettingsRow(if (paired) "Mac" else "Pair your Mac",
                                when { !paired -> "Connect using a QR code"; connected -> "Connected"; else -> "Waiting for Mac" },
                                R.drawable.ic_laptop, { onNavigate(PhoneSettingsPage.DEVICE) })
                        }
                        if (DevelopmentFeatures.enabled) SettingsGroup("Developer") {
                            SettingsRow("Advanced", "Notification testbed", R.drawable.ic_settings,
                                { onNavigate(PhoneSettingsPage.ADVANCED) })
                        }
                        Text("Phone Check${version?.let { " $it" }.orEmpty()}",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    }
                    PhoneSettingsPage.ACCOUNT -> {
                        SettingsCard {
                            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 32.dp),
                                horizontalAlignment = Alignment.CenterHorizontally) {
                                AccountAvatar(if (signedIn) accountName else null, 96.dp)
                                Text(if (signedIn) name else "Sign in to Phone Check",
                                    style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold,
                                    textAlign = TextAlign.Center, modifier = Modifier.padding(top = 20.dp))
                                Text(if (signedIn) accountEmail ?: "Signed in with Google" else "Sign in to sync beyond your local network.",
                                    style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
                                Spacer(Modifier.height(24.dp))
                                if (signedIn) OutlinedButton(onClick = { confirmSignOut = true }) { Text("Sign out") }
                                else Button(onClick = onSignIn, enabled = !signingIn) {
                                    Text(if (signingIn) "Signing in…" else "Sign in with Google")
                                }
                            }
                        }
                        if (signedIn) Text("Your name and email are managed by Google.",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    }
                    PhoneSettingsPage.DEVICE -> {
                        SettingsCard {
                            Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(Modifier.size(80.dp).background(MaterialTheme.colorScheme.secondaryContainer, CircleShape),
                                    contentAlignment = Alignment.Center) {
                                    Icon(painterResource(R.drawable.ic_laptop), contentDescription = null, modifier = Modifier.size(38.dp),
                                        tint = MaterialTheme.colorScheme.onSecondaryContainer)
                                }
                                Text(if (paired) "Mac" else "Pair your Mac", style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 20.dp))
                                Text(when { !paired -> "Scan the QR code in Phone Check on your Mac."
                                    !access -> "Allow notification access to start syncing."
                                    connected -> "Connected"; else -> "Waiting for Mac" },
                                    style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
                                Spacer(Modifier.height(24.dp))
                                when {
                                    !paired -> Button(onClick = onSetup) { Text("Pair Mac") }
                                    !access -> Button(onClick = onNotificationAccess) { Text("Allow notification access") }
                                    !connected -> FilledTonalButton(onClick = onReconnect) { Text("Reconnect") }
                                }
                                if (paired) TextButton(onClick = onUnpair,
                                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Unpair Mac") }
                            }
                        }
                        Text("Notification content is encrypted between your devices.",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    }
                    PhoneSettingsPage.ADVANCED -> if (DevelopmentFeatures.enabled) SettingsGroup("Developer") {
                        SettingsRow("Notification testbed", "Try sample notifications and actions", R.drawable.ic_bell, onTestbed)
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
private fun SettingsCard(onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier),
        shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerLow
    ) { Column(content = content) }
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
private fun SettingsRow(title: String, detail: String, icon: Int, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) }, supportingContent = { Text(detail) },
        leadingContent = {
            Icon(painterResource(icon), contentDescription = null, modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        },
        trailingContent = { SettingsChevron() },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick).padding(vertical = 6.dp)
    )
}

@Composable
private fun SettingsChevron() {
    Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
}

@Composable
private fun AccountAvatar(name: String?, size: Dp) {
    val initials = name.orEmpty().trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        .take(2).joinToString("") { it.take(1) }.uppercase()
    Box(Modifier.size(size).background(MaterialTheme.colorScheme.secondaryContainer, CircleShape).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        if (initials.isNotEmpty()) Text(initials, style = if (size > 64.dp) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSecondaryContainer)
        else Icon(painterResource(R.drawable.ic_person), contentDescription = null, modifier = Modifier.size(size * 0.48f),
            tint = MaterialTheme.colorScheme.onSecondaryContainer)
    }
}
