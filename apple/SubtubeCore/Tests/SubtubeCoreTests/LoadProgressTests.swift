import Foundation
import Testing

@testable import SubtubeCore

@Suite struct LoadFractionTests {
  @Test func standsAtASmallStepWhileTheSubscriptionListIsRead() {
    #expect(loadFraction(finished: 0, total: nil) == loadProgressStart)
    #expect(loadProgressStart > 0 && loadProgressStart < 0.2)
    #expect(loadFraction(finished: 0, total: 8) == loadProgressStart)
  }

  @Test func eachFinishedChannelMovesItOnByTheSameStepUpToTheEnd() {
    let steps = (0...4).map { loadFraction(finished: $0, total: 4) }
    #expect(steps == steps.sorted())
    #expect(Set(steps).count == 5)
    #expect(abs(steps[2] - (loadProgressStart + (1 - loadProgressStart) / 2)) < 1e-9)
    #expect(steps[4] == 1)
  }

  @Test func aLoadWithNoChannelToFetchIsDoneOnceTheListIsRead() {
    #expect(loadFraction(finished: 0, total: 0) == 1)
  }

  @Test func staysBetweenTheStartAndTheEnd() {
    #expect(loadFraction(finished: 9, total: 4) == 1)
    #expect(loadFraction(finished: -1, total: 4) == loadProgressStart)
  }
}

@Suite struct FetchProgressTests {
  private actor Counts {
    var seen: [Int] = []
    func add(_ count: Int) { seen.append(count) }
  }

  private func filter(_ id: String) -> ChannelFilter {
    ChannelFilter(channelId: id, title: id, thumbnail: "")
  }

  @Test func everyChannelCountsOnceFetchedFailedOrSkipped() async throws {
    let counts = Counts()
    let channels = (0..<9).map { filter("UC\($0)") }
    _ = try await fetchChannels(channels, finished: { await counts.add($0) }) { wanted in
      if wanted.channelId == "UC3" {
        throw GoogleAPIError.http(status: 500, body: "")
      }
      return ChannelItems(mode: .videos, items: [])
    }
    #expect(await counts.seen.sorted() == Array(1...9))
  }

  @Test func channelsSkippedAfterTheDailyLimitCountToo() async throws {
    let counts = Counts()
    let channels = (0..<9).map { filter("UC\($0)") }
    _ = try await fetchChannels(channels, finished: { await counts.add($0) }) { _ in
      throw GoogleAPIError.dailyLimit
    }
    #expect(await counts.seen.max() == 9)
  }
}

@Suite struct HeldChannelOrderTests {
  private func entry(_ id: String, enabled: Bool = true, unwatched: Int = 0) -> ChannelOrderEntry {
    ChannelOrderEntry(id: id, title: id, enabled: enabled, newest: nil, unwatched: unwatched)
  }

  @Test func turningAChannelOffLeavesItsRowWhereItIsUntilTheNextRecompute() {
    var held = HeldChannelOrder()
    held.recompute(channelOrder([entry("a"), entry("b"), entry("c")]))
    #expect(held.ids == ["a", "b", "c"])
    let edited = channelOrder([entry("a", enabled: false), entry("b"), entry("c")])
    #expect(edited == ["b", "c", "a"])
    held.hold(edited)
    #expect(held.ids == ["a", "b", "c"])
    held.recompute(edited)
    #expect(held.ids == ["b", "c", "a"])
  }

  @Test func aChangedCountMovesNothingWhileHeld() {
    var held = HeldChannelOrder()
    let before = [entry("a", unwatched: 3), entry("b", unwatched: 2)]
    held.recompute(channelOrder(before, sort: .unwatched))
    held.hold(channelOrder([entry("a", unwatched: 0), entry("b", unwatched: 2)], sort: .unwatched))
    #expect(held.ids == ["a", "b"])
  }

  @Test func aChannelThatIsGoneLeavesAndNewOnesGoLastInTheirOwnOrder() {
    var held = HeldChannelOrder()
    held.recompute(["c", "a", "b"])
    held.hold(["a", "d", "c", "e"])
    #expect(held.ids == ["c", "a", "d", "e"])
    held.hold(["e", "d", "c", "a"])
    #expect(held.ids == ["c", "a", "d", "e"])
  }

  @Test func aRecomputeTakesOnlyTheKeptChannels() {
    var held = HeldChannelOrder()
    held.recompute(["a", "b", "c"], kept: ["c", "a"])
    #expect(held.ids == ["a", "c"])
    held.recompute(["a", "b", "c"], kept: [])
    #expect(held.ids == [])
    held.recompute(["a", "b", "c"], kept: nil)
    #expect(held.ids == ["a", "b", "c"])
  }

  @Test func aShownChannelStaysWhenNoLongerKeptAndANewlyKeptOneGoesLast() {
    var held = HeldChannelOrder()
    held.recompute(["a", "b", "c", "d"], kept: ["a", "c"])
    held.hold(["b", "c", "a", "d"], kept: ["c", "d", "b"])
    #expect(held.ids == ["a", "c", "b", "d"])
    held.hold(["b", "c", "d"], kept: [])
    #expect(held.ids == ["c", "b", "d"])
    held.recompute(["b", "c", "d"], kept: ["d"])
    #expect(held.ids == ["d"])
  }

  @Test func holdsWhatArrivesBeforeTheFirstRecompute() {
    var held = HeldChannelOrder()
    held.hold(["a", "b"])
    held.hold(["b", "a"])
    #expect(held.ids == ["a", "b"])
  }
}
