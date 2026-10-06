package cc.hafa.subtube.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.groupName
import cc.hafa.subtube.core.channelsByName
import cc.hafa.subtube.core.matchesSearch
import kotlinx.coroutines.launch

/**
 * The group editor, in a bottom sheet: a name, then every listed channel by
 * name with a switch for being in the group, the channel list's search field
 * over them.
 *
 * It edits a draft: nothing is saved until "Save", which needs a name (one
 * too long is kept as typed and can't be saved) and a channel switched on;
 * "Cancel" and dismissing the sheet discard it. Every button that closes the
 * sheet slides it away first. [group] is the group edited, which also gets
 * "Delete group" (deleting at once) while it still exists, or null for a new one. Only the channel rows scroll. See
 * [SubtubeViewModel.saveGroup] and [SubtubeViewModel.deleteGroup].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupEditor(viewModel: SubtubeViewModel, group: String?, onClose: () -> Unit) {
    val context = LocalContext.current
    val focus = LocalFocusManager.current
    val channels = viewModel.channels.values.sortedWith(channelsByName)
    var name by rememberSaveable(group) { mutableStateOf(group.orEmpty()) }
    var members by rememberSaveable(group, stateSaver = listSaver(save = { ids: Set<String> -> ids.toList() }, restore = { ids -> ids.toSet() })) {
        mutableStateOf(if (group == null) emptySet() else channels.filter { channel -> group in channel.groups }.mapTo(HashSet(), ChannelFilter::channelId))
    }
    var query by rememberSaveable(group) { mutableStateOf("") }
    val cleaned = groupName(name)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val hide = { scope.launch { sheetState.hide() }.invokeOnCompletion { onClose() } }
    CoversPlayer(viewModel)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Text(
            stringResource(if (group == null) R.string.new_group else R.string.edit_group),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 24.dp),
        )
        Column(Modifier.weight(1f).padding(start = 24.dp, end = 24.dp, top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(
                value = name,
                onValueChange = { text -> name = text },
                label = { Text(stringResource(R.string.group_name)) },
                singleLine = true,
                // Done only puts the keyboard away: "Save" is the one thing that saves
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
                colors = brandTextFieldColors(),
                modifier = Modifier.fillMaxWidth(),
            )
            SectionLabel(stringResource(R.string.channels))
            SearchField(query, { text -> query = text }, Modifier.fillMaxWidth())
            val shown = channels.filter { channel -> matchesSearch(channel.title, query) }
            LazyColumn(Modifier.weight(1f)) {
                items(shown, key = ChannelFilter::channelId) { channel ->
                    ChannelRow(
                        channel = channel,
                        summary = filterSummary(context, channel),
                        onOpen = null,
                        onToggle = { member -> members = if (member) members + channel.channelId else members - channel.channelId },
                        edgePadding = false,
                        checked = channel.channelId in members,
                        switchLabel = channel.title,
                    )
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 12.dp, bottom = 16.dp).navigationBarsPadding().imePadding(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (group != null && group in viewModel.groups) {
                OutlinedButton(
                    onClick = {
                        viewModel.deleteGroup(group)
                        hide()
                    },
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) {
                    Text(stringResource(R.string.delete_group))
                }
            }
            Spacer(Modifier.weight(1f))
            AccentTextButton(stringResource(R.string.cancel), onClick = { hide() })
            Button(
                onClick = {
                    if (cleaned != null) {
                        viewModel.saveGroup(group, cleaned, members)
                        hide()
                    }
                },
                enabled = cleaned != null && members.isNotEmpty(),
            ) {
                Text(stringResource(R.string.save))
            }
        }
    }
}

/** Which group editor a screen has open: none, a new group's, or an existing group's. */
internal class GroupEditorState {
    private var open by mutableStateOf(false)
    private var group by mutableStateOf<String?>(null)

    /** Open the editor for a new group. */
    fun openNew() {
        group = null
        open = true
    }

    /** Open the editor for [name]. */
    fun openFor(name: String) {
        group = name
        open = true
    }

    /** The editor, while it is open. */
    @Composable
    fun Sheet(viewModel: SubtubeViewModel) {
        if (open) {
            GroupEditor(viewModel, group) { open = false }
        }
    }
}
