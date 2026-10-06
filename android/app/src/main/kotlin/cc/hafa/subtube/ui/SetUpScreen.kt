package cc.hafa.subtube.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.StartFrom
import cc.hafa.subtube.core.matchesSearch

/** First run: what subtube is, signing in, choosing channels, the Shorts choice, where to start, done. */
@Composable
fun SetUpScreen(viewModel: SubtubeViewModel) {
    val step = viewModel.setUpStep
    val steps = SetUpStep.entries
    val back = { viewModel.goToStep(steps[step.ordinal - 1]) }
    // the last screen only goes on: Back there leaves the app, as on the first
    val offersBack = step != SetUpStep.INTRO && step != SetUpStep.DONE
    BackHandler(enabled = offersBack, onBack = back)
    Column(Modifier.fillMaxSize().safeDrawingPadding()) {
        Row(
            Modifier.fillMaxWidth().height(64.dp).padding(start = 4.dp, end = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (offersBack) {
                IconButton(onClick = back) {
                    Icon(SubtubeIcons.ArrowBack, contentDescription = stringResource(R.string.back))
                }
            } else {
                Spacer(Modifier.size(48.dp))
            }
            val progress = stringResource(R.string.step_of, step.ordinal + 1, steps.size)
            Row(
                Modifier.weight(1f).height(4.dp).clearAndSetSemantics { contentDescription = progress },
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                for (segment in steps.indices) {
                    Box(
                        Modifier
                            .weight(1f)
                            .fillMaxSize()
                            .clip(RoundedCornerShape(2.dp))
                            .background(if (segment <= step.ordinal) MaterialTheme.brand.accent else MaterialTheme.colorScheme.surfaceContainerHighest),
                    )
                }
            }
        }
        AnimatedContent(
            targetState = step,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "setUpStep",
            modifier = Modifier.weight(1f),
        ) { shown ->
            Column(Modifier.fillMaxSize().padding(start = 24.dp, top = 8.dp, end = 24.dp, bottom = 24.dp)) {
                when (shown) {
                    SetUpStep.INTRO -> IntroStep { viewModel.goToStep(SetUpStep.SIGN_IN) }
                    SetUpStep.SIGN_IN -> SignInStep(viewModel)
                    SetUpStep.CHANNELS -> ChannelsStep(viewModel)
                    SetUpStep.SHORTS -> ShortsStep(viewModel)
                    SetUpStep.START -> StartStep(viewModel)
                    SetUpStep.DONE -> DoneStep(viewModel::finishSetUp)
                }
            }
        }
    }
}

@Composable
private fun StepTitle(text: String) {
    Text(text, style = MaterialTheme.typography.headlineMedium)
}

@Composable
private fun StepBody(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun ColumnScope.IntroStep(onNext: () -> Unit) {
    Column(
        Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 40.dp),
        verticalArrangement = Arrangement.spacedBy(32.dp),
    ) {
        Wordmark(fontSize = 36)
        Text(stringResource(R.string.intro_title), style = MaterialTheme.typography.headlineMedium)
        Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
            IntroPoint(SubtubeIcons.Subscriptions, stringResource(R.string.intro_subscriptions))
            IntroPoint(SubtubeIcons.Filters, stringResource(R.string.intro_filters))
            IntroPoint(SubtubeIcons.Eye, stringResource(R.string.intro_watched))
        }
    }
    BigButton(onClick = onNext) { Text(stringResource(R.string.get_started), style = MaterialTheme.typography.titleMedium) }
}

@Composable
private fun IntroPoint(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(
            Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(22.dp))
        }
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun ColumnScope.SignInStep(viewModel: SubtubeViewModel) {
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        StepTitle(stringResource(R.string.sign_in_title))
        StepBody(stringResource(R.string.sign_in_lead))
        PermissionCard(SubtubeIcons.Subscriptions, stringResource(R.string.permission_youtube_title), stringResource(R.string.permission_youtube_body))
        PermissionCard(SubtubeIcons.Folder, stringResource(R.string.permission_drive_title), stringResource(R.string.permission_drive_body))
        Text(
            stringResource(R.string.sign_in_footnote),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        viewModel.signInError?.let { message ->
            Text(
                message.resolve(LocalContext.current),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
    GoogleSignInButton(onClick = viewModel::signIn, busy = viewModel.signingIn)
    SignInAgreement(Modifier.padding(top = 12.dp))
}

@Composable
private fun PermissionCard(icon: ImageVector, title: String, body: String) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.brand.accent)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ColumnScope.ChannelsStep(viewModel: SubtubeViewModel) {
    var query by rememberSaveable { mutableStateOf("") }
    val context = LocalContext.current
    val channels = viewModel.setUpChannels
    val enabled = viewModel.setUpEnabled
    val onCount = channels.count { channel -> enabled[channel.channelId] ?: channel.enabled }
    val error = viewModel.setUpError
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (viewModel.setUpLoading) {
            // nothing but the rows while they load, as on the web
            SkeletonChannelRows()
        } else {
            StepTitle(stringResource(R.string.choose_channels_title))
            StepBody(stringResource(R.string.choose_channels_body))
            if (error != null) {
                Text(error.resolve(context), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    SearchField(query, { text -> query = text }, Modifier.weight(1f))
                    AccentTextButton(
                        stringResource(if (onCount > 0) R.string.turn_all_off else R.string.turn_all_on),
                        onClick = { viewModel.setAllSetUpChannels(onCount == 0) },
                    )
                }
                if (channels.isEmpty()) {
                    StepBody(stringResource(R.string.no_subscriptions))
                }
                val shown = channels.filter { channel -> matchesSearch(channel.title, query) }
                LazyColumn(Modifier.weight(1f)) {
                    items(shown, key = ChannelFilter::channelId) { channel ->
                        val row = channel.copy(enabled = enabled[channel.channelId] ?: channel.enabled)
                        ChannelRow(
                            channel = row,
                            summary = filterSummary(context, row),
                            onOpen = null,
                            onToggle = { viewModel.toggleSetUpChannel(channel.channelId) },
                            edgePadding = false,
                        )
                    }
                }
            }
        }
    }
    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (!viewModel.setUpLoading && error == null) {
            Text(
                stringResource(R.string.channels_on_count, onCount, channels.size),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        BigButton(onClick = viewModel::finishSetUpChannels, enabled = !viewModel.setUpLoading && viewModel.setUpError == null) {
            Text(stringResource(R.string.next), style = MaterialTheme.typography.titleMedium)
        }
    }
}

/** First run's Shorts choice for every channel at once, with the filter sheet's own control. */
@Composable
private fun ColumnScope.ShortsStep(viewModel: SubtubeViewModel) {
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StepTitle(stringResource(R.string.shorts))
        StepBody(stringResource(R.string.shorts_step_body))
        SectionLabel(stringResource(R.string.shorts))
        ShortsChoice(selected = viewModel.setUpShorts, onSelect = { choice -> viewModel.setUpShorts = choice })
    }
    BigButton(onClick = viewModel::finishSetUpShorts) { Text(stringResource(R.string.next), style = MaterialTheme.typography.titleMedium) }
}

/** First run's starting point: videos from before it are marked watched at the first load. */
@Composable
private fun ColumnScope.StartStep(viewModel: SubtubeViewModel) {
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StepTitle(stringResource(R.string.where_to_start))
        StepBody(stringResource(R.string.where_to_start_body))
        SectionLabel(stringResource(R.string.where_to_start))
        Segmented(
            options = listOf(StartFrom.DAY to R.string.time_day, StartFrom.WEEK to R.string.time_week, StartFrom.ALL to R.string.time_all),
            selected = viewModel.setUpStart,
            onSelect = { choice -> viewModel.setUpStart = choice },
        )
    }
    BigButton(onClick = { viewModel.goToStep(SetUpStep.DONE) }) { Text(stringResource(R.string.next), style = MaterialTheme.typography.titleMedium) }
}

@Composable
private fun ColumnScope.DoneStep(onOpenFeed: () -> Unit) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically)) {
        Box(
            Modifier.size(72.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(SubtubeIcons.Check, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(36.dp))
        }
        StepTitle(stringResource(R.string.youre_set_title))
        StepBody(stringResource(R.string.youre_set_body))
    }
    BigButton(onClick = onOpenFeed) { Text(stringResource(R.string.open_my_feed), style = MaterialTheme.typography.titleMedium) }
}
