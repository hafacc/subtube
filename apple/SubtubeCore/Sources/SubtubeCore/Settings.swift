/// The names of the settings synced through the device files.
public enum SettingName: String, Sendable, CaseIterable {
  /// The feed's order.
  case feedSort
  /// The channel lists' order.
  case channelSort
  /// Whether the next unwatched item plays when one ends.
  case autoplay
  /// The feed's time chip.
  case timeChip
  /// The feed's selected topic chips.
  case topicChips
  /// The channel lists' time chip.
  case channelTimeChip
  /// The channel lists' selected topic chips.
  case channelTopicChips
  /// The feed's selected group chips.
  case groupChips
  /// The channel lists' selected group chips.
  case channelGroupChips
}

/// The synced settings as this version reads them out of the merged
/// `settings` map (shared/fixtures/settings.json). A setting that is missing,
/// or holds a value this version doesn't know, reads as its default.
public struct SyncedSettings: Sendable, Hashable {
  /// The feed's order.
  public var feedSort = FeedSort.newest
  /// The channel lists' order.
  public var channelSort = ChannelSort.newest
  /// Whether the next unwatched item plays when one ends.
  public var autoplay = false
  /// The selected time chip.
  public var timeChip = TimeChip.anyTime
  /// The selected topic chips' category ids, as written.
  public var topicChips: [String] = []
  /// The channel list's selected time chip.
  public var channelTimeChip = TimeChip.anyTime
  /// The channel list's selected topic chips' category ids, as written.
  public var channelTopicChips: [String] = []
  /// The feed row's selected group chips' names, as written.
  public var groupChips: [String] = []
  /// The channel list row's selected group chips' names, as written.
  public var channelGroupChips: [String] = []

  /// Every setting at its default.
  public init() {}

  /// The settings in a merged view's `settings` map.
  public init(_ entries: [String: SettingEntry]) {
    func value(_ name: SettingName) -> JSONValue? {
      entries[name.rawValue]?.value
    }
    func choice<Value: RawRepresentable>(_ name: SettingName, _ fallback: Value) -> Value
    where Value.RawValue == String {
      value(name)?.stringValue.flatMap(Value.init(rawValue:)) ?? fallback
    }
    feedSort = choice(.feedSort, FeedSort.newest)
    channelSort = choice(.channelSort, ChannelSort.newest)
    autoplay = value(.autoplay)?.boolValue ?? false
    timeChip = choice(.timeChip, TimeChip.anyTime)
    func texts(_ name: SettingName) -> [String] {
      if case .array(let values) = value(name) {
        let texts = values.compactMap(\.stringValue)
        return texts.count == values.count ? texts : []
      } else {
        return []
      }
    }
    topicChips = texts(.topicChips)
    channelTimeChip = choice(.channelTimeChip, TimeChip.anyTime)
    channelTopicChips = texts(.channelTopicChips)
    groupChips = texts(.groupChips)
    channelGroupChips = texts(.channelGroupChips)
  }
}

/// A setting's entry after a change at `now`: the new value, with the
/// unknown fields the entry had in this device's own file.
public func editedSetting(_ prior: SettingEntry?, value: JSONValue, now: Int64) -> SettingEntry {
  SettingEntry(at: now, value: value, extra: prior?.extra ?? [:])
}
