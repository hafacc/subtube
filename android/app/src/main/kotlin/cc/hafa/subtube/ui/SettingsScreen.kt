package cc.hafa.subtube.ui

import android.text.format.DateUtils
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.data.ThemeMode
import kotlinx.coroutines.delay

/** How often the "Last synced" line is worked out again. */
private const val SYNC_STATUS_REFRESH_MS = 30_000L

/** The settings tab: account, sync status, theme, sign out, delete profile, privacy policy and terms. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SubtubeViewModel) {
    val account = (viewModel.session as? Session.SignedIn)?.account
    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.settings)) }) },
        bottomBar = { MainNavigationBar(Screen.Settings, viewModel::selectTab) },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 16.dp + minimizedPlayerRoom(viewModel)),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            if (account != null) {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer, shape = RoundedCornerShape(12.dp)) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        val user = viewModel.user
                        LaunchedEffect(account.channelId) { viewModel.loadUser() }
                        ChannelAvatar(user?.displayName ?: account.title, account.thumbnail, size = 48.dp)
                        Column {
                            Text(user?.displayName ?: account.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                            user?.emailAddress?.let { email ->
                                Text(email, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            SyncStatus(viewModel.lastSynced)
            Column(Modifier.padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.theme), style = MaterialTheme.typography.titleSmall)
                Segmented(
                    options = listOf(ThemeMode.SYSTEM to R.string.theme_system, ThemeMode.LIGHT to R.string.theme_light, ThemeMode.DARK to R.string.theme_dark),
                    selected = viewModel.themeMode,
                    onSelect = viewModel::chooseTheme,
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Column(Modifier.padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = viewModel::signOut,
                    enabled = !viewModel.signingOut,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.brand.accent),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) {
                    if (viewModel.signingOut) {
                        Spinner(size = 18.dp)
                    } else {
                        Icon(SubtubeIcons.Logout, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                    Text(stringResource(R.string.sign_out), modifier = Modifier.padding(start = 8.dp))
                }
                Text(
                    stringResource(R.string.sign_out_note),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                viewModel.signOutError?.let { message ->
                    Text(message.resolve(LocalContext.current), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
                }
            }
            Column(Modifier.padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                var confirming by remember { mutableStateOf(false) }
                OutlinedButton(
                    onClick = { confirming = true },
                    enabled = !viewModel.deletingProfile,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) {
                    if (viewModel.deletingProfile) {
                        Spinner(size = 18.dp)
                    }
                    Text(stringResource(R.string.delete_profile), modifier = Modifier.padding(start = if (viewModel.deletingProfile) 8.dp else 0.dp))
                }
                Text(
                    stringResource(R.string.delete_profile_note),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                viewModel.deleteError?.let { message ->
                    Text(message.resolve(LocalContext.current), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
                }
                if (confirming) {
                    CoversPlayer(viewModel)
                    AlertDialog(
                        onDismissRequest = { confirming = false },
                        title = { Text(stringResource(R.string.delete_profile_title)) },
                        text = { Text(stringResource(R.string.delete_profile_body)) },
                        confirmButton = {
                            TextButton(
                                onClick = {
                                    confirming = false
                                    viewModel.deleteProfile()
                                },
                                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                            ) {
                                Text(stringResource(R.string.delete_profile))
                            }
                        },
                        dismissButton = { AccentTextButton(stringResource(R.string.cancel), onClick = { confirming = false }) },
                    )
                }
            }
            val context = LocalContext.current
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                AccentTextButton(stringResource(R.string.privacy_policy), onClick = { context.openInBrowser(PRIVACY_POLICY_URL) })
                AccentTextButton(stringResource(R.string.terms), onClick = { context.openInBrowser(TERMS_URL) })
            }
        }
    }
}

@Composable
private fun SyncStatus(lastSynced: Long?) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(SYNC_STATUS_REFRESH_MS)
            now = System.currentTimeMillis()
        }
    }
    Row(Modifier.padding(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(SubtubeIcons.CloudDone, contentDescription = null, tint = MaterialTheme.brand.accent, modifier = Modifier.padding(top = 2.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.synced_with_drive), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            val synced = if (lastSynced == null) {
                stringResource(R.string.syncing)
            } else if (now - lastSynced < DateUtils.MINUTE_IN_MILLIS) {
                stringResource(R.string.last_synced_now)
            } else {
                val ago = DateUtils.getRelativeTimeSpanString(lastSynced, maxOf(now, lastSynced), DateUtils.MINUTE_IN_MILLIS)
                stringResource(R.string.last_synced, ago)
            }
            Text(synced, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                stringResource(R.string.sync_explainer),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
