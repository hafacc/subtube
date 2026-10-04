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
  if object["kind"]?.stringValue == "playlist" {
    return .playlist(
      Playlist(
        playlistId: id, channelId: "UC1", channelTitle: "", title: title,
        description: description, publishedAt: publishedAt, thumbnail: "", itemCount: 1))
  } else {
    return .video(
      Video(
        videoId: id, channelId: "UC1", channelTitle: "", title: title, description: description,
        publishedAt: publishedAt, thumbnail: "",
        durationSeconds: object["durationSeconds"]?.integerValue.map { Int($0) },
        liveStatus: object["liveStatus"]?.stringValue.flatMap(LiveStatus.init(rawValue:)),
        isShort: object["isShort"]?.boolValue))
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
      #expect(pruneDeviceFile(file, now: now).json == testCase["expected"], name(testCase))
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

@Suite struct SharedFeedOrderTests {
  private func items(_ value: JSONValue?) -> [FeedItem] {
    array(value).compactMap(\.objectValue).map { object in
      feedItem(object, id: object["id"]?.stringValue ?? "")
    }
  }

  @Test func feedOrder() throws {
    let all = try cases("feed-order")
    #expect(!all.isEmpty)
    for testCase in all {
      let expected = testCase["expected"]
      switch testCase["op"]?.stringValue {
      case "sort":
        let sorted = items(testCase["items"]).sorted(by: byNewest).map(\.id)
        #expect(.array(sorted.map(JSONValue.string)) == expected, name(testCase))
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
      let channels = array(testCase["channels"]).compactMap(\.objectValue).map { object in
        ChannelOrderEntry(
          id: object["id"]?.stringValue ?? "", title: object["title"]?.stringValue ?? "",
          enabled: object["enabled"]?.boolValue ?? false,
          newestPassing: object["newestPassing"]?.stringValue)
      }
      let ordered = SubtubeCore.channelOrder(channels)
      #expect(.array(ordered.map(JSONValue.string)) == testCase["expected"], name(testCase))
    }
  }
}
