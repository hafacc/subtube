import Foundation

/// The signed-in Google account, as Drive reports it.
public struct Account: Codable, Sendable, Hashable {
  /// The account's id in Drive, which keys what a device keeps for it.
  public var id: String
  /// The account's name.
  public var name: String
  /// Avatar URL, or nil.
  public var photo: String?
  /// The account's address, when Drive gives it.
  public var email: String?

  /// An account from its parts.
  public init(id: String, name: String, photo: String? = nil, email: String? = nil) {
    self.id = id
    self.name = name
    self.photo = photo
    self.email = email
  }

  /// The account behind Drive's answer; nil when it carries no id.
  public init?(_ user: DriveUser) {
    guard let id = user.permissionId else { return nil }
    self.init(id: id, name: user.displayName, photo: user.photoLink, email: user.emailAddress)
  }
}

/// The defaults key of an account's first-run mark on this device.
public func onboardedKey(_ accountId: String) -> String {
  "subtube.onboarded.\(accountId)"
}

private func accountDefaultsKeys(_ accountId: String) -> [String] {
  [onboardedKey(accountId), pendingStartKey(accountId)]
}

private func accountFileNames(_ accountId: String) -> [String] {
  [syncFileName(accountId), uploadedFileName(accountId)]
}

/// Whether `id` is a YouTube channel's, which earlier versions filed an
/// account's entries under.
private func isChannelId(_ id: Substring) -> Bool {
  id.wholeMatch(of: /UC[\w-]{22}/) != nil
}

/// The YouTube channel ids that entries of earlier versions are still filed
/// under, in the defaults and in the store's `directory`.
public func oldAccountIds(defaults: UserDefaults = .standard, directory: URL) -> Set<String> {
  var ids: Set<String> = []
  for key in defaults.dictionaryRepresentation().keys {
    for prefix in [onboardedKey(""), pendingStartKey("")] where key.hasPrefix(prefix) {
      let id = key.dropFirst(prefix.count)
      if isChannelId(id) {
        ids.insert(String(id))
      }
    }
  }
  let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
  for name in names {
    let id: Substring? =
      if name.hasPrefix("sync-"), name.hasSuffix(".json") {
        name.dropFirst("sync-".count).dropLast(".json".count)
      } else if name.hasPrefix("uploaded-") {
        name.dropFirst("uploaded-".count)
      } else {
        nil
      }
    if let id, isChannelId(id) {
      ids.insert(String(id))
    }
  }
  return ids
}

/// File everything kept under `oldId` under `newId`; what `newId` already
/// has stays.
public func moveAccountEntries(
  from oldId: String, to newId: String, defaults: UserDefaults = .standard, directory: URL
) {
  for (old, new) in zip(accountDefaultsKeys(oldId), accountDefaultsKeys(newId)) {
    if let value = defaults.object(forKey: old) {
      if defaults.object(forKey: new) == nil {
        defaults.set(value, forKey: new)
      }
      defaults.removeObject(forKey: old)
    }
  }
  let files = FileManager.default
  for (old, new) in zip(accountFileNames(oldId), accountFileNames(newId)) {
    let source = directory.appendingPathComponent(old)
    let target = directory.appendingPathComponent(new)
    if files.fileExists(atPath: source.path) {
      if files.fileExists(atPath: target.path) {
        try? files.removeItem(at: source)
      } else {
        try? files.moveItem(at: source, to: target)
      }
    }
  }
}
