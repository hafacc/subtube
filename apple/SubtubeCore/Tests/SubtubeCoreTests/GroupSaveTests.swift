import Foundation
import Testing

@testable import SubtubeCore

private struct NoTokens: AccessTokenSource {
  func validToken() async throws -> String { throw CancellationError() }
  func refreshedToken() async throws -> String { throw CancellationError() }
}

@Suite struct GroupSaveTests {
  private let accountId = "UCaccount"

  /// A store over a fresh folder holding `local` as this device's unsent file.
  private func store(_ local: String) throws -> (SyncStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("subtube-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let localURL = directory.appendingPathComponent("sync-\(accountId).json")
    try Data(local.utf8).write(to: localURL)
    let store = SyncStore(
      accountId: accountId, tokens: NoTokens(), directory: directory, deviceId: "here")
    return (store, localURL)
  }

  private let twoChannels = """
    {
      "version": 1,
      "channels": {
        "UC1": {
          "at": 5, "note": "kept",
          "filter": {"enabled": true, "regex": "", "mode": "include", "groups": ["Old"], "later": 1}
        },
        "UC2": {"at": 6, "filter": {"enabled": false, "regex": "", "mode": "include"}}
      },
      "watched": {},
      "settings": {"groupChips": {"at": 7, "value": ["Old"], "from": "elsewhere"}}
    }
    """

  @Test func savedFiltersAreEveryFilterListedOrNot() async throws {
    let (store, _) = try store(twoChannels)
    let saved = await store.savedFilters()
    #expect(Set(saved.keys) == ["UC1", "UC2"])
    #expect(filterGroups(saved["UC1"] ?? [:]) == ["Old"])
    #expect(saved["UC1"]?["later"] == .integer(1))
  }

  @Test func aGroupEditIsOneSaveWithOneTimeThatKeepsUnknownFields() async throws {
    let (store, localURL) = try store(twoChannels)
    let saved = await store.savedFilters()
    let edit = saveGroup(
      saved, listed: ["UC1", "UC2"],
      selections: GroupSelections(groupChips: ["Old"], channelGroupChips: []), group: "Old",
      name: "New", members: ["UC1", "UC2"])
    #expect(Set(edit.channels.keys) == ["UC1", "UC2"])
    #expect(edit.groupChips == ["New"] && edit.channelGroupChips == nil)
    await store.applyGroupEdit(edit)

    let after = await store.savedFilters()
    #expect(filterGroups(after["UC1"] ?? [:]) == ["New"])
    #expect(filterGroups(after["UC2"] ?? [:]) == ["New"])
    #expect(after["UC1"]?["later"] == .integer(1))
    #expect(after["UC2"]?["enabled"] == .bool(false))
    #expect(await store.settings().groupChips == ["New"])
    #expect(await store.settings().channelGroupChips == [])

    let written = try #require(parseDeviceFile(try Data(contentsOf: localURL)))
    let first = try #require(written.channels["UC1"])
    let second = try #require(written.channels["UC2"])
    let chips = try #require(written.settings?[SettingName.groupChips.rawValue])
    #expect(first.at > 7 && first.at == second.at && chips.at == first.at)
    #expect(first.extra["note"] == .string("kept"))
    #expect(chips.extra["from"] == .string("elsewhere"))
    #expect(written.settings?[SettingName.channelGroupChips.rawValue] == nil)
  }

  @Test func anEditThatChangesNothingWritesNothing() async throws {
    let (store, localURL) = try store(twoChannels)
    let before = try Data(contentsOf: localURL)
    await store.applyGroupEdit(GroupEdit())
    #expect(try Data(contentsOf: localURL) == before)
  }

  @Test func aGroupEditMadeDuringALoadWinsOverTheLoadsOlderCopy() {
    let stored: JSONObject = [
      "enabled": .bool(true), "regex": .string(""), "mode": .string("include"),
    ]
    let listed = ["UC1", "UC2"].map {
      ChannelFilter(channelId: $0, title: "Channel \($0)", thumbnail: "thumb", stored: stored)
    }
    let edit = saveGroup(
      ["UC1": stored, "UC2": stored], listed: ["UC1", "UC2"],
      selections: GroupSelections(groupChips: [], channelGroupChips: []), group: nil,
      name: "Talks", members: ["UC2"])
    let edited = groupEdited(listed, by: edit)
    #expect(Array(edited.keys) == ["UC2"])
    #expect(edited["UC2"]?.title == "Channel UC2" && edited["UC2"]?.thumbnail == "thumb")
    // the load read Drive before the edit, so its copy has no group
    let shown = keepingEdits(listed, edits: edited)
    #expect(shown.map(\.groups) == [[], ["Talks"]])
    #expect(groupNames(shown.map(\.groups)) == ["Talks"])
  }

  @Test func aNameTooLongIsNoNameSoItCannotBeSaved() {
    let full = String(repeating: "x", count: groupNameMax)
    #expect(groupName("  \(full) ") == full)
    #expect(groupName("\(full)y") == nil)
    #expect(groupName("   ") == nil)
  }

  @Test func theLargePlayerFitsUnderItsBarAndIsNeverSmallerThanYouTubeAllows() {
    let (width, height) = largePlayerSize(viewWidth: 1400, viewHeight: 900, barHeight: 37)
    #expect(width == 1304 && height == 734)
    let tall = largePlayerSize(viewWidth: 800, viewHeight: 2000, barHeight: 37)
    #expect(tall.width == 736 && tall.height == 414)
    for side in stride(from: 0.0, through: 600.0, by: 50.0) {
      let small = largePlayerSize(viewWidth: side, viewHeight: side, barHeight: 37)
      #expect(small.width >= 356 && small.height >= minimumPlayerSide)
    }
  }
}
