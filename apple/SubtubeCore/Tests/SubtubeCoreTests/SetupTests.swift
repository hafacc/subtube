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
    let hidden = setupChannelEdits(channels, enabled: ["c": true], shorts: .normal)
    #expect(hidden.map(\.channelId) == ["a", "b", "c"])
    #expect(hidden.allSatisfy { $0.shortsFilter == .normal })
    #expect(hidden.last?.enabled == true)
  }

  @Test func filterScreensSaveOnlyARealChange() {
    let stored = channel("a")
    #expect(stored.mode == .include)
    var untouched = stored
    untouched.mode = .exclude
    #expect(setupFilterEdit(stored: stored, draft: untouched) == nil)
    var typed = untouched
    typed.regex = "live"
    #expect(setupFilterEdit(stored: stored, draft: typed)?.mode == .exclude)
    var shorts = untouched
    shorts.shortsFilter = .normal
    let saved = setupFilterEdit(stored: stored, draft: shorts)
    #expect(saved?.shortsFilter == .normal)
    #expect(saved?.mode == .include)
  }
}

@Suite struct SyncDecisionTests {
  @Test func followedNamesAreAskedWhenMissingOrADayOld() {
    var merged = DeviceFile()
    var followed = channel("UCfollowed")
    followed.followed = true
    merged.channels["UCfollowed"] = ChannelEntry(at: 1, filter: followed.storedFilter)
    let now = Date(timeIntervalSince1970: 1_000_000)
    func ask(_ identity: ChannelIdentity?) -> [String] {
      followedWithoutIdentity(
        merged, subscriptions: [], identities: identity.map { ["UCfollowed": $0] } ?? [:], now: now)
    }
    #expect(ask(nil) == ["UCfollowed"])
    #expect(ask(ChannelIdentity(title: "T", thumbnail: "")) == ["UCfollowed"])
    #expect(ask(ChannelIdentity(title: "T", thumbnail: "", fetchedAt: now.addingTimeInterval(-3600))) == [])
    #expect(
      ask(ChannelIdentity(title: "T", thumbnail: "", fetchedAt: now.addingTimeInterval(-90_000)))
        == ["UCfollowed"])
  }

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
    let edited = channel("b") { $0.regex = "live" }
    let kept = keepingEdits(loaded, edits: ["b": edited, "gone": channel("gone")])
    #expect(kept.map(\.channelId) == ["a", "b"])
    #expect(kept.last?.regex == "live")
  }

  @Test func justWatchedCardsStayWhileWatchedIsHidden() {
    let items: [FeedItem] = [.video(makeVideo("old", day: 1)), .video(makeVideo("new", day: 2))]
    #expect(feedOrder(items, watched: ["old"], hideWatched: false, justWatched: []) == ["new", "old"])
    #expect(feedOrder(items, watched: ["old"], hideWatched: true, justWatched: []) == ["new"])
    #expect(
      feedOrder(items, watched: ["old", "new"], hideWatched: true, justWatched: ["new"]) == ["new"])
  }

  @Test func failedRequestsDontShowTheirBody() {
    #expect(GoogleAPIError.http(status: 503, body: "<html>").localizedDescription == "Google request failed: 503")
    #expect(GoogleAPIError.noChannel.localizedDescription == "This Google account has no YouTube channel.")
  }
}
