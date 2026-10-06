import Testing

@testable import SubtubeCore

private func channel(_ configure: (inout ChannelFilter) -> Void = { _ in }) -> ChannelFilter {
  var channel = ChannelFilter(channelId: "UC1", title: "One", thumbnail: "")
  configure(&channel)
  return channel
}

@Suite struct FilterSummaryTests {
  @Test func aFilterThatKeepsEverythingIsAllVideos() {
    #expect(filterSummaryParts(channel()) == [.allVideos])
  }

  @Test func topicsAloneAreNotAllVideos() {
    let music = channel { $0.topics = ["10"] }
    #expect(filterSummaryParts(music) == [.topics(["Music"])])
  }

  @Test func topicsAreNamedByNameAndUnknownIdsDropped() {
    let several = channel { $0.topics = ["10", "999", "20", "1", "10"] }
    #expect(filterSummaryParts(several) == [.topics(["Film & Animation", "Gaming", "Music"])])
    #expect(filterSummaryParts(channel { $0.topics = ["999"] }) == [.allVideos])
  }

  @Test func partsFollowTheEditorWithTopicsLast() {
    let full = channel {
      $0.regex = phrasesToPattern(["podcast", "live"])
      $0.mode = .exclude
      $0.searchScope = .both
      $0.shortsFilter = .normal
      $0.liveFilter = .vod
      $0.minDurationSeconds = 1
      $0.topics = ["20", "10"]
    }
    #expect(
      filterSummaryParts(full) == [
        .matching(phrases: ["podcast", "live"], mode: .exclude, scope: .both),
        .noShorts, .liveOnly, .hidesUnder(seconds: 1), .topics(["Gaming", "Music"]),
      ])
    #expect(
      filterSummaryParts(channel { $0.shortsFilter = .shorts; $0.liveFilter = .normal })
        == [.shortsOnly, .noLive])
  }

  @Test func playlistsLeaveOutWhatTheirEditorHides() {
    let playlists = channel {
      $0.contentMode = .playlists
      $0.shortsFilter = .normal
      $0.liveFilter = .normal
      $0.minDurationSeconds = 60
      $0.topics = ["10"]
    }
    #expect(filterSummaryParts(playlists) == [.playlists])
  }
}
