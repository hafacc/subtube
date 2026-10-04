import Testing

@testable import SubtubeCore

@Suite struct MarkAllTests {
  @Test func marksShownUnwatchedOrUnmarksWhenAllShownAreWatched() {
    let shown: [FeedItem] = [
      .video(makeVideo("seen")), .video(makeVideo("new")), .playlist(makePlaylist("PL1")),
    ]
    #expect(markAll(shown: shown, watched: ["seen", "elsewhere"]) == .watched(["new", "PL1"]))
    #expect(
      markAll(shown: shown, watched: ["seen", "new", "PL1", "elsewhere"])
        == .unwatched(["seen", "new", "PL1"]))
    #expect(markAll(shown: [], watched: ["elsewhere"]) == .watched([]))
  }
}

@Suite struct FormatDurationTests {
  @Test func formats() {
    #expect(formatDuration(0) == "0:00")
    #expect(formatDuration(59) == "0:59")
    #expect(formatDuration(65) == "1:05")
    #expect(formatDuration(600) == "10:00")
    #expect(formatDuration(3661) == "1:01:01")
    #expect(formatDuration(36000) == "10:00:00")
  }
}

@Suite struct PlayerTrackerTests {
  @Test func marksAVideoOnlyOnceItHasPlayed() {
    let tracker = PlayerTracker(content: .video("a"))
    #expect(tracker.closed() == nil)
    var playing = tracker
    _ = playing.stateChanged(
      state: YouTubePlayerState.playing, videoId: "a", playlistIndex: 0, playlistLength: 1)
    #expect(playing.closed() == "a")
  }

  @Test func marksAPlaylistOnlyWhenItsLastVideoEnds() {
    var tracker = PlayerTracker(content: .playlist("PL1"))
    #expect(
      tracker.stateChanged(
        state: YouTubePlayerState.ended, videoId: "x", playlistIndex: 0, playlistLength: 2) == [])
    #expect(
      tracker.stateChanged(
        state: YouTubePlayerState.ended, videoId: "y", playlistIndex: 1, playlistLength: 2)
        == ["PL1"])
    #expect(tracker.closed() == nil)
  }
}

@Suite struct YouTubePageTests {
  @Test func opensTheWatchPageOrThePlaylistPage() {
    #expect(youTubePage(for: .video("abc"))?.absoluteString == "https://www.youtube.com/watch?v=abc")
    #expect(
      youTubePage(for: .playlist("PL1"))?.absoluteString == "https://www.youtube.com/playlist?list=PL1")
  }
}
