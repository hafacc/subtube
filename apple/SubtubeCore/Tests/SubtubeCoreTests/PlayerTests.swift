import Testing

@testable import SubtubeCore

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

@Suite struct PlaybackTests {
  private func progress(_ position: Double, ended: Bool = false, _ upload: ProgressUpload)
    -> PlaybackAction
  {
    .saveProgress(position: position, duration: 600, ended: ended, upload: upload)
  }

  @Test func nothingIsSavedBeforePlaybackStarts() {
    var playback = Playback(content: .video("a"))
    #expect(playback.timeReported(position: 0, duration: 600, clock: 0) == [])
    #expect(playback.save(upload: .soon) == [])
    #expect(playback.stateChanged(state: YouTubePlayerState.paused, position: 0, duration: 600) == [])
  }

  @Test func whilePlayingThePositionIsSavedOnTheDeviceEveryFiveSeconds() {
    var playback = Playback(content: .video("a"))
    #expect(playback.stateChanged(state: YouTubePlayerState.playing, position: 0, duration: 600) == [])
    #expect(playback.timeReported(position: 1, duration: 600, clock: 100) == [])
    #expect(playback.timeReported(position: 5, duration: 600, clock: 104) == [])
    #expect(playback.timeReported(position: 6, duration: 600, clock: 105) == [progress(6, .later)])
    #expect(playback.timeReported(position: 9, duration: 600, clock: 108) == [])
    #expect(playback.timeReported(position: 11, duration: 600, clock: 110) == [progress(11, .later)])
  }

  @Test func pausingAndLeavingSaveForDriveWithTheLastReportedPosition() {
    var playback = Playback(content: .video("a"))
    _ = playback.stateChanged(state: YouTubePlayerState.playing, position: 0, duration: 600)
    #expect(
      playback.stateChanged(state: YouTubePlayerState.paused, position: 30, duration: 600)
        == [progress(30, .soon)])
    #expect(playback.timeReported(position: 31, duration: 600, clock: 0) == [])
    #expect(playback.stateChanged(state: YouTubePlayerState.paused, position: 31, duration: 600) == [])
    #expect(playback.save(upload: .soon) == [progress(31, .soon)])
    #expect(playback.save(upload: .now) == [progress(31, .now)])
  }

  @Test func theEndMarksTheVideoAndNothingMoreIsSavedUntilItPlaysAgain() {
    var playback = Playback(content: .video("a"))
    _ = playback.stateChanged(state: YouTubePlayerState.playing, position: 0, duration: 600)
    #expect(
      playback.stateChanged(state: YouTubePlayerState.ended, position: 600, duration: 600)
        == [progress(600, ended: true, .soon), .ended])
    #expect(playback.save(upload: .soon) == [])
    _ = playback.stateChanged(state: YouTubePlayerState.playing, position: 20, duration: 600)
    #expect(playback.save(upload: .soon) == [progress(20, .soon)])
  }

  @Test func nothingIsSavedForALiveBroadcastWhichIsMarkedWhenItEnds() {
    var playback = Playback(content: .video("a"), isLive: true)
    _ = playback.stateChanged(state: YouTubePlayerState.playing, position: 0, duration: 0)
    #expect(playback.timeReported(position: 50, duration: 0, clock: 0) == [])
    #expect(playback.save(upload: .now) == [])
    #expect(
      playback.stateChanged(state: YouTubePlayerState.ended, position: 50, duration: 0)
        == [.markWatched, .ended])
  }

  @Test func aPlaylistIsMarkedOnlyWhenItsLastVideoEnds() {
    var playback = Playback(content: .playlist("PL1"))
    _ = playback.stateChanged(
      state: YouTubePlayerState.playing, position: 0, duration: 60, playlistIndex: 0,
      playlistLength: 2)
    #expect(playback.timeReported(position: 9, duration: 60, clock: 0) == [])
    #expect(
      playback.stateChanged(
        state: YouTubePlayerState.ended, position: 60, duration: 60, playlistIndex: 0,
        playlistLength: 2) == [])
    #expect(playback.save(upload: .soon) == [])
    #expect(
      playback.stateChanged(
        state: YouTubePlayerState.ended, position: 60, duration: 60, playlistIndex: 1,
        playlistLength: 2) == [.markWatched, .ended])
  }
}

@Suite struct PlayerPlaceTests {
  private func video(_ id: String) -> FeedItem {
    .video(
      Video(
        videoId: id, channelId: "UC1", channelTitle: "", title: id, description: "",
        publishedAt: "", thumbnail: "", durationSeconds: 60, liveStatus: .normal, isShort: false,
        categoryId: ""))
  }

  @Test func theMinimizedPlayerIsNeverSmallerThanYouTubeAllows() {
    for viewWidth in stride(from: 0.0, through: 1400.0, by: 7.0) {
      let (width, height) = minimizedPlayerSize(viewWidth: viewWidth)
      #expect(width >= minimumPlayerSide && width <= minimizedPlayerWidth)
      #expect(height >= minimumPlayerSide)
    }
    let (width, height) = minimizedPlayerSize(viewWidth: 402)
    #expect(width == 356 && height == 200)
  }

  @Test func theNextItemComesFromTheListThePlayerWasStartedFrom() {
    let queue = PlayQueue(items: ["a", "b", "c"].map(video), mode: .unwatched)
    #expect(nextInQueue(queue, after: "a", watched: ["b"], autoplay: true)?.id == "c")
    #expect(nextInQueue(queue, after: "a", watched: [], autoplay: false) == nil)
    #expect(nextInQueue(queue, after: "c", watched: [], autoplay: true) == nil)
    let watchedList = PlayQueue(items: queue.items, mode: .watched)
    #expect(nextInQueue(watchedList, after: "a", watched: [], autoplay: true) == nil)
  }

  @Test func aCardThatIsNotShowingHandsTheNextItemToTheMinimizedPlayer() {
    #expect(endOutcome(place: .card, hasNext: true, nextCardShowing: false) == .next(.minimized))
    #expect(endOutcome(place: .card, hasNext: true, nextCardShowing: true) == .next(.card))
    #expect(endOutcome(place: .large, hasNext: false, nextCardShowing: false) == .stay)
    #expect(endOutcome(place: .minimized, hasNext: false, nextCardShowing: false) == .stay)
    #expect(endOutcome(place: .card, hasNext: false, nextCardShowing: true) == .close)
  }
}

@Suite struct MarkFromTheBarTests {
  @Test func aMarkFillsTheBarAndAnUnmarkEmptiesIt() {
    let played = playedEntry(nil, now: 1, position: 120, ended: false)
    let partly = progressFraction(played, durationSeconds: 600) ?? 0
    #expect(partly > 0 && partly < 1)
    let marked = markedEntry(played, now: 2, watched: true)
    #expect(isWatched(marked, durationSeconds: 600))
    #expect(progressFraction(marked, durationSeconds: 600) == 1)
    let unmarked = markedEntry(marked, now: 3, watched: false)
    #expect(!isWatched(unmarked, durationSeconds: 600))
    #expect((progressFraction(unmarked, durationSeconds: 600) ?? 0) == 0)
    #expect(resumePosition(unmarked, durationSeconds: 600) == 0)
  }
}
