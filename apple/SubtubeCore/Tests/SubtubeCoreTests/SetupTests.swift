import Foundation
import Testing

@testable import SubtubeCore

private func channel(_ id: String, _ configure: (inout ChannelFilter) -> Void = { _ in })
  -> ChannelFilter
{
  var channel = ChannelFilter(channelId: id, title: id, thumbnail: "")
  configure(&channel)
  return channel
}

@Suite struct CommonShortsTests {
  @Test func picksTheMajorityAndShowsOnATie() {
    let hide = channel("a") { $0.shortsFilter = .normal }
    let only = channel("b") { $0.shortsFilter = .shorts }
    #expect(commonShorts([]) == .all)
    #expect(commonShorts([hide, hide, only]) == .normal)
    #expect(commonShorts([hide, only]) == .all)
  }
}

@Suite struct SetupEditsTests {
  @Test func savesOnlyWhatChooseChannelsChanged() {
    let channels = [channel("a"), channel("b"), channel("c") { $0.enabled = false }]
    #expect(setupChannelEdits(channels, enabled: [:], shorts: nil).isEmpty)
    #expect(setupChannelEdits(channels, enabled: ["a": true, "c": false], shorts: .all).isEmpty)
    let off = setupChannelEdits(channels, enabled: ["b": false], shorts: nil)
    #expect(off.map(\.channelId) == ["b"])
    #expect(off.first?.enabled == false)
    #expect(setupChannelEdits(channels, enabled: [:], shorts: .shorts).count == 3)
    let hidden = setupChannelEdits(channels, enabled: ["c": true], shorts: .normal)
    #expect(hidden.map(\.channelId) == ["a", "b", "c"])
    #expect(hidden.allSatisfy { $0.shortsFilter == .normal })
    #expect(hidden.last?.enabled == true)
  }
}

@Suite struct SyncDecisionTests {
  @Test func unsentEditsAreUploaded() {
    var local = DeviceFile()
    #expect(!needsUpload(local: local, remote: nil))
    #expect(!needsUpload(local: local, remote: local))
    local.watched["v"] = WatchedEntry(at: 1, watched: true)
    #expect(needsUpload(local: local, remote: nil))
    #expect(needsUpload(local: local, remote: DeviceFile()))
    #expect(!needsUpload(local: local, remote: local))
  }

  @Test func aLoadKeepsFiltersEditedWhileItRan() {
    let loaded = [channel("a"), channel("b")]
    let edited = channel("b") { $0.regex = #"\blive\b"# }
    let kept = keepingEdits(loaded, edits: ["b": edited, "gone": channel("gone")])
    #expect(kept.map(\.channelId) == ["a", "b"])
    #expect(kept.last?.regex == #"\blive\b"#)
  }
}

/// Fetches that end only when released.
private actor HeldFetches {
  private(set) var started: [String] = []
  private(set) var shortsAdded: [String] = []
  private var held: [String: CheckedContinuation<ChannelItems, any Error>] = [:]

  func fetch(_ channel: ChannelFilter) async throws -> ChannelItems {
    started.append(channel.channelId)
    return try await withCheckedThrowingContinuation { held[channel.channelId] = $0 }
  }

  func addShorts(_ channel: ChannelFilter, _ fetched: ChannelItems) async throws -> ChannelItems {
    shortsAdded.append(channel.channelId)
    return try await withCheckedThrowingContinuation { held[channel.channelId] = $0 }
  }

  /// End a started fetch with `items`.
  func release(_ channelId: String, _ items: ChannelItems) {
    held.removeValue(forKey: channelId)?.resume(returning: items)
  }

  /// End a started fetch with an error.
  func fail(_ channelId: String, _ error: GoogleAPIError = .noChannel) {
    held.removeValue(forKey: channelId)?.resume(throwing: error)
  }

  func waitForStarted(_ count: Int) async {
    for _ in 0..<2000 where started.count + shortsAdded.count < count {
      try? await Task.sleep(for: .milliseconds(1))
    }
  }
}

private func uploads(_ ids: [String] = [], shorts: Bool = false) -> ChannelItems {
  ChannelItems(mode: .videos, shorts: shorts, items: ids.map { .video(makeVideo($0)) })
}

@Suite struct PrefetchTests {
  private let channels = (0..<8).map { channel("UC\($0)") }

  private func make() -> (prefetch: Prefetch, fetches: HeldFetches) {
    let fetches = HeldFetches()
    let prefetch = Prefetch(
      fetchAll: { try await fetches.fetch($0) },
      addShorts: { try await fetches.addShorts($0, $1) })
    return (prefetch, fetches)
  }

  private func settle() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  @Test func fetchesNothingUntilItIsToldWhichChannels() async {
    let (prefetch, fetches) = make()
    await settle()
    #expect(await fetches.started.isEmpty)
    #expect(await prefetch.items("UC0") == nil)
  }

  @Test func startsOnSixChannelsAtOnceAndHandsOverEachOnesItems() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly(channels)
    await fetches.waitForStarted(fetchConcurrency)
    #expect(await fetches.started.sorted() == ["UC0", "UC1", "UC2", "UC3", "UC4", "UC5"])
    await fetches.release("UC0", uploads(["v1"]))
    #expect(await prefetch.items("UC0") == uploads(["v1"]))
    await fetches.waitForStarted(7)
    #expect(await fetches.started.contains("UC6"))
  }

  @Test func hasNothingForAFailedFetchOrAChannelItWasNotGiven() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly(Array(channels.prefix(2)))
    await fetches.waitForStarted(2)
    await fetches.fail("UC1")
    #expect(await prefetch.items("UC1") == nil)
    #expect(await prefetch.items("UC7") == nil)
  }

  @Test func aSecondSetKeepsWhatIsFetchedStartsWhatIsNewAndNeverStartsWhatWasDropped() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly(channels)
    await fetches.waitForStarted(fetchConcurrency)
    await fetches.release("UC0", uploads(["v1"]))
    _ = await prefetch.items("UC0")
    await fetches.waitForStarted(7)
    // UC7 still waits and is dropped; UC9 is new
    await prefetch.fetchOnly([channels[0], channels[1], channel("UC9")])
    for started in ["UC1", "UC2", "UC3", "UC4", "UC5", "UC6"] {
      await fetches.release(started, uploads())
    }
    await fetches.waitForStarted(8)
    await settle()
    #expect(
      await fetches.started.sorted()
        == ["UC0", "UC1", "UC2", "UC3", "UC4", "UC5", "UC6", "UC9"])
    #expect(await prefetch.items("UC0") == uploads(["v1"]))
    #expect(await prefetch.items("UC7") == nil)
  }

  @Test func aChannelDroppedWhileBeingFetchedHasNoItemsAndIsNotFetchedAgainWhenItComesBack() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly([channels[0]])
    await fetches.waitForStarted(1)
    await prefetch.fetchOnly([])
    #expect(await prefetch.items("UC0") == nil)
    await prefetch.fetchOnly([channels[0]])
    await fetches.release("UC0", uploads(["v1"]))
    #expect(await prefetch.items("UC0") == uploads(["v1"]))
    #expect(await fetches.started == ["UC0"])
  }

  @Test func aShortsChoiceMadeAfterTheFetchAddsOnlyTheShortsList() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly([channels[0]])
    await fetches.waitForStarted(1)
    await fetches.release("UC0", uploads(["v1"]))
    _ = await prefetch.items("UC0")
    await prefetch.fetchOnly([channel("UC0") { $0.shortsFilter = .normal }])
    await fetches.waitForStarted(2)
    #expect(await fetches.started == ["UC0"])
    #expect(await fetches.shortsAdded == ["UC0"])
    await fetches.release("UC0", uploads(["v1"], shorts: true))
    #expect(await prefetch.items("UC0") == uploads(["v1"], shorts: true))
  }

  @Test func aShortsChoiceMadeWhileAChannelWaitsIsFetchedInOneGo() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly(channels)
    await fetches.waitForStarted(fetchConcurrency)
    await prefetch.fetchOnly(channels.map { waiting in
      var hidden = waiting
      hidden.shortsFilter = .normal
      return hidden
    })
    await fetches.release("UC0", uploads(shorts: false))
    await fetches.waitForStarted(7)
    #expect(await fetches.started.last == "UC6")
    #expect(await fetches.shortsAdded.isEmpty)
  }

  @Test func aShortsListThatFailsLeavesTheUploadsForTheFeedToAddTo() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly([channels[0]])
    await fetches.waitForStarted(1)
    await fetches.release("UC0", uploads(["v1"]))
    _ = await prefetch.items("UC0")
    await prefetch.fetchOnly([channel("UC0") { $0.shortsFilter = .normal }])
    await fetches.waitForStarted(2)
    await fetches.fail("UC0")
    #expect(await prefetch.items("UC0") == uploads(["v1"]))
  }

  @Test func afterTheDailyLimitRefusesARequestNoWaitingChannelIsAskedFor() async {
    let (prefetch, fetches) = make()
    await prefetch.fetchOnly(channels)
    await fetches.waitForStarted(fetchConcurrency)
    await fetches.fail("UC0", .dailyLimit)
    #expect(await prefetch.items("UC6") == nil)
    #expect(await prefetch.items("UC7") == nil)
    #expect(await fetches.started.count == fetchConcurrency)
  }
}

@Suite struct ShortsListNeedTests {
  private let fetched = ChannelItems(mode: .videos, items: [.video(makeVideo("v1"))])

  private actor Asked {
    var all = 0
    var shorts = 0
    func fetchedAll() { all += 1 }
    func addedShorts() { shorts += 1 }
  }

  private func complete(_ filter: ChannelFilter, have: ChannelItems?) async throws
    -> (items: ChannelItems, all: Int, shorts: Int)
  {
    let asked = Asked()
    let items = try await completeItems(
      filter, have: have,
      fetchAll: { wanted in
        await asked.fetchedAll()
        return ChannelItems(mode: wanted.contentMode, shorts: needsShorts(wanted), items: [])
      },
      addShorts: { _, have in
        await asked.addedShorts()
        return ChannelItems(mode: .videos, shorts: true, items: have.items)
      })
    return (items, await asked.all, await asked.shorts)
  }

  @Test func onlyUploadsWithShortsHiddenOrAloneNeedTheShortsList() {
    #expect(!needsShorts(channel("a")))
    #expect(needsShorts(channel("a") { $0.shortsFilter = .normal }))
    #expect(needsShorts(channel("a") { $0.shortsFilter = .shorts }))
    #expect(
      !needsShorts(
        channel("a") {
          $0.shortsFilter = .normal
          $0.contentMode = .playlists
        }))
  }

  @Test func fetchedItemsCoverAFilterOfTheirModeWithShortsMarksWhenItFiltersOnThem() {
    let hides = channel("a") { $0.shortsFilter = .normal }
    #expect(covers(fetched, channel("a")))
    #expect(!covers(fetched, hides))
    #expect(covers(ChannelItems(mode: .videos, shorts: true, items: []), hides))
    #expect(!covers(fetched, channel("a") { $0.contentMode = .playlists }))
  }

  @Test func asksForNothingWhenWhatIsFetchedIsEnough() async throws {
    let result = try await complete(channel("a"), have: fetched)
    #expect(result.items == fetched)
    #expect(result.all == 0 && result.shorts == 0)
  }

  @Test func asksOnlyForTheShortsListWhenUploadsLackIt() async throws {
    let result = try await complete(channel("a") { $0.shortsFilter = .normal }, have: fetched)
    #expect(result.items.shorts)
    #expect(result.items.items == fetched.items)
    #expect(result.all == 0 && result.shorts == 1)
  }

  @Test func fetchesEverythingWithNothingFetchedOrTheOtherMode() async throws {
    let nothing = try await complete(channel("a"), have: nil)
    #expect(nothing.all == 1 && nothing.shorts == 0)
    let otherMode = try await complete(channel("a") { $0.contentMode = .playlists }, have: fetched)
    #expect(otherMode.items.mode == .playlists)
    #expect(otherMode.all == 1 && otherMode.shorts == 0)
  }
}

@Suite struct FetchChannelsTests {
  private let channels = (0..<9).map { channel("UC\($0)") }

  private actor Asked {
    var ids: [String] = []
    func ask(_ id: String) { ids.append(id) }
  }

  @Test func aFailedChannelMakesTheLoadPartialAndTheRestGoOn() async throws {
    let result = try await fetchChannels(channels) { wanted in
      if wanted.channelId == "UC3" {
        throw GoogleAPIError.http(status: 500, body: "")
      }
      return ChannelItems(mode: .videos, items: [])
    }
    #expect(result.failed == ["UC3"])
    #expect(result.fetched.count == 8)
    #expect(!result.dailyLimit)
  }

  @Test func theDailyLimitStopsTheRequestsNotYetSentAndKeepsWhatWasFetched() async throws {
    let asked = Asked()
    let result = try await fetchChannels(channels) { wanted in
      await asked.ask(wanted.channelId)
      if wanted.channelId == "UC0" {
        return ChannelItems(mode: .videos, items: [.video(makeVideo("kept"))])
      }
      try? await Task.sleep(for: .milliseconds(20))
      throw GoogleAPIError.dailyLimit
    }
    #expect(result.dailyLimit)
    #expect(result.fetched.keys.sorted() == ["UC0"])
    #expect(result.failed.count == 8)
    // six at a time: UC0 answered and one more started before the first refusal
    #expect(await asked.ids.count <= fetchConcurrency + 1)
  }

  @Test func aRefusedTokenEndsTheFetch() async {
    await #expect(throws: GoogleAPIError.tokenExpired) {
      _ = try await fetchChannels(channels) { _ in throw GoogleAPIError.tokenExpired }
    }
  }

  @Test func onlySubscriptionsAreListedAndASavedFilterForAnotherChannelIsKept() {
    let saved = ChannelEntry(
      at: 1,
      filter: [
        "enabled": .bool(false), "regex": .string(""), "mode": .string("include"),
        "newField": .string("kept"),
      ])
    let merged = DeviceFile(channels: ["UCsub": saved, "UCgone": saved])
    let listed = channelsFor(
      merged, subscriptions: [Subscription(channelId: "UCsub", title: "zebra", thumbnail: "")])
    #expect(listed.map(\.channelId) == ["UCsub"])
    #expect(listed.first?.enabled == false)
    #expect(listed.first?.storedFilter["newField"] == .string("kept"))
    #expect(merged.channels["UCgone"] == saved)
  }

  @Test func workIsDoneAFewAtATimeAndComesBackInOrder() async throws {
    let running = Running()
    let doubled = try await mapWithConcurrency(Array(1...20), limit: 3) { number in
      await running.enter()
      try await Task.sleep(for: .milliseconds(5))
      await running.leave()
      return number * 2
    }
    #expect(doubled == (1...20).map { $0 * 2 })
    #expect(await running.most <= 3)
  }

  @Test func aLoadCalledOffIsNotAFailedChannel() async {
    await #expect(throws: CancellationError.self) {
      _ = try await fetchChannels([makeChannel()]) { _ in throw CancellationError() }
    }
    #expect(isCancellation(URLError(.cancelled)))
    #expect(!isCancellation(URLError(.notConnectedToInternet)))
  }
}

private actor Running {
  private var now = 0
  private(set) var most = 0

  func enter() {
    now += 1
    most = max(most, now)
  }

  func leave() {
    now -= 1
  }
}
