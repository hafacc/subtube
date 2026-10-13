import Foundation
import Testing

@testable import SubtubeCore

@Suite struct AccountTests {
  private let channelId = "UC" + String(repeating: "a", count: 22)

  private func defaults() throws -> (UserDefaults, String) {
    let suite = "subtube.tests.\(UUID().uuidString)"
    return (try #require(UserDefaults(suiteName: suite)), suite)
  }

  private func folder() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("subtube-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @Test func anAccountIsDrivesUserAndNeedsItsId() throws {
    let user = try JSONDecoder().decode(
      DriveUser.self,
      from: Data(
        #"{"displayName":"Ada","emailAddress":"ada@example.com","permissionId":"42","photoLink":"https://example.com/ada.jpg"}"#
          .utf8))
    #expect(
      Account(user)
        == Account(
          id: "42", name: "Ada", photo: "https://example.com/ada.jpg", email: "ada@example.com"))
    #expect(Account(DriveUser(displayName: "Ada")) == nil)
  }

  @Test func entriesFiledUnderAChannelMoveToTheAccount() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = try folder()
    let week = try #require(PendingStart(start: .week, cutoff: 1000, channels: ["UC1"]))
    defaults.set(true, forKey: onboardedKey(channelId))
    keepPendingStart(accountId: channelId, week, defaults: defaults)
    try Data("edits".utf8).write(to: directory.appendingPathComponent("sync-\(channelId).json"))
    try Data().write(to: directory.appendingPathComponent("uploaded-\(channelId)"))
    #expect(oldAccountIds(defaults: defaults, directory: directory) == [channelId])

    moveAccountEntries(from: channelId, to: "42", defaults: defaults, directory: directory)

    #expect(defaults.bool(forKey: onboardedKey("42")))
    #expect(pendingStart(accountId: "42", defaults: defaults) == week)
    #expect(
      try Data(contentsOf: directory.appendingPathComponent("sync-42.json")) == Data("edits".utf8))
    #expect(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("uploaded-42").path))
    #expect(defaults.object(forKey: onboardedKey(channelId)) == nil)
    #expect(pendingStart(accountId: channelId, defaults: defaults) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    #expect(oldAccountIds(defaults: defaults, directory: directory).isEmpty)
  }

  @Test func whatTheAccountAlreadyHasStays() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = try folder()
    try Data("old".utf8).write(to: directory.appendingPathComponent("sync-\(channelId).json"))
    try Data("new".utf8).write(to: directory.appendingPathComponent("sync-42.json"))

    moveAccountEntries(from: channelId, to: "42", defaults: defaults, directory: directory)

    #expect(
      try Data(contentsOf: directory.appendingPathComponent("sync-42.json")) == Data("new".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["sync-42.json"])
  }

  @Test func onlyChannelIdsCountAsOldEntries() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = try folder()
    defaults.set(true, forKey: onboardedKey("42"))
    defaults.set(true, forKey: "subtube.onboarded.perAccount")
    try Data().write(to: directory.appendingPathComponent("sync-42.json"))
    try Data().write(to: directory.appendingPathComponent("uploaded-42"))
    #expect(oldAccountIds(defaults: defaults, directory: directory).isEmpty)
  }
}
