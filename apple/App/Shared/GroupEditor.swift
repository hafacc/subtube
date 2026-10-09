import SubtubeCore
import SwiftUI

/// What the group editor is open for.
enum GroupTarget: Hashable, Identifiable {
  /// A group not yet made.
  case new
  /// The group of this name.
  case existing(String)

  var id: Self { self }

  /// The edited group's name; nil for a new one.
  var group: String? {
    switch self {
    case .new: nil
    case .existing(let name): name
    }
  }
}

/// Names a group and chooses its channels.
///
/// It edits a draft: nothing is saved until "Save", which needs a name of
/// at most 24 characters and one channel switched on, and "Cancel" drops it.
/// A longer name is kept as typed, with "Save" off. "Delete Group", for a
/// group that exists, deletes at once. The name and the buttons stay in
/// place and only the channel rows scroll. On iOS it is a sheet's content,
/// with "Cancel" and "Save" in its bar and the Channels tab's search field
/// over the rows; on macOS it fills the details panel, with the buttons in
/// one row at the bottom, on the panel's background and at its inset, as
/// the filters are. See ``FeedModel/saveGroup(_:name:members:)``.
struct GroupEditor: View {
  let feed: FeedModel
  let target: GroupTarget
  /// Called after "Save", "Cancel" and "Delete Group".
  let onClose: () -> Void
  @State private var name: String
  /// The channels switched on.
  @State private var members: Set<String>
  @State private var search = ""

  init(feed: FeedModel, target: GroupTarget, onClose: @escaping () -> Void) {
    self.feed = feed
    self.target = target
    self.onClose = onClose
    _name = State(initialValue: target.group ?? "")
    _members = State(initialValue: target.group.map(feed.members(of:)) ?? [])
  }

  private var exists: Bool {
    target.group.map { group in feed.groups.contains { sameScalars($0, group) } } ?? false
  }

  private var canSave: Bool {
    groupName(name) != nil && !members.isEmpty
  }

  private var title: String {
    target.group == nil ? Strings.newGroup : Strings.editGroup
  }

  private var rows: [ChannelFilter] {
    channelsByName(channelsMatching(feed.channels, search: search))
  }

  private func isMember(_ channel: ChannelFilter) -> Binding<Bool> {
    Binding(
      get: { members.contains(channel.channelId) },
      set: { isOn in
        if isOn {
          members.insert(channel.channelId)
        } else {
          members.remove(channel.channelId)
        }
      })
  }

  private func save() {
    if let saved = groupName(name), !members.isEmpty {
      feed.saveGroup(target.group, name: saved, members: Array(members))
      onClose()
    }
  }

  private func delete() {
    if let group = target.group {
      feed.deleteGroup(group)
    }
    onClose()
  }

  private var nameField: some View {
    TextField(Strings.name, text: $name)
  }

  private func memberSwitch(_ channel: ChannelFilter) -> some View {
    Toggle(channel.title, isOn: isMember(channel))
      .labelsHidden()
      .toggleStyle(.switch)
      .tint(Color.sunflower)
  }

  #if os(macOS)
    @FocusState private var nameFocused: Bool

    private var memberRows: some View {
      LazyVStack(spacing: 0) {
        ForEach(rows, id: \.channelId) { channel in
          HStack(spacing: 8) {
            HStack(spacing: 8) {
              Avatar(url: channel.thumbnail, title: channel.title, size: 24)
              Text(channel.title).lineLimit(1)
            }
            .opacity(channel.enabled ? 1 : offChannelOpacity)
            Spacer()
            memberSwitch(channel).controlSize(.small)
          }
          .padding(.vertical, 6)
          .padding(.horizontal, 10)
          if channel.channelId != rows.last?.channelId {
            Divider().padding(.horizontal, 10)
          }
        }
      }
      .background(Color.secondary.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.title3.bold())
        nameField
          .textFieldStyle(.plain)
          .focused($nameFocused)
          .fieldBox(focused: nameFocused)
          .padding(.top, 12)
        Text(Strings.channels)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.secondary)
          .padding(.top, 16)
          .padding(.bottom, 6)
        ScrollView {
          memberRows
        }
        .frame(maxHeight: .infinity)
        HStack {
          if exists {
            Button(Strings.deleteGroup, role: .destructive, action: delete)
              .buttonStyle(.borderless)
              .foregroundStyle(.red)
          }
          Spacer()
          Button(Strings.cancel, action: onClose)
            .controlSize(.large)
          Button(Strings.save, action: save)
            .buttonStyle(.prominent)
            .disabled(!canSave)
        }
        .padding(.top, 12)
      }
      .padding(.horizontal, panelInset)
      .padding(.top, 14)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(title)
    }
  #else
    var body: some View {
      NavigationStack {
        VStack(alignment: .leading, spacing: 0) {
          nameField
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(
              Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 16)
            .padding(.top, 8)
          Text(Strings.channels)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 8)
          ChannelSearchField(text: $search)
            .padding(.horizontal, 16)
          List {
            ForEach(rows, id: \.channelId) { channel in
              HStack(spacing: 12) {
                ChannelRowLabel(channel: channel, feed: feed)
                memberSwitch(channel)
              }
            }
          }
          .listStyle(.insetGrouped)
          .contentMargins(.top, 12, for: .scrollContent)
          .scrollDismissesKeyboard(.interactively)
          if exists {
            Button(Strings.deleteGroup, role: .destructive, action: delete)
              .frame(maxWidth: .infinity, minHeight: 52)
              .background(
                Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26)
              )
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
          }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(Strings.cancel, action: onClose)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(Strings.save, action: save).disabled(!canSave)
          }
        }
      }
    }
  #endif
}

/// The pencil and × that follow a chip row's title while it shows selected
/// names: "Edit group" for the one selected group, and "Clear".
struct ChipTitleButtons: View {
  let title: ChipTitle
  /// Opens the editor for the one selected group.
  let onEdit: (String) -> Void
  let onClear: () -> Void

  var body: some View {
    if let group = title.edit {
      Button {
        onEdit(group)
      } label: {
        Label(Strings.editGroup, systemImage: "pencil")
      }
      .help(Strings.editGroup)
    }
    if !title.names.isEmpty {
      Button(action: onClear) {
        Label(Strings.clear, systemImage: "xmark")
      }
      .help(Strings.clear)
    }
  }
}
