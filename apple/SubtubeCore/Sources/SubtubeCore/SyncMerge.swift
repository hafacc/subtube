import Foundation

/// A saved channel filter with when it was saved.
public struct ChannelEntry: Sendable, Hashable {
  /// Milliseconds since the epoch.
  public var at: Int64
  /// The filter object, as stored (see ``ChannelFilter/stored``).
  public var filter: JSONObject
  /// The entry's other fields, kept as read.
  public var extra: JSONObject = [:]

  /// A filter saved at `at`.
  public init(at: Int64, filter: JSONObject, extra: JSONObject = [:]) {
    self.at = at
    self.filter = filter
    self.extra = extra
  }

  var json: JSONValue {
    var object = extra
    object["at"] = .integer(at)
    object["filter"] = .object(filter)
    return .object(object)
  }
}

/// A watched mark with when it was made.
public struct WatchedEntry: Sendable, Hashable {
  /// Milliseconds since the epoch.
  public var at: Int64
  /// False is an explicit unmark.
  public var watched: Bool
  /// The entry's other fields, kept as read.
  public var extra: JSONObject = [:]

  /// A mark made at `at`.
  public init(at: Int64, watched: Bool, extra: JSONObject = [:]) {
    self.at = at
    self.watched = watched
    self.extra = extra
  }

  /// When this device last had the item among a full load's items, in
  /// milliseconds since the epoch; nil when the entry has none or holds
  /// anything but a whole number from 0 to ``maxEntryTime``.
  public var seen: Int64? {
    extra["seen"]?.integerValue.flatMap { (0...maxEntryTime).contains($0) ? $0 : nil }
  }

  /// When the entry was last saved or last among a load's items, whichever
  /// is later.
  var lastUsed: Int64 {
    max(at, seen ?? at)
  }

  var json: JSONValue {
    var object = extra
    object["at"] = .integer(at)
    object["watched"] = .bool(watched)
    return .object(object)
  }
}

/// A synced setting as a device last saved it, with when it was saved; what a
/// value means is read by ``SyncedSettings``.
public struct SettingEntry: Sendable, Hashable {
  /// Milliseconds since the epoch.
  public var at: Int64
  /// The saved value, kept whatever it is.
  public var value: JSONValue
  /// The entry's other fields, kept as read.
  public var extra: JSONObject = [:]

  /// A value saved at `at`.
  public init(at: Int64, value: JSONValue, extra: JSONObject = [:]) {
    self.at = at
    self.value = value
    self.extra = extra
  }

  var json: JSONValue {
    var object = extra
    object["at"] = .integer(at)
    object["value"] = value
    return .object(object)
  }
}

/// One device's edits, as kept in its own `device-<id>.json` in the Drive
/// app folder (shared/schema/device-file.schema.json, version 1).
public struct DeviceFile: Sendable, Hashable {
  /// The last filter saved for each channel id.
  public var channels: [String: ChannelEntry] = [:]
  /// The last watched mark for each video or playlist id.
  public var watched: [String: WatchedEntry] = [:]
  /// The last value saved for each synced setting, by name; nil for a file
  /// without the section, which is then written back without it.
  public var settings: [String: SettingEntry]?
  /// Top-level fields this version doesn't know, written back unchanged.
  public var extra: JSONObject = [:]

  /// A file holding these sections.
  public init(
    channels: [String: ChannelEntry] = [:], watched: [String: WatchedEntry] = [:],
    settings: [String: SettingEntry]? = nil, extra: JSONObject = [:]
  ) {
    self.channels = channels
    self.watched = watched
    self.settings = settings
    self.extra = extra
  }

  /// The file as JSON, `version` 1 and unknown fields included.
  public var json: JSONValue {
    var object = extra
    object["version"] = .integer(1)
    object["channels"] = .object(channels.mapValues(\.json))
    object["watched"] = .object(watched.mapValues(\.json))
    if let settings {
      object["settings"] = .object(settings.mapValues(\.json))
    }
    return .object(object)
  }
}

/// The only format version this client reads and writes.
public let deviceFileVersion: Int64 = 1
/// A watched entry neither saved nor loaded for this long is dropped when its device next saves.
public let watchedRetentionMilliseconds: Int64 = 30 * 24 * 60 * 60 * 1000
/// How old an entry's `seen` gets before a load writes a new one.
public let seenRefreshMilliseconds: Int64 = 24 * 60 * 60 * 1000
/// The largest `at` a file may carry (2^53 - 1).
public let maxEntryTime: Int64 = 9_007_199_254_740_991

/// Milliseconds since the epoch, the unit of every `at`.
public func epochMilliseconds(_ date: Date = Date()) -> Int64 {
  Int64((date.timeIntervalSince1970 * 1000).rounded())
}

/// The device id in a Drive file name, or nil when it isn't a device file.
public func deviceIdFromFileName(_ name: String) -> String? {
  name.wholeMatch(of: #/device-([A-Za-z0-9_-]+)\.json/#).map { String($0.output.1) }
}

/// Whether an app folder with these file names already holds a profile, so
/// the first run can be skipped: any device's file counts.
public func hasSyncedProfile(_ fileNames: [String]) -> Bool {
  fileNames.contains { deviceIdFromFileName($0) != nil }
}

/// Whether another device has set the account up: a device file other than
/// this device's own, which a setup left unfinished here may have written.
public func setUpElsewhere(_ fileNames: [String], ownName: String) -> Bool {
  hasSyncedProfile(fileNames.filter { $0 != ownName })
}

/// Whether the profile was deleted from another device: this device
/// uploaded its file before, and a listing of the app folder no longer has it.
public func profileDeletedElsewhere(uploadedBefore: Bool, fileNames: [String], ownName: String)
  -> Bool
{
  uploadedBefore && !fileNames.contains(ownName)
}

private func entryTime(_ object: JSONObject) -> Int64? {
  object["at"]?.integerValue.flatMap { (0...maxEntryTime).contains($0) ? $0 : nil }
}

/// Read a device file. Nil when it should be skipped: not JSON, not an
/// object, or a `version` other than 1. Malformed sections read as empty and
/// malformed entries are dropped; everything else is kept, unknown fields too.
public func parseDeviceFile(_ value: JSONValue) -> DeviceFile? {
  if let object = value.objectValue, object["version"]?.integerValue == deviceFileVersion {
    return readDeviceFile(object)
  } else {
    return nil
  }
}

private func readDeviceFile(_ object: JSONObject) -> DeviceFile {
  var file = DeviceFile()
  file.extra = object.filter { !["version", "channels", "watched", "settings"].contains($0.key) }
  for (key, raw) in object["channels"]?.objectValue ?? [:] {
    guard var entry = raw.objectValue, let at = entryTime(entry),
      let filter = entry["filter"]?.objectValue
    else { continue }
    entry["at"] = nil
    entry["filter"] = nil
    file.channels[key] = ChannelEntry(at: at, filter: filter, extra: entry)
  }
  for (key, raw) in object["watched"]?.objectValue ?? [:] {
    guard var entry = raw.objectValue, let at = entryTime(entry),
      let watched = entry["watched"]?.boolValue
    else { continue }
    entry["at"] = nil
    entry["watched"] = nil
    file.watched[key] = WatchedEntry(at: at, watched: watched, extra: entry)
  }
  if let section = object["settings"] {
    var settings: [String: SettingEntry] = [:]
    for (key, raw) in section.objectValue ?? [:] {
      guard var entry = raw.objectValue, let at = entryTime(entry), let value = entry["value"]
      else { continue }
      entry["at"] = nil
      entry["value"] = nil
      settings[key] = SettingEntry(at: at, value: value, extra: entry)
    }
    file.settings = settings
  }
  return file
}

/// Read a downloaded device file; nil when it should be skipped.
public func parseDeviceFile(_ data: Data) -> DeviceFile? {
  JSONValue.parse(data).flatMap(parseDeviceFile)
}

/// Encode a device file for upload or local storage.
public func encodeDeviceFile(_ file: DeviceFile) throws -> Data {
  try file.json.encoded()
}

/// One device's file and the id it was written under.
public struct DeviceFileSource: Sendable {
  /// The id in the file's name.
  public var deviceId: String
  /// What the file holds.
  public var file: DeviceFile

  /// A device's file.
  public init(deviceId: String, file: DeviceFile) {
    self.deviceId = deviceId
    self.file = file
  }
}

private func isGreaterId(_ left: String, _ right: String) -> Bool {
  right.utf8.lexicographicallyPrecedes(left.utf8)
}

private func newest<Entry>(
  _ sources: [DeviceFileSource], _ section: (DeviceFile) -> [String: Entry], at: (Entry) -> Int64
) -> [String: Entry] {
  var merged: [String: (deviceId: String, entry: Entry)] = [:]
  for source in sources {
    for (key, entry) in section(source.file) {
      if let prior = merged[key] {
        let newer = at(entry) > at(prior.entry)
        let tieWins = at(entry) == at(prior.entry) && isGreaterId(source.deviceId, prior.deviceId)
        guard newer || tieWins else { continue }
      }
      merged[key] = (source.deviceId, entry)
    }
  }
  return merged.mapValues(\.entry)
}

/// Every device's edits, the entry with the greatest `at` per key, the
/// greater device id on a tie. Winning entries are kept whole; unknown
/// top-level fields don't reach the merged view, which always has `settings`.
public func mergeDeviceFiles(_ sources: [DeviceFileSource]) -> DeviceFile {
  DeviceFile(
    channels: newest(sources, \.channels, at: \.at),
    watched: newest(sources, \.watched, at: \.at),
    settings: newest(sources, { $0.settings ?? [:] }, at: \.at)
  )
}

/// A device's own file after a full load whose items were `loaded`
/// (shared/fixtures/prune.json): each of its entries among them gets `seen`
/// set to `now`, unless its `seen` is younger than
/// ``seenRefreshMilliseconds``. `at` is never changed.
public func refreshSeen(_ file: DeviceFile, loaded: Set<String>, now: Int64) -> DeviceFile {
  var refreshed = file
  for (id, entry) in file.watched where loaded.contains(id) {
    if let seen = entry.seen, now - seen < seenRefreshMilliseconds {
      continue
    }
    refreshed.watched[id]?.extra["seen"] = .integer(now)
  }
  return refreshed
}

/// A device's own file without the watched entries neither saved nor seen in
/// a load within ``watchedRetentionMilliseconds``.
public func pruneDeviceFile(_ file: DeviceFile, now: Int64) -> DeviceFile {
  var pruned = file
  pruned.watched = file.watched.filter { now - $0.value.lastUsed < watchedRetentionMilliseconds }
  return pruned
}

/// The name and avatar of a channel, which YouTube owns.
public struct ChannelIdentity: Codable, Sendable, Hashable {
  /// The channel's name.
  public var title: String
  /// The channel's avatar URL, or empty.
  public var thumbnail: String
  /// When YouTube was asked; nil for one cached before this was kept.
  public var fetchedAt: Date?

  /// A name and avatar as YouTube gave them at `fetchedAt`.
  public init(title: String, thumbnail: String, fetchedAt: Date? = nil) {
    self.title = title
    self.thumbnail = thumbnail
    self.fetchedAt = fetchedAt
  }
}

/// How long a followed channel's cached name and avatar are trusted.
public let identityLifetime: TimeInterval = 24 * 60 * 60

/// The channels the feed reads, in subscription order: every YouTube
/// subscription with its saved filter (or the default), then the channels
/// followed in subtube, by title. Names and avatars come from YouTube: the
/// subscription, or `identities` for followed channels (the id until known).
/// A filter saved for a channel since unsubscribed is kept but not listed, so
/// subscribing again restores it.
public func channelsFor(
  _ merged: DeviceFile, subscriptions: [Subscription],
  identities: [String: ChannelIdentity] = [:]
) -> [ChannelFilter] {
  var channels: [ChannelFilter] = []
  var seen = Set<String>()
  for subscription in subscriptions where !seen.contains(subscription.channelId) {
    seen.insert(subscription.channelId)
    channels.append(
      ChannelFilter(
        channelId: subscription.channelId, title: subscription.title,
        thumbnail: subscription.thumbnail,
        stored: merged.channels[subscription.channelId]?.filter ?? [:]))
  }
  let followed = merged.channels
    .filter { !seen.contains($0.key) }
    .map { channelId, entry in
      let identity = identities[channelId]
      return ChannelFilter(
        channelId: channelId, title: identity?.title ?? channelId,
        thumbnail: identity?.thumbnail ?? "", stored: entry.filter)
    }
    .filter(\.followed)
    .sorted { left, right in
      if sameScalars(left.title, right.title) {
        return precedesByScalar(left.channelId, right.channelId)
      } else {
        return precedesIgnoringCase(left.title, right.title)
      }
    }
  channels.append(contentsOf: followed)
  return channels
}

/// The followed channels whose name and avatar aren't known, or were asked
/// more than a day before `now`.
public func followedWithoutIdentity(
  _ merged: DeviceFile, subscriptions: [Subscription], identities: [String: ChannelIdentity],
  now: Date = Date()
) -> [String] {
  let subscribed = Set(subscriptions.map(\.channelId))
  return channelsFor(merged, subscriptions: subscriptions)
    .filter { channel in
      if subscribed.contains(channel.channelId) {
        return false
      } else if let fetchedAt = identities[channel.channelId]?.fetchedAt {
        return now.timeIntervalSince(fetchedAt) > identityLifetime
      } else {
        return true
      }
    }
    .map(\.channelId)
}

/// Whether this device's file must go up: Drive has no copy of it and there
/// is something to keep, or Drive's copy differs from the local one.
public func needsUpload(local: DeviceFile, remote: DeviceFile?) -> Bool {
  if let remote {
    // a section that is missing and one that is empty hold the same settings
    return local.channels != remote.channels || local.watched != remote.watched
      || (local.settings ?? [:]) != (remote.settings ?? [:]) || local.extra != remote.extra
  } else {
    return !local.channels.isEmpty || !local.watched.isEmpty
      || !(local.settings ?? [:]).isEmpty
  }
}

/// The channels a finished load shows: the store's, with each filter edited
/// while the load ran kept as edited.
public func keepingEdits(_ channels: [ChannelFilter], edits: [String: ChannelFilter])
  -> [ChannelFilter]
{
  channels.map { edits[$0.channelId] ?? $0 }
}
