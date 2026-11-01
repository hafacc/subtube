package cc.hafa.subtube.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.DisableSelection
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.InfoPage
import cc.hafa.subtube.core.InfoText
import cc.hafa.subtube.core.infoText
import cc.hafa.subtube.core.readInfoPage
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** A page of shared/pages the app shows itself, bundled as an asset. */
enum class InfoPageName(
    /** The page's file under the app's assets. */
    val asset: String,
) {
    /** The privacy policy. */
    PRIVACY("pages/privacy.json"),

    /** The terms. */
    TERMS("pages/terms.json"),
}

/**
 * The privacy policy or the terms, shown in the app: the title in the top
 * bar with Back and "Open on the web" (the page's `web` address), then
 * "Last updated", the intro and each section's bulleted items, all selectable.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoScreen(viewModel: SubtubeViewModel, name: InfoPageName) {
    val context = LocalContext.current
    val page = remember(name) { context.assets.open(name.asset).use { stream -> readInfoPage(stream.readBytes().decodeToString()) } }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(page.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = viewModel::pop) {
                        Icon(SubtubeIcons.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    IconButton(onClick = { context.openInBrowser(page.web) }) {
                        Icon(SubtubeIcons.OpenInNew, contentDescription = stringResource(R.string.open_on_web))
                    }
                },
            )
        },
    ) { padding ->
        SelectionContainer(Modifier.fillMaxSize().padding(padding)) {
            InfoBody(page, Modifier.padding(start = 24.dp, top = 8.dp, end = 24.dp, bottom = 24.dp + minimizedPlayerRoom(viewModel)))
        }
    }
}

@Composable
private fun InfoBody(page: InfoPage, modifier: Modifier) {
    val locale = LocalConfiguration.current.locales[0]
    val updated = remember(page.updated, locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale).format(LocalDate.parse(page.updated))
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).then(modifier),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            stringResource(R.string.last_updated, updated),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        for (paragraph in page.intro) {
            Text(linkedText(paragraph), style = MaterialTheme.typography.bodyLarge)
        }
        for (section in page.sections) {
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(section.heading, style = MaterialTheme.typography.titleMedium)
                for (item in section.items) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        DisableSelection {
                            Text("•", style = MaterialTheme.typography.bodyLarge)
                        }
                        Text(linkedText(item), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** A page's text with each `[label](url)` a link, styled as the app's other links. */
@Composable
private fun linkedText(text: String): AnnotatedString {
    val context = LocalContext.current
    val styles = linkStyles()
    return remember(text, styles) {
        buildAnnotatedString {
            for (run in infoText(text)) {
                when (run) {
                    is InfoText.Plain -> append(run.text)
                    is InfoText.Link -> withLink(LinkAnnotation.Url(run.url, styles) { context.openInBrowser(run.url) }) { append(run.label) }
                }
            }
        }
    }
}
