/// The most code points a group's name has.
public let groupNameMax = 24

// Unicode's White_Space code points, spelled out so every client trims alike
private let groupNameSpace: Set<UInt32> = Set(
  [0x0020, 0x0085, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
    + Array(0x0009...0x000D) + Array(0x2000...0x200A))

/// A name's code points: two names are one group only when these are equal,
/// where `==` on the strings would also accept an equivalent spelling.
public func codePoints(_ name: String) -> [UInt32] {
  name.unicodeScalars.map(\.value)
}

private func has(_ names: [String], _ name: String) -> Bool {
  names.contains { sameScalars($0, name) }
}

private func sameNames(_ left: [String], _ right: [String]) -> Bool {
  left.map(codePoints) == right.map(codePoints)
}

private func once(_ names: [String]) -> [String] {
  var seen = Set<[UInt32]>()
  return names.filter { seen.insert(codePoints($0)).inserted }
}

/// Typed text as a group's name (shared/fixtures/groups.json): white space
/// at either end removed; nil unless 1 to ``groupNameMax`` code points are
/// left.
public func groupName(_ text: String) -> String? {
  let scalars = Array(text.unicodeScalars)
  let isSpace = { (scalar: Unicode.Scalar) in groupNameSpace.contains(scalar.value) }
  if let first = scalars.firstIndex(where: { !isSpace($0) }),
    let last = scalars.lastIndex(where: { !isSpace($0) }), last - first < groupNameMax
  {
    var name = String.UnicodeScalarView()
    name.append(contentsOf: scalars[first...last])
    return String(name)
  } else {
    return nil
  }
}


private func isName(_ text: String) -> Bool {
  groupName(text).map { sameScalars($0, text) } ?? false
}

/// The groups a saved filter puts its channel in, each once, in the order
/// written: the strings of `groups` that are a name as they stand. A `groups`
/// that is not an array, or holds anything but strings, is none.
public func filterGroups(_ filter: JSONObject) -> [String] {
  if case .array(let listed) = filter["groups"] {
    let texts = listed.compactMap(\.stringValue)
    return texts.count == listed.count ? once(texts.filter(isName)) : []
  } else {
    return []
  }
}

/// Whether one group's chip goes before another's: ignoring case, then by
/// code point.
public func groupNamePrecedes(_ left: String, _ right: String) -> Bool {
  let foldedLeft = foldCase(left)
  let foldedRight = foldCase(right)
  if foldedLeft.elementsEqual(foldedRight) {
    return precedesByScalar(left, right)
  } else {
    return foldedLeft.lexicographicallyPrecedes(foldedRight)
  }
}

/// The groups that exist, in chip order: every name one of the listed
/// channels' groups has.
public func groupNames(_ channelGroups: some Sequence<[String]>) -> [String] {
  once(channelGroups.flatMap { $0 }).sorted(by: groupNamePrecedes)
}

/// The selected names that are existing groups, in chip order.
public func selectedGroups(_ existing: [String], selected: [String]) -> [String] {
  existing.filter { has(selected, $0) }
}

/// What stands in a chip row's title while it has groups or topics selected.
public struct ChipTitle: Sendable, Hashable {
  /// The selected groups' names, then the selected topics' labels; empty for
  /// the usual title.
  public var names: [String]
  /// The group the title's "Edit group" button opens: the only selected one.
  public var edit: String?

  /// A title showing `names`, with `edit` to open.
  public init(names: [String] = [], edit: String? = nil) {
    self.names = names
    self.edit = edit
  }

  /// The names joined as the title shows them.
  public var text: String {
    names.joined(separator: ", ")
  }
}

/// A chip row's title: its selected existing groups, then its selected
/// topics, each in chip order. `groups` and `topics` are the row's group and
/// topic chips in order, `groupChips` and `topicChips` its two settings.
public func chipTitle(
  groups: [String], groupChips: [String], topics: [String], topicChips: [String]
) -> ChipTitle {
  let selected = selectedGroups(groups, selected: groupChips)
  return ChipTitle(
    names: selected + topics.filter(topicChips.contains).compactMap { topicLabel($0) },
    edit: selected.count == 1 ? selected.first : nil)
}

/// The channels the selected groups keep, by id: those in any selected
/// existing group. Nil when none is selected, which keeps every channel.
/// `channelGroups` is every listed channel's groups by its id.
public func groupKeptChannels(_ channelGroups: [String: [String]], selected: [String])
  -> Set<String>?
{
  let wanted = selectedGroups(groupNames(channelGroups.values), selected: selected)
  if wanted.isEmpty {
    return nil
  } else {
    return Set(
      channelGroups.filter { _, groups in groups.contains { has(wanted, $0) } }.keys)
  }
}

/// The ids two sets of kept channels both keep; nil, which keeps all, when
/// both are.
public func keptByBoth(_ left: Set<String>?, _ right: Set<String>?) -> Set<String>? {
  if let left, let right {
    return left.intersection(right)
  } else {
    return left ?? right
  }
}

/// The items of the channels in `kept`, in the order given; all of them when
/// it is nil.
public func groupFiltered(_ items: [FeedItem], kept: Set<String>?) -> [FeedItem] {
  if let kept {
    return items.filter { kept.contains($0.channelId) }
  } else {
    return items
  }
}

/// The selected group chips of both rows, as the settings hold them.
public struct GroupSelections: Sendable, Hashable {
  /// The feed's row.
  public var groupChips: [String]
  /// The channel list's row.
  public var channelGroupChips: [String]

  /// Both rows' selections.
  public init(groupChips: [String], channelGroupChips: [String]) {
    self.groupChips = groupChips
    self.channelGroupChips = channelGroupChips
  }
}

/// What a group edit saves.
public struct GroupEdit: Sendable, Hashable {
  /// Each changed channel's whole filter, by channel id.
  public var channels: [String: JSONObject] = [:]
  /// The feed row's selection, when it changes.
  public var groupChips: [String]?
  /// The channel list row's selection, when it changes.
  public var channelGroupChips: [String]?

  /// An edit that changes nothing.
  public init() {}

  /// Whether nothing is to be saved.
  public var isEmpty: Bool {
    channels.isEmpty && groupChips == nil && channelGroupChips == nil
  }
}

/// The listed channels a group edit changes, by id, each with its edited
/// filter and the identity it had.
public func groupEdited(_ channels: [ChannelFilter], by edit: GroupEdit) -> [String: ChannelFilter] {
  Dictionary(
    channels.compactMap { channel in
      edit.channels[channel.channelId].map { stored in
        (
          channel.channelId,
          ChannelFilter(
            channelId: channel.channelId, title: channel.title, thumbnail: channel.thumbnail,
            stored: stored)
        )
      }
    }) { first, _ in first }
}

private func withGroups(_ filter: JSONObject, _ groups: [String]) -> JSONObject {
  var edited = filter
  edited["groups"] = .array(groups.map(JSONValue.string))
  return edited
}

private let defaultStoredFilter: JSONObject = [
  "enabled": .bool(true), "regex": .string(""), "mode": .string(FilterMode.include.rawValue),
]

/// Every saved filter `change` gives other groups, with the groups it gives.
private func regrouped(_ saved: [String: JSONObject], _ change: ([String]) -> [String])
  -> [String: JSONObject]
{
  var changed: [String: JSONObject] = [:]
  for (channelId, filter) in saved {
    let groups = filterGroups(filter)
    let next = change(groups)
    if !sameNames(groups, next) {
      changed[channelId] = withGroups(filter, next)
    }
  }
  return changed
}

private func reselected(
  _ edit: inout GroupEdit, _ selections: GroupSelections, _ change: ([String]) -> [String]
) {
  let feedRow = change(selections.groupChips)
  if !sameNames(selections.groupChips, feedRow) {
    edit.groupChips = feedRow
  }
  let channelRow = change(selections.channelGroupChips)
  if !sameNames(selections.channelGroupChips, channelRow) {
    edit.channelGroupChips = channelRow
  }
}

/// Delete a group: its name leaves every saved filter that has it and both
/// settings. `saved` is every saved filter by channel id, listed or not.
public func deleteGroup(
  _ saved: [String: JSONObject], selections: GroupSelections, group: String
) -> GroupEdit {
  let without = { (names: [String]) in names.filter { !sameScalars($0, group) } }
  var edit = GroupEdit()
  edit.channels = regrouped(saved, without)
  reselected(&edit, selections, without)
  return edit
}

/// Rename a group on every saved filter that has it and in both settings; a
/// filter or setting that already has the new name keeps it once, where it
/// came first. Nothing changes unless `to` is a name other than `from`.
public func renameGroup(
  _ saved: [String: JSONObject], selections: GroupSelections, from: String, to: String
) -> GroupEdit {
  var edit = GroupEdit()
  if isName(to) && !sameScalars(from, to) {
    let renamed = { (names: [String]) -> [String] in
      if has(names, from) {
        let moved = names.map { sameScalars($0, from) ? to : $0 }
        let first = moved.firstIndex { sameScalars($0, to) }
        return moved.enumerated().filter { index, name in
          !sameScalars(name, to) || index == first
        }.map(\.element)
      } else {
        return names
      }
    }
    edit.channels = regrouped(saved, renamed)
    reselected(&edit, selections, renamed)
  }
  return edit
}

/// Put channels in a group, or take them out. A channel with no saved filter
/// gets the default one; a new name goes last in the filter's `groups`.
/// Taking out the last of the `listed` channels in the group deletes it
/// (``deleteGroup(_:selections:group:)``).
public func setMembers(
  _ saved: [String: JSONObject], listed: [String], selections: GroupSelections,
  channelIds: [String], group: String, member: Bool
) -> GroupEdit {
  var edit = GroupEdit()
  if isName(group) {
    for channelId in channelIds {
      let filter = saved[channelId] ?? defaultStoredFilter
      let groups = filterGroups(filter)
      if has(groups, group) != member {
        edit.channels[channelId] = withGroups(
          filter, member ? groups + [group] : groups.filter { !sameScalars($0, group) })
      }
    }
    let after = saved.merging(edit.channels) { _, changed in changed }
    let isLeft = listed.contains { channelId in
      after[channelId].map { has(filterGroups($0), group) } ?? false
    }
    if !member && !isLeft {
      let deleted = deleteGroup(after, selections: selections, group: group)
      edit.channels.merge(deleted.channels) { _, changed in changed }
      edit.groupChips = deleted.groupChips
      edit.channelGroupChips = deleted.channelGroupChips
    }
  }
  return edit
}

/// What the group editor's "Save" writes, as one edit: the listed channels in
/// the group become exactly `members`, then the group takes `name`
/// (``renameGroup(_:selections:from:to:)``, which merges into a group that
/// has it already). `group` is the edited group, or nil for a new one, whose
/// members are put in `name`. Nothing changes unless `name` is a name and
/// `members` has a channel.
public func saveGroup(
  _ saved: [String: JSONObject], listed: [String], selections: GroupSelections,
  group: String?, name: String, members: [String]
) -> GroupEdit {
  if !isName(name) || members.isEmpty {
    return GroupEdit()
  } else if let group {
    let added = setMembers(
      saved, listed: listed, selections: selections, channelIds: members, group: group,
      member: true)
    let withAdded = saved.merging(added.channels) { _, changed in changed }
    let removed = setMembers(
      withAdded, listed: listed, selections: selections,
      channelIds: listed.filter { !members.contains($0) }, group: group, member: false)
    var edit = renameGroup(
      withAdded.merging(removed.channels) { _, changed in changed }, selections: selections,
      from: group, to: name)
    edit.channels = added.channels
      .merging(removed.channels) { _, changed in changed }
      .merging(edit.channels) { _, changed in changed }
    return edit
  } else {
    return setMembers(
      saved, listed: listed, selections: selections, channelIds: members, group: name,
      member: true)
  }
}
