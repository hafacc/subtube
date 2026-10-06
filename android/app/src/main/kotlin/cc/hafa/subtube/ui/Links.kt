package cc.hafa.subtube.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import cc.hafa.subtube.R

/** Where the privacy policy is published. */
const val PRIVACY_POLICY_URL: String = "https://subtube.hafa.cc/privacy"

/** Where the terms are published. */
const val TERMS_URL: String = "https://subtube.hafa.cc/terms"

/** Where the "Videos from YouTube" line leads. */
const val YOUTUBE_URL: String = "https://www.youtube.com/"

/** Open [url] in the browser; nothing happens on a device without one. */
fun Context.openInBrowser(url: String) {
    try {
        startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
    } catch (_: ActivityNotFoundException) {
        // no browser to open it in
    }
}

/** The line under a sign-in button: signing in agrees to the terms and the privacy policy, each a link. */
@Composable
fun SignInAgreement(modifier: Modifier = Modifier) {
    val terms = stringResource(R.string.terms)
    val privacy = stringResource(R.string.sign_in_agreement_privacy)
    val sentence = stringResource(R.string.sign_in_agreement, terms, privacy)
    val linkStyles = TextLinkStyles(SpanStyle(color = MaterialTheme.brand.accent, textDecoration = TextDecoration.Underline))
    val text = buildAnnotatedString {
        var written = 0
        // in the order they stand in the sentence, whatever a translation makes it
        for ((label, url) in listOf(terms to TERMS_URL, privacy to PRIVACY_POLICY_URL).sortedBy { (label, _) -> sentence.indexOf(label) }) {
            val start = sentence.indexOf(label, written)
            if (start >= 0) {
                append(sentence.substring(written, start))
                withLink(LinkAnnotation.Url(url, linkStyles)) { append(label) }
                written = start + label.length
            }
        }
        append(sentence.substring(written))
    }
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = modifier.fillMaxWidth(),
    )
}

/** "Videos from YouTube", a link to youtube.com, at the end of a list. */
@Composable
fun YouTubeAttribution(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Text(
            stringResource(R.string.videos_from_youtube),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { context.openInBrowser(YOUTUBE_URL) }
                .padding(horizontal = 16.dp)
                .wrapContentHeight(),
        )
    }
}
