import Foundation
import Testing

@testable import SubtubeCore

/* The repo's shared/ folder: the behaviour every client must agree on. */

private let sharedURL = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()  // SubtubeCoreTests
  .deletingLastPathComponent()  // Tests
  .deletingLastPathComponent()  // SubtubeCore
  .deletingLastPathComponent()  // apple
  .deletingLastPathComponent()  // repo root
  .appendingPathComponent("shared")

private func load(_ path: String) throws -> JSONValue {
  let data = try Data(contentsOf: sharedURL.appendingPathComponent(path))
  return try #require(JSONValue.parse(data), "\(path) is not JSON")
}

/// The `cases` of a fixture file.
private func cases(_ name: String) throws -> [JSONObject] {
  let fixture = try #require(try load("fixtures/\(name).json").objectValue)
  let cases = try #require(fixture["cases"].flatMap { value -> [JSONValue]? in
    if case .array(let items) = value { items } else { nil }
  })
  return cases.compactMap(\.objectValue)
}

private func name(_ testCase: JSONObject) -> Comment {
  Comment(rawValue: testCase["name"]?.stringValue ?? "?")
}

private func array(_ value: JSONValue?) -> [JSONValue] {
  if case .array(let items) = value { items } else { [] }
}

/// A feed item from a fixture's `{kind, title, description, …}`.
private func feedItem(_ object: JSONObject, id: String = "x") -> FeedItem {
  let title = object["title"]?.stringValue ?? ""
  let description = object["description"]?.stringValue ?? ""
  let publishedAt = object["publishedAt"]?.stringValue ?? ""
  let channelId = object["channelId"]?.stringValue ?? "UC1"
  if object["kind"]?.stringValue == "playlist" {
    return .playlist(
      Playlist(
        playlistId: id, channelId: channelId, channelTitle: "", title: title,
        description: description, publishedAt: publishedAt, thumbnail: "", itemCount: 1))
  } else {
    return .video(
      Video(
        videoId: id, channelId: channelId, channelTitle: "", title: title, description: description,
        publishedAt: publishedAt, thumbnail: "",
        durationSeconds: object["durationSeconds"]?.integerValue.map { Int($0) },
        liveStatus: object["liveStatus"]?.stringValue.flatMap(LiveStatus.init(rawValue:)),
        isShort: object["isShort"]?.boolValue,
        categoryId: object["categoryId"]?.stringValue))
  }
}

@Suite struct SharedPatternTests {
  @Test func metaRegexMatchesTheSharedCopy() throws {
    let text = try String(
      contentsOf: sharedURL.appendingPathComponent("patterns/meta-regex.txt"), encoding: .utf8)
    #expect(patternMetaRegex == text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  @Test func patterns() throws {
    let all = try cases("patterns")
    #expect(!all.isEmpty)
    for testCase in all {
      let pattern = try #require(testCase["pattern"]?.stringValue)
      let valid = testCase["valid"]?.boolValue ?? false
      #expect(isValidPattern(pattern) == valid, name(testCase))
      guard valid else { continue }
      for check in array(testCase["matches"]).compactMap(\.objectValue) {
        let text = check["text"]?.stringValue ?? ""
        let caseSensitive = check["caseSensitive"]?.boolValue ?? false
        let regex = try #require(compilePattern(pattern, caseSensitive: caseSensitive), name(testCase))
        let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        #expect(
          found == check["matches"]?.boolValue,
          "\(name(testCase).rawValue): \(text.debugDescription) caseSensitive \(caseSensitive)")
      }
    }
  }
}

@Suite struct SharedFilterTests {
  @Test func filters() throws {
    let all = try cases("filters")
    #expect(!all.isEmpty)
    for testCase in all {
      let stored = try #require(testCase["filter"]?.objectValue)
      let item = feedItem(try #require(testCase["item"]?.objectValue))
      let filter = ChannelFilter(channelId: "UC1", title: "", thumbnail: "", stored: stored)
      #expect(
        itemPassesFilter(item, compileFilter(filter)) == testCase["kept"]?.boolValue,
        name(testCase))
    }
  }

  @Test func savingAnEditKeepsUnknownFieldsAndValues() {
    var filter = ChannelFilter(
      channelId: "UC1", title: "One", thumbnail: "",
      stored: [
        "enabled": .bool(true), "regex": .string(""), "mode": .string("include"),
        "sortOrder": .string("newest"), "liveFilter": .string("premieres"),
      ])
    filter.shortsFilter = .normal
    #expect(
      filter.storedFilter == [
        "enabled": .bool(true), "regex": .string(""), "mode": .string("include"),
        "sortOrder": .string("newest"), "liveFilter": .string("premieres"),
        "shortsFilter": .string("normal"),
      ])
  }

  @Test func aPatternThatIsNotPhrasesIsNotAppliedAndIsSavedAsEmpty() {
    let stored: JSONObject = [
      "enabled": .bool(true), "regex": .string(#"Episode \d+"#), "mode": .string("include"),
    ]
    var filter = ChannelFilter(channelId: "UC1", title: "One", thumbnail: "", stored: stored)
    #expect(filter.regex.isEmpty)
    #expect(compileFilter(filter).regex == nil)
    // read, not edited: the stored object is what it was
    #expect(filter.stored == stored)
    filter.enabled = false
    #expect(
      filter.storedFilter == [
        "enabled": .bool(false), "regex": .string(""), "mode": .string("include"),
      ])
  }

  @Test func topicsAreSavedOnlyWhenChangedAndLeftOutWhenEmpty() {
    var filter = ChannelFilter(
      channelId: "UC1", title: "One", thumbnail: "",
      stored: [
        "enabled": .bool(true), "regex": .string(""), "mode": .string("include"),
        "topics": .array([.string("10"), .string("99"), .string("10")]),
      ])
    #expect(filter.topics == ["10"])
    #expect(filter.storedFilter["topics"] == .array([.string("10"), .string("99"), .string("10")]))
    filter.topics.append("20")
    #expect(filter.storedFilter["topics"] == .array([.string("10"), .string("20")]))
    filter.topics = []
    #expect(filter.storedFilter["topics"] == nil)
  }

  @Test func aNewFilterStoresOnlyRequiredFieldsAndNoIdentity() {
    var filter = ChannelFilter(channelId: "UC1", title: "One", thumbnail: "t")
    filter.followed = true
    #expect(
      filter.storedFilter == [
        "enabled": .bool(true), "regex": .string(""), "mode": .string("include"),
        "followed": .bool(true),
      ])
  }
}

private func sources(_ testCase: JSONObject) -> [DeviceFileSource] {
  array(testCase["files"]).compactMap(\.objectValue).compactMap { file in
    guard let deviceId = file["deviceId"]?.stringValue, let content = file["content"],
      let parsed = parseDeviceFile(content)
    else { return nil }
    return DeviceFileSource(deviceId: deviceId, file: parsed)
  }
}

@Suite struct SharedSyncTests {
  @Test func merge() throws {
    let all = try cases("merge")
    #expect(!all.isEmpty)
    for testCase in all {
      let merged = mergeDeviceFiles(sources(testCase))
      #expect(merged.json == testCase["expected"], name(testCase))
    }
  }

  @Test func prune() throws {
    let all = try cases("prune")
    #expect(!all.isEmpty)
    for testCase in all {
      let file = try #require(testCase["file"].flatMap(parseDeviceFile), name(testCase))
      let now = try #require(testCase["now"]?.integerValue)
      var written = file
      if testCase["loaded"] != nil {
        let loaded = Set(array(testCase["loaded"]).compactMap(\.stringValue))
        written = refreshSeen(file, loaded: loaded, now: now)
        #expect(written.watched.mapValues(\.at) == file.watched.mapValues(\.at), name(testCase))
      }
      #expect(pruneDeviceFile(written, now: now).json == testCase["expected"], name(testCase))
    }
  }

  @Test func exampleDeviceFiles() throws {
    let directory = sharedURL.appendingPathComponent("fixtures/device-files")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(!names.isEmpty)
    for fileName in names where fileName.hasPrefix("valid-") {
      let raw = try load("fixtures/device-files/\(fileName)")
      let parsed = try #require(parseDeviceFile(raw), "\(fileName)")
      // read and written back unchanged, unknown fields included
      #expect(parsed.json == raw, "\(fileName)")
    }
    for fileName in ["invalid-newer-version.json", "invalid-missing-version.json"] {
      #expect(parseDeviceFile(try load("fixtures/device-files/\(fileName)")) == nil, "\(fileName)")
    }
  }

  @Test func onlyDeviceFilesAreRead() {
    #expect(deviceIdFromFileName("device-ab_C-9.json") == "ab_C-9")
    #expect(deviceIdFromFileName("device-.json") == nil)
    #expect(deviceIdFromFileName("device-a.b.json") == nil)
  }

  @Test func aMissingOwnFileAfterUploadingMeansDeletedElsewhere() {
    let own = "device-me.json"
    #expect(!profileDeletedElsewhere(uploadedBefore: false, fileNames: [], ownName: own))
    #expect(
      !profileDeletedElsewhere(uploadedBefore: false, fileNames: ["device-other.json"], ownName: own))
    #expect(
      !profileDeletedElsewhere(
        uploadedBefore: true, fileNames: ["device-other.json", own], ownName: own))
    #expect(profileDeletedElsewhere(uploadedBefore: true, fileNames: [], ownName: own))
    #expect(
      profileDeletedElsewhere(uploadedBefore: true, fileNames: ["device-other.json"], ownName: own))
  }

  @Test func aDeviceFileMeansTheAccountIsSetUp() {
    #expect(!hasSyncedProfile([]))
    #expect(!hasSyncedProfile(["notes.txt", "device-.json", "device-a.b.json"]))
    #expect(hasSyncedProfile(["notes.txt", "device-ab_C-9.json"]))
    #expect(hasSyncedProfile(["device-one.json", "device-two.json"]))
    #expect(deviceIdFromFileName("notes.json") == nil)
  }
}

@Suite struct SharedShortsTests {
  private actor Requests {
    var readsList = false
    var probes: [String] = []
    func readList() { readsList = true }
    func probed(_ videoId: String) { probes.append(videoId) }
  }

  @Test func shorts() async throws {
    let all = try cases("shorts")
    #expect(!all.isEmpty)
    for testCase in all {
      let videos = array(testCase["videos"]).compactMap(\.objectValue).map { object in
        Video(
          videoId: object["videoId"]?.stringValue ?? "", channelId: "UC1", channelTitle: "",
          title: "", description: "", publishedAt: "", thumbnail: "",
          durationSeconds: object["durationSeconds"]?.integerValue.map { Int($0) })
      }
      let list: Set<String>? = testCase["shortsList"].flatMap { value in
        if case .array(let ids) = value { Set(ids.compactMap(\.stringValue)) } else { nil }
      }
      let probeAnswers = testCase["probe"]?.objectValue
      let requests = Requests()
      var probe: ShortsProbeFunction?
      if let probeAnswers {
        probe = { @Sendable (videoId: String) async -> Bool? in
          await requests.probed(videoId)
          return probeAnswers[videoId]?.boolValue
        }
      }
      let classified = try await classifyShorts(
        videos,
        loadShortIds: {
          await requests.readList()
          return list
        },
        probe: probe)
      let expected = try #require(testCase["expected"]?.objectValue)
      for video in classified {
        #expect(video.isShort == expected[video.videoId]?.boolValue, "\(name(testCase).rawValue): \(video.videoId)")
      }
      #expect(await requests.readsList == testCase["readsShortsList"]?.boolValue, name(testCase))
      let expectedProbes = Set(array(testCase["probes"]).compactMap(\.stringValue))
      #expect(Set(await requests.probes) == expectedProbes, name(testCase))
    }
  }
}

/// Items from a fixture's list of `{id, kind, title, publishedAt, durationSeconds, categoryId}`.
private func items(_ value: JSONValue?, titleFromId: Bool = false) -> [FeedItem] {
  array(value).compactMap(\.objectValue).map { object in
    let id = object["id"]?.stringValue ?? ""
    var described = object
    if titleFromId, described["title"] == nil {
      described["title"] = .string(id)
    }
    return feedItem(described, id: id)
  }
}

private func strings(_ value: JSONValue?) -> [String] {
  array(value).compactMap(\.stringValue)
}

/// Strings as JSON, compared scalar for scalar: `==` on strings would also
/// accept a canonically equivalent spelling.
private func sameTexts(_ texts: [String], _ expected: JSONValue?) -> Bool {
  texts.map { Array($0.unicodeScalars) } == strings(expected).map { Array($0.unicodeScalars) }
    && strings(expected).count == array(expected).count
}

@Suite struct SharedFeedOrderTests {
  @Test func feedOrder() throws {
    let all = try cases("feed-order")
    #expect(!all.isEmpty)
    for testCase in all {
      let expected = testCase["expected"]
      let seed = UInt32(exactly: testCase["seed"]?.integerValue ?? 0) ?? 0
      switch testCase["op"]?.stringValue {
      case "sort":
        let sort = try #require(
          FeedSort(rawValue: testCase["sort"]?.stringValue ?? "newest"), name(testCase))
        let given = items(testCase["items"], titleFromId: true)
        #expect(sameTexts(sortFeed(given, by: sort, seed: seed).map(\.id), expected), name(testCase))
        #expect(
          sameTexts(sortFeed(given.reversed(), by: sort, seed: seed).map(\.id), expected),
          "\(name(testCase).rawValue), given in reverse")
      case "hash":
        let hashes = items(testCase["items"]).map { Int64(shuffleKey(seed: seed, id: $0.id)) }
        #expect(.array(hashes.map(JSONValue.integer)) == expected, name(testCase))
      default:
        Issue.record("unknown op in \(name(testCase).rawValue)")
      }
    }
  }
}

@Suite struct SharedChannelOrderTests {
  @Test func channelOrder() throws {
    let all = try cases("channel-order")
    #expect(!all.isEmpty)
    for testCase in all {
      let sort = try #require(
        ChannelSort(rawValue: testCase["sort"]?.stringValue ?? "newest"), name(testCase))
      let channels = array(testCase["channels"]).compactMap(\.objectValue).map { object in
        ChannelOrderEntry(
          id: object["id"]?.stringValue ?? "", title: object["title"]?.stringValue ?? "",
          enabled: object["enabled"]?.boolValue ?? false,
          newest: object["newest"]?.stringValue,
          unwatched: object["unwatched"]?.integerValue.map { Int($0) } ?? 0)
      }
      #expect(
        sameTexts(SubtubeCore.channelOrder(channels, sort: sort), testCase["expected"]),
        name(testCase))
      #expect(
        sameTexts(SubtubeCore.channelOrder(channels.reversed(), sort: sort), testCase["expected"]),
        "\(name(testCase).rawValue), given in reverse")
    }
  }
}

@Suite struct SharedSettingsTests {
  @Test func settings() throws {
    let all = try cases("settings")
    #expect(!all.isEmpty)
    for testCase in all {
      let file = try #require(
        parseDeviceFile(
          .object([
            "version": .integer(1), "channels": .object([:]), "watched": .object([:]),
            "settings": testCase["settings"] ?? .null,
          ])), name(testCase))
      let read = SyncedSettings(mergeDeviceFiles([DeviceFileSource(deviceId: "a", file: file)]).settings ?? [:])
      let expected = try #require(testCase["expected"]?.objectValue, name(testCase))
      #expect(.string(read.feedSort.rawValue) == expected["feedSort"], name(testCase))
      #expect(.string(read.channelSort.rawValue) == expected["channelSort"], name(testCase))
      #expect(.bool(read.autoplay) == expected["autoplay"], name(testCase))
      #expect(.string(read.timeChip.rawValue) == expected["timeChip"], name(testCase))
      #expect(sameTexts(read.topicChips, expected["topicChips"]), name(testCase))
      #expect(
        .string(read.channelTimeChip.rawValue) == expected["channelTimeChip"], name(testCase))
      #expect(
        sameTexts(read.channelTopicChips, expected["channelTopicChips"]), name(testCase))
      // reading never changes what is stored
      #expect(file.json.objectValue?["settings"] == testCase["settings"], name(testCase))
    }
  }

  @Test func aChangeKeepsTheEntrysUnknownFields() {
    let prior = SettingEntry(at: 5, value: .string("title"), extra: ["setOn": .string("tv")])
    #expect(
      editedSetting(prior, value: .null, now: 9)
        == SettingEntry(at: 9, value: .null, extra: ["setOn": .string("tv")]))
    #expect(editedSetting(nil, value: .bool(true), now: 9) == SettingEntry(at: 9, value: .bool(true)))
  }

  @Test func aFileWithoutSettingsIsWrittenBackWithoutThem() throws {
    let raw = try load("fixtures/device-files/valid-empty.json")
    let parsed = try #require(parseDeviceFile(raw))
    #expect(parsed.settings == nil)
    #expect(parsed.json == raw)
  }

  @Test func settingsCountAsSomethingToUpload() {
    var local = DeviceFile()
    #expect(!needsUpload(local: local, remote: nil))
    local.settings = [:]
    #expect(!needsUpload(local: local, remote: nil))
    #expect(!needsUpload(local: local, remote: DeviceFile()))
    local.settings = ["autoplay": SettingEntry(at: 1, value: .bool(true))]
    #expect(needsUpload(local: local, remote: nil))
    #expect(needsUpload(local: local, remote: DeviceFile()))
    #expect(!needsUpload(local: local, remote: local))
  }

  @Test func malformedSettingsExamplesReadAsNoSetting() throws {
    for fileName in ["invalid-setting-missing-value.json", "invalid-settings-array.json"] {
      let parsed = try #require(
        parseDeviceFile(try load("fixtures/device-files/\(fileName)")), "\(fileName)")
      #expect(parsed.settings == [:], "\(fileName)")
    }
  }
}

@Suite struct SharedChipTests {
  @Test func feedChips() throws {
    let all = try cases("feed-chips")
    #expect(!all.isEmpty)
    for testCase in all {
      let expected = testCase["expected"]
      let given = items(testCase["items"])
      let now = testCase["now"]?.integerValue ?? 0
      switch testCase["op"]?.stringValue {
      case "label":
        #expect(
          topicLabel(testCase["categoryId"]?.stringValue).map(JSONValue.string) ?? .null
            == expected, name(testCase))
      case "chips":
        #expect(
          sameTexts(chipRow(given, selected: strings(testCase["selected"])), expected),
          name(testCase))
        #expect(
          sameTexts(chipRow(given.reversed(), selected: strings(testCase["selected"])), expected),
          "\(name(testCase).rawValue), given in reverse")
      case "filter":
        let timeChip = try #require(
          TimeChip(rawValue: testCase["timeChip"]?.stringValue ?? ""), name(testCase))
        let kept = chipFiltered(
          given, timeChip: timeChip, topicChips: strings(testCase["topicChips"]), now: now)
        #expect(sameTexts(kept.map(\.id), expected), name(testCase))
      case "editor":
        #expect(sameTexts(editorTopics(given), expected), name(testCase))
      case "start":
        let start = try #require(
          StartFrom(rawValue: testCase["start"]?.stringValue ?? ""), name(testCase))
        #expect(sameTexts(startMarks(given, start: start, now: now), expected), name(testCase))
      default:
        Issue.record("unknown op in \(name(testCase).rawValue)")
      }
    }
  }

  @Test func channelChips() throws {
    let all = try cases("channel-chips")
    #expect(!all.isEmpty)
    for testCase in all {
      let expected = testCase["expected"]
      let given = items(testCase["items"])
      switch testCase["op"]?.stringValue {
      case "chips":
        #expect(
          sameTexts(chipRow(given, selected: strings(testCase["selected"])), expected),
          name(testCase))
        #expect(
          sameTexts(chipRow(given.reversed(), selected: strings(testCase["selected"])), expected),
          "\(name(testCase).rawValue), given in reverse")
      case "channels":
        let timeChip = try #require(
          TimeChip(rawValue: testCase["timeChip"]?.stringValue ?? ""), name(testCase))
        let kept = chipKeptChannels(
          given, timeChip: timeChip, topicChips: strings(testCase["topicChips"]),
          now: testCase["now"]?.integerValue ?? 0)
        var held = HeldChannelOrder()
        held.recompute(strings(testCase["channels"]), kept: kept)
        #expect(sameTexts(held.ids, expected), name(testCase))
      default:
        Issue.record("unknown op in \(name(testCase).rawValue)")
      }
    }
  }

  @Test func theChannelListLooksAtOnChannelsItemsOfTheirKindThatPassTheirFilter() {
    let on = makeChannel { $0.minDurationSeconds = 300 }
    let off = makeChannel {
      $0.channelId = "UCoff"
      $0.enabled = false
    }
    let lists = makeChannel {
      $0.channelId = "UClists"
      $0.contentMode = .playlists
    }
    let channels = [on, off, lists]
    let filters = Dictionary(uniqueKeysWithValues: channels.map { ($0.channelId, compileFilter($0)) })
    let modes = Dictionary(uniqueKeysWithValues: channels.map { ($0.channelId, $0.contentMode) })
    var playlist = makePlaylist("PLlists")
    playlist.channelId = "UClists"
    let given: [FeedItem] = [
      .video(makeVideo("long")),
      .video(makeVideo("brief", durationSeconds: 60)),
      .playlist(makePlaylist("PLon")),
      .video(makeVideo("offVideo") { $0.channelId = "UCoff" }),
      .video(makeVideo("listsVideo") { $0.channelId = "UClists" }),
      .playlist(playlist),
      .video(makeVideo("stranger") { $0.channelId = "UCnone" }),
    ]
    #expect(listedItems(given, filters: filters, modes: modes).map(\.id) == ["long", "PLlists"])
  }

  @Test func onlyAVideoInOneOfTheFifteenCategoriesHasATopic() {
    #expect(FeedItem.playlist(makePlaylist()).topic == nil)
    #expect(FeedItem.video(makeVideo()).topic == nil)
    #expect(FeedItem.video(makeVideo { $0.categoryId = "10" }).topic == "10")
    #expect(FeedItem.video(makeVideo { $0.categoryId = "99" }).topic == nil)
    #expect(categoryNames.count == 15)
  }

  @Test func aTimeThatCannotBeReadIsOutsideEverySpan() {
    #expect(parseTimestamp("2026-09-20T14:13:20Z") == 1_789_913_600_000)
    #expect(parseTimestamp("2026-09-20T14:13:20.500Z") == 1_789_913_600_500)
    #expect(parseTimestamp("soon") == nil)
    #expect(publishedWithin("soon", .anyTime, now: 0))
    #expect(!publishedWithin("soon", .month, now: 0))
  }

  @Test func theStartingPointIsKeptOnTheDeviceUntilTaken() throws {
    let suite = "subtube.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(takePendingStart(accountId: "UCme", defaults: defaults) == .all)
    keepPendingStart(accountId: "UCme", start: .week, defaults: defaults)
    #expect(takePendingStart(accountId: "UCother", defaults: defaults) == .all)
    #expect(takePendingStart(accountId: "UCme", defaults: defaults) == .week)
    #expect(takePendingStart(accountId: "UCme", defaults: defaults) == .all)
    keepPendingStart(accountId: "UCme", start: .day, defaults: defaults)
    keepPendingStart(accountId: "UCme", start: .all, defaults: defaults)
    #expect(takePendingStart(accountId: "UCme", defaults: defaults) == .all)
  }
}

@Suite struct WatchedModeTests {
  private let listed: [FeedItem] = ["seen", "new", "stays"].map { .video(makeVideo($0)) }

  private func ids(_ mode: WatchedMode, staying: Set<String> = []) -> [String] {
    modeFiltered(listed, mode: mode, watched: ["seen", "stays"], staying: staying).map(\.id)
  }

  @Test func eachModeListsItsSideAndWhatChangedSidesOnScreen() {
    #expect(ids(.unwatched) == ["new"])
    #expect(ids(.watched) == ["seen", "stays"])
    #expect(ids(.all) == ["seen", "new", "stays"])
    #expect(ids(.unwatched, staying: ["stays"]) == ["new", "stays"])
    #expect(ids(.watched, staying: ["new"]) == ["seen", "new", "stays"])
  }

  @Test func autoplayDoesNotMoveOnAmongTheWatched() {
    #expect(autoplayAdvances(.unwatched))
    #expect(autoplayAdvances(.all))
    #expect(!autoplayAdvances(.watched))
  }

  @Test func anEmptyListIsCaughtUpOnlyWithNothingSelected() {
    #expect(!emptiedBySelection(mode: .unwatched, timeChip: .anyTime, topicChips: []))
    #expect(!emptiedBySelection(mode: .unwatched, timeChip: .anyTime, topicChips: ["99"]))
    #expect(emptiedBySelection(mode: .unwatched, timeChip: .anyTime, topicChips: ["10"]))
    #expect(emptiedBySelection(mode: .unwatched, timeChip: .day, topicChips: []))
    #expect(emptiedBySelection(mode: .watched, timeChip: .anyTime, topicChips: []))
    #expect(emptiedBySelection(mode: .all, timeChip: .anyTime, topicChips: []))
  }
}

@Suite struct SharedPhraseTests {
  @Test func phrases() throws {
    let all = try cases("phrases")
    #expect(!all.isEmpty)
    for testCase in all {
      let pattern = try #require(testCase["pattern"]?.stringValue, name(testCase))
      switch testCase["op"]?.stringValue {
      case "build":
        let built = phrasesToPattern(strings(testCase["phrases"]))
        #expect(sameScalars(built, pattern), name(testCase))
        #expect(isValidPattern(built), name(testCase))
        #expect(
          sameTexts(patternToPhrases(built) ?? ["not phrases"], testCase["canonical"]),
          name(testCase))
        for check in array(testCase["matches"]).compactMap(\.objectValue) {
          let text = check["text"]?.stringValue ?? ""
          let caseSensitive = check["caseSensitive"]?.boolValue ?? false
          let regex = try #require(compilePattern(built, caseSensitive: caseSensitive), name(testCase))
          let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
          #expect(
            found == check["matches"]?.boolValue,
            "\(name(testCase).rawValue): \(text.debugDescription) caseSensitive \(caseSensitive)")
        }
      case "parse":
        let read = patternToPhrases(pattern)
        if testCase["expected"] == .null {
          #expect(read == nil, name(testCase))
          #expect(phrasePatternOnly(pattern).isEmpty, name(testCase))
        } else {
          let phrases = try #require(read, name(testCase))
          #expect(sameTexts(phrases, testCase["expected"]), name(testCase))
          #expect(sameScalars(phrasesToPattern(phrases), pattern), name(testCase))
          #expect(sameScalars(phrasePatternOnly(pattern), pattern), name(testCase))
        }
      default:
        Issue.record("unknown op in \(name(testCase).rawValue)")
      }
    }
  }
}

@Suite struct SharedWatchProgressTests {
  /// A fixture's `entry` as the merged view would hold it.
  private func entry(_ testCase: JSONObject) -> WatchedEntry? {
    guard let raw = testCase["entry"] else { return nil }
    return parseDeviceFile(
      .object([
        "version": .integer(1), "channels": .object([:]), "watched": .object(["v": raw]),
      ]))?.watched["v"]
  }

  private func number(_ value: JSONValue?) -> Double? {
    switch value {
    case .integer(let whole): Double(whole)
    case .double(let fraction): fraction
    default: nil
    }
  }

  @Test func watchProgress() throws {
    let all = try cases("watch-progress")
    #expect(!all.isEmpty)
    for testCase in all {
      let given = entry(testCase)
      let duration = number(testCase["duration"]) ?? 0
      let expected = testCase["expected"]
      switch testCase["op"]?.stringValue {
      case "watched":
        #expect(isWatched(given, durationSeconds: duration) == expected?.boolValue, name(testCase))
      case "resume":
        #expect(
          resumePosition(given, durationSeconds: duration) == number(expected), name(testCase))
      case "bar":
        let fraction = progressFraction(given, durationSeconds: duration)
        if let wanted = number(expected), let fraction {
          #expect(abs(fraction - wanted) < 1e-9, name(testCase))
        } else {
          #expect(fraction == nil && expected == .null, name(testCase))
        }
      default:
        Issue.record("unknown op in \(name(testCase).rawValue)")
      }
    }
  }

  @Test func playingWritesThePositionAndOnlyTheEndMarks() {
    let prior = WatchedEntry(at: 1, watched: true, extra: ["setOn": .string("tv")])
    #expect(
      playedEntry(prior, now: 9, position: 42, ended: false)
        == WatchedEntry(
          at: 9, watched: false, extra: ["setOn": .string("tv"), "position": .integer(42)]))
    #expect(
      playedEntry(nil, now: 9, position: 600, ended: true)
        == WatchedEntry(at: 9, watched: true, extra: ["position": .integer(600)]))
  }

  @Test func aMarkKeepsThePositionAndAnUnmarkDropsIt() {
    let played = WatchedEntry(
      at: 1, watched: false, extra: ["setOn": .string("tv"), "position": .integer(42)])
    #expect(
      markedEntry(played, now: 9, watched: true)
        == WatchedEntry(
          at: 9, watched: true, extra: ["setOn": .string("tv"), "position": .integer(42)]))
    #expect(
      markedEntry(played, now: 9, watched: false)
        == WatchedEntry(at: 9, watched: false, extra: ["setOn": .string("tv")]))
    #expect(markedEntry(nil, now: 9, watched: true) == WatchedEntry(at: 9, watched: true))
  }

  @Test func aPositionIsWrittenAsANumberAndReadBack() {
    let entry = playedEntry(nil, now: 9, position: 42, ended: false)
    #expect(entry.json == .object(["at": .integer(9), "watched": .bool(false), "position": .integer(42)]))
    #expect(entry.position == 42)
    #expect(WatchedEntry(at: 1, watched: false, extra: ["position": .double(1.5)]).position == 1.5)
    #expect(WatchedEntry(at: 1, watched: false, extra: ["position": .string("42")]).position == nil)
    #expect(WatchedEntry(at: 1, watched: false, extra: ["position": .integer(-1)]).position == nil)
  }
}

@Suite struct AutoplayTests {
  private let shown: [FeedItem] = ["a", "b", "c", "d"].map { .video(makeVideo($0)) }

  private func next(_ endedId: String, _ watched: Set<String>) -> String? {
    nextUnwatched(shown, after: endedId, watched: watched)?.id
  }

  @Test func isTheItemAfterTheOneThatEndedInTheOrderShown() {
    #expect(next("a", ["a"]) == "b")
  }

  @Test func skipsWatchedItems() {
    #expect(next("a", ["a", "b", "c"]) == "d")
  }

  @Test func neverGoesBackToAnEarlierItem() {
    #expect(next("c", ["c", "d"]) == nil)
  }

  @Test func stopsAtTheEndOfTheList() {
    #expect(next("d", ["d"]) == nil)
  }

  @Test func stopsWhenTheEndedItemIsNotInTheList() {
    #expect(next("elsewhere", []) == nil)
  }
}
