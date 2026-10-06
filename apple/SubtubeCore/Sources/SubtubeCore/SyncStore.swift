import Foundation

/// Hands out a valid Google access token, renewing it when needed.
public protocol AccessTokenSource: Sendable {
  /// A token that is valid now.
  func validToken() async throws -> String
  /// A newly minted token, for when the current one was refused.
  func refreshedToken() async throws -> String
}

/// The id this install writes its Drive file under, kept for the life of the
/// install.
public func deviceId(defaults: UserDefaults = .standard) -> String {
  let key = "subtube.device"
  if let existing = defaults.string(forKey: key), deviceIdFromFileName("device-\(existing).json") != nil {
    return existing
  } else {
    let created = UUID().uuidString.lowercased()
    defaults.set(created, forKey: key)
    return created
  }
}

/// Why the sync store stopped.
public enum SyncError: Error, Sendable {
  /// The profile was deleted, here or from another device; nothing is kept
  /// or uploaded any more.
  case profileDeleted
  /// This device's Drive file couldn't be read, so it isn't written over.
  case ownFileUnreadable
}

/// The channel filters, watched marks and settings, synced through the Drive
/// app folder. Each device writes only its own file and reads everyone's, so two
/// devices never write the same file. Edits apply in memory at once, are kept
/// on disk until uploaded, and go up after a short pause.
public actor SyncStore {
  /// A burst of edits (marking several cards) goes up as one upload.
  public static let saveDelay: Duration = .seconds(2)

  private let deviceId: String
  private let ownName: String
  private let localURL: URL
  private let identitiesURL: URL
  /// Exists once this device's file has been seen in Drive.
  private let uploadedURL: URL
  private var uploadedBefore: Bool
  /// Whether the profile was deleted; the store is then finished.
  private var deleted = false
  private let tokens: any AccessTokenSource
  private let session: URLSession
  private var own: DeviceFile
  private var ownFileId: String?
  // whether ownFileId is known; saving before then would create a second file
  private var listed = false
  private var others: [String: (modifiedTime: String, source: DeviceFileSource)] = [:]
  private var merged: DeviceFile
  /// Whether `own` holds edits Drive doesn't have.
  private var unsent = false
  /// Whether this device's Drive file was there but couldn't be read.
  private var ownUnreadable = false
  private var pendingSave: Task<Void, Never>?
  /// The newest upload asked for; nil once it has ended.
  private var saving: Task<Void, Error>?
  private var savesStarted = 0
  /// How many uploads have ended; a listing asked for before one ended may lack its file.
  private var savesEnded = 0
  /// Names and avatars of followed channels, which the Drive files don't hold.
  private var identities: [String: ChannelIdentity]
  /// When Drive last answered a read or a write.
  public private(set) var lastSyncedAt: Date?

  /// - Parameters:
  ///   - accountId: the YouTube channel id of the signed-in account.
  ///   - directory: where the not-yet-uploaded edits are kept.
  public init(
    accountId: String,
    tokens: any AccessTokenSource,
    directory: URL,
    deviceId: String,
    session: URLSession = .shared
  ) {
    self.deviceId = deviceId
    ownName = "device-\(deviceId).json"
    localURL = directory.appendingPathComponent("sync-\(accountId).json")
    identitiesURL = directory.appendingPathComponent("channels-\(accountId).json")
    uploadedURL = directory.appendingPathComponent("uploaded-\(accountId)")
    uploadedBefore = FileManager.default.fileExists(atPath: uploadedURL.path)
    self.tokens = tokens
    self.session = session
    let local = (try? Data(contentsOf: localURL)).flatMap(parseDeviceFile) ?? DeviceFile()
    own = local
    merged = local
    identities =
      (try? Data(contentsOf: identitiesURL))
      .flatMap { try? JSONDecoder().decode([String: ChannelIdentity].self, from: $0) } ?? [:]
  }

  private func markUploaded() {
    guard !uploadedBefore else { return }
    uploadedBefore = true
    try? FileManager.default.createDirectory(
      at: uploadedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data().write(to: uploadedURL)
  }

  /// Forget everything kept for the account, in memory and on disk.
  private func wipe() {
    deleted = true
    pendingSave?.cancel()
    pendingSave = nil
    for url in [localURL, identitiesURL, uploadedURL] {
      try? FileManager.default.removeItem(at: url)
    }
    own = DeviceFile()
    merged = DeviceFile()
    others = [:]
    identities = [:]
    ownFileId = nil
    uploadedBefore = false
  }

  /// Delete every file in the Drive app folder, every device's, then
  /// everything kept here. Nothing here changes if Drive fails.
  public func deleteProfile() async throws {
    // unsent edits stay on disk; if Drive fails they go up with the next edit
    pendingSave?.cancel()
    pendingSave = nil
    await waitForSaves()
    do {
      try await withDrive { client in
        for file in try await client.listAppFiles() {
          try await client.delete(file.id)
        }
      }
    } catch {
      // this device's file may be among the ones already gone: the next
      // save lists the folder again and makes a new one
      ownFileId = nil
      listed = false
      uploadedBefore = false
      try? FileManager.default.removeItem(at: uploadedURL)
      throw error
    }
    wipe()
  }

  private func writeLocal() {
    guard !deleted else { return }
    do {
      try FileManager.default.createDirectory(
        at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try encodeDeviceFile(own).write(to: localURL, options: .atomic)
    } catch {
      // the upload still carries it
    }
  }

  private func remerge() {
    merged = mergeDeviceFiles(
      [DeviceFileSource(deviceId: deviceId, file: own)] + others.values.map(\.source))
  }

  /// Run `work` against Drive, renewing the token once if Google refuses it.
  private func withDrive<Result: Sendable>(
    _ work: @Sendable (DriveClient) async throws -> Result
  ) async throws -> Result {
    do {
      return try await work(
        DriveClient(accessToken: try await tokens.validToken(), session: session))
    } catch GoogleAPIError.tokenExpired {
      return try await work(
        DriveClient(accessToken: try await tokens.refreshedToken(), session: session))
    }
  }

  private func waitForSaves() async {
    // each upload clears `saving` itself unless a newer one took its place
    while let running = saving {
      _ = try? await running.value
    }
  }

  /// Whether this device's file, missing from a listing, is really gone from
  /// Drive: asked for by its id, or listed again when the id isn't known.
  /// False while an upload of it runs or has just ended, when no answer can
  /// be trusted.
  private func ownFileIsGone() async throws -> Bool {
    let endedBefore = savesEnded
    let fileId = ownFileId
    let ownName = ownName
    if saving != nil {
      return false
    } else {
      let gone = try await withDrive { client in
        if let fileId {
          return try await !client.exists(fileId)
        } else {
          return try await !client.listAppFiles().contains { $0.name == ownName }
        }
      }
      return gone && saving == nil && savesEnded == endedBefore
    }
  }

  private struct Listing: Sendable {
    var files: [DriveFile]
    var downloads: [(DriveFile, Data)]
  }

  /// Read every device's file, downloading only the ones that changed.
  public func load() async throws {
    guard !deleted else { throw SyncError.profileDeleted }
    let ownName = ownName
    let known = others.mapValues(\.modifiedTime)
    let endedBefore = savesEnded
    let savingBefore = saving != nil
    let read = try await withDrive { client in
      let files = try await client.listAppFiles().filter { deviceIdFromFileName($0.name) != nil }
      let downloads = try await withThrowingTaskGroup(of: (DriveFile, Data).self) { group in
        for entry in files where entry.name == ownName || known[entry.id] != entry.modifiedTime {
          group.addTask { (entry, try await client.download(entry.id)) }
        }
        var results: [(DriveFile, Data)] = []
        for try await result in group {
          results.append(result)
        }
        return results
      }
      return Listing(files: files, downloads: downloads)
    }
    guard !deleted else { throw SyncError.profileDeleted }
    let listing = read.files
    let downloads = read.downloads
    let ownListed = listing.contains { $0.name == ownName }
    // an upload that ran while the listing was asked for may not be in it
    let mayBeStale = savingBefore || saving != nil || savesEnded != endedBefore
    var ownKept = ownListed
    if ownListed {
      markUploaded()
    } else if profileDeletedElsewhere(
      uploadedBefore: uploadedBefore, fileNames: listing.map(\.name), ownName: ownName)
    {
      if !mayBeStale, try await ownFileIsGone() {
        wipe()
        throw SyncError.profileDeleted
      } else {
        ownKept = true
      }
    } else if mayBeStale {
      ownKept = true
    }
    if !ownKept {
      ownFileId = nil
      ownUnreadable = false
      unsent = needsUpload(local: own, remote: nil)
    }
    for (entry, data) in downloads {
      let file = parseDeviceFile(data)
      if entry.name == ownName {
        ownFileId = entry.id
        ownUnreadable = file == nil
        if let file {
          // a save from this device may have landed since this copy was read
          var combined = mergeDeviceFiles([
            DeviceFileSource(deviceId: "remote", file: file),
            DeviceFileSource(deviceId: "~local", file: own),
          ])
          combined.extra = file.extra.merging(own.extra) { _, local in local }
          if file.settings == nil && own.settings == nil {
            combined.settings = nil
          }
          own = combined
          unsent = needsUpload(local: own, remote: file)
        }
      } else if let file, let fileDeviceId = deviceIdFromFileName(entry.name) {
        others[entry.id] = (entry.modifiedTime, DeviceFileSource(deviceId: fileDeviceId, file: file))
      } else {
        // a version this client doesn't read: remember it so it isn't fetched again
        others[entry.id] = (entry.modifiedTime, DeviceFileSource(deviceId: "", file: DeviceFile()))
      }
    }
    let live = Set(listing.filter { $0.name != ownName }.map(\.id))
    others = others.filter { live.contains($0.key) }
    listed = true
    lastSyncedAt = Date()
    remerge()
    if unsent && !ownUnreadable && pendingSave == nil && saving == nil {
      scheduleSave()
    }
  }

  /// The channels the feed reads, given the account's subscriptions.
  public func channels(subscriptions: [Subscription]) -> [ChannelFilter] {
    channelsFor(merged, subscriptions: subscriptions, identities: identities)
  }

  /// Followed channels that still need their name and avatar from YouTube.
  public func missingIdentities(subscriptions: [Subscription]) -> [String] {
    followedWithoutIdentity(merged, subscriptions: subscriptions, identities: identities)
  }

  /// Remember followed channels' names and avatars on this device.
  public func remember(_ summaries: [ChannelSummary]) {
    for summary in summaries {
      identities[summary.channelId] = ChannelIdentity(
        title: summary.title, thumbnail: summary.thumbnail, fetchedAt: Date())
    }
    do {
      try FileManager.default.createDirectory(
        at: identitiesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(identities).write(to: identitiesURL, options: .atomic)
    } catch {
      // asked again on the next load
    }
  }

  /// The watched entries of `ids` as last saved on any device; an id
  /// without one is absent.
  public func watchedEntries(_ ids: some Sequence<String>) -> [String: WatchedEntry] {
    var entries: [String: WatchedEntry] = [:]
    for id in ids {
      entries[id] = merged.watched[id]
    }
    return entries
  }

  /// Save one channel's filter.
  public func setFilter(_ filter: ChannelFilter) {
    setFilters([filter])
  }

  /// Save several filters as one edit, so they go up in one upload. Each
  /// keeps the unknown fields its entry had in this device's own file.
  public func setFilters(_ filters: [ChannelFilter]) {
    guard !filters.isEmpty else { return }
    let now = epochMilliseconds()
    for filter in filters {
      own.channels[filter.channelId] = ChannelEntry(
        at: now, filter: filter.storedFilter,
        extra: own.channels[filter.channelId]?.extra ?? [:])
    }
    changed()
  }

  /// Every filter as last saved on any device, by channel id, whether or
  /// not its channel is still listed.
  public func savedFilters() -> [String: JSONObject] {
    merged.channels.mapValues(\.filter)
  }

  /// Save a group edit (``saveGroup(_:listed:selections:group:name:members:)``)
  /// as one edit: every changed filter with one time, and the changed
  /// selections. Each entry keeps its unknown fields.
  public func applyGroupEdit(_ edit: GroupEdit) {
    guard !edit.isEmpty else { return }
    let now = epochMilliseconds()
    for (channelId, filter) in edit.channels {
      own.channels[channelId] = ChannelEntry(
        at: now, filter: filter, extra: own.channels[channelId]?.extra ?? [:])
    }
    let selections: [(SettingName, [String]?)] = [
      (.groupChips, edit.groupChips), (.channelGroupChips, edit.channelGroupChips),
    ]
    for case (let name, let names?) in selections {
      var settings = own.settings ?? [:]
      settings[name.rawValue] = editedSetting(
        settings[name.rawValue], value: .array(names.map(JSONValue.string)), now: now)
      own.settings = settings
    }
    changed()
  }

  /// Mark or unmark several ids as one edit, so they go up in one upload.
  /// An unmark also forgets the position.
  public func setWatched(_ ids: [String], watched: Bool) {
    guard !ids.isEmpty else { return }
    let now = epochMilliseconds()
    for id in ids {
      own.watched[id] = markedEntry(own.watched[id], now: now, watched: watched)
    }
    changed()
  }

  /// Save how far a video has been played; `ended` when its player reported
  /// the end. It is kept on this device at once and goes to Drive with the
  /// next upload, which this starts only when `upload` is set.
  public func setProgress(_ id: String, position: Int, ended: Bool, upload: Bool) {
    guard !deleted else { return }
    own.watched[id] = playedEntry(
      own.watched[id], now: epochMilliseconds(), position: position, ended: ended)
    remerge()
    writeLocal()
    unsent = true
    if upload {
      scheduleSave()
    }
  }

  /// Note the videos and playlists a full load just returned: this device's
  /// entries for them are kept another 30 days, and its entries past that
  /// are dropped, here and in Drive. Nothing is uploaded when neither
  /// changes anything.
  public func noteLoaded(_ ids: some Sequence<String>) {
    let now = epochMilliseconds()
    let kept = pruneDeviceFile(refreshSeen(own, loaded: Set(ids), now: now), now: now)
    if kept != own {
      own = kept
      changed()
    }
  }

  /// Every synced setting as last saved on any device, by name;
  /// ``SyncedSettings`` gives them meaning.
  public func settingEntries() -> [String: SettingEntry] {
    merged.settings ?? [:]
  }

  /// The synced settings the app acts on.
  public func settings() -> SyncedSettings {
    SyncedSettings(settingEntries())
  }

  /// Save a synced setting, keeping the unknown fields its entry had in this
  /// device's own file.
  public func setSetting(_ name: SettingName, value: JSONValue) {
    var settings = own.settings ?? [:]
    settings[name.rawValue] = editedSetting(
      settings[name.rawValue], value: value, now: epochMilliseconds())
    own.settings = settings
    changed()
  }

  private func changed() {
    guard !deleted else { return }
    remerge()
    writeLocal()
    unsent = true
    scheduleSave()
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task {
      guard (try? await Task.sleep(for: Self.saveDelay)) != nil else { return }
      await self.firePendingSave()
    }
  }

  private func firePendingSave() async {
    // cleared first, so an edit made during the upload doesn't cancel it
    pendingSave = nil
    try? await save()
  }

  /// Upload this device's file now; a save already running is waited for
  /// first.
  public func save() async throws {
    let previous = saving
    savesStarted += 1
    let started = savesStarted
    let task = Task {
      _ = try? await previous?.value
      defer {
        self.savesEnded += 1
        if self.savesStarted == started {
          self.saving = nil
        }
      }
      try await self.upload()
    }
    saving = task
    try await task.value
  }

  private func upload() async throws {
    if !listed {
      try await load()
    }
    guard !deleted else { throw SyncError.profileDeleted }
    guard !ownUnreadable else { throw SyncError.ownFileUnreadable }
    own = pruneDeviceFile(own, now: epochMilliseconds())
    unsent = false
    do {
      let content = try encodeDeviceFile(own)
      let ownName = ownName
      let fileId = ownFileId
      ownFileId = try await withDrive { client in
        if let fileId {
          return try await client.updateJSON(fileId: fileId, content: content).id
        } else {
          return try await client.createJSON(name: ownName, content: content).id
        }
      }
    } catch {
      unsent = true
      throw error
    }
    guard !deleted else { throw SyncError.profileDeleted }
    markUploaded()
    lastSyncedAt = Date()
    writeLocal()
  }

  /// Upload any edits Drive doesn't have yet, without waiting out the pause.
  public func flush() async throws {
    if pendingSave != nil || unsent {
      pendingSave?.cancel()
      pendingSave = nil
      try await save()
    }
  }
}
