/// What the player plays.
public enum PlayerContent: Sendable, Hashable {
  /// One video, its position saved as it plays.
  case video(String)
  /// A real YouTube playlist, marked as a whole once its last video ends.
  case playlist(String)
}

/// The IFrame API's `PlayerState` values playback reacts to.
public enum YouTubePlayerState {
  public static let ended = 0
  public static let playing = 1
  public static let paused = 2
}

/// When a saved position goes to Drive.
public enum ProgressUpload: Sendable, Equatable {
  /// Only with the next upload; it is kept on the device.
  case later
  /// After the usual pause.
  case soon
  /// At once.
  case now
}

/// What the app does for a playing item.
public enum PlaybackAction: Sendable, Equatable {
  /// Save how far the video has been played, and whether its player reported
  /// the end.
  case saveProgress(position: Double, duration: Double, ended: Bool, upload: ProgressUpload)
  /// Mark the item watched without a position.
  case markWatched
  /// The item is over.
  case ended
}

/// One item in one YouTube player: saves a video's position as it plays and
/// marks it watched at the player's reported end
/// (shared/fixtures/watch-progress.json).
///
/// Nothing is saved for a playlist or a live broadcast; a playlist is marked
/// when its last video ends. The position is saved on the device every
/// ``Playback/saveEvery`` seconds while playing, and for Drive on pause and on
/// ``save(upload:)``, which the app calls when the player closes or the app
/// leaves the foreground. See also ``resumePosition(_:durationSeconds:)`` for
/// where a video starts.
public struct Playback: Sendable {
  /// How often the playing position is saved on this device, in seconds.
  public static let saveEvery = 5.0

  /// What is playing.
  public let content: PlayerContent
  /// Whether the position is saved: not for a playlist or a live broadcast.
  public let savesPosition: Bool
  private var playing = false
  // from the first time the video plays until it ends: while set, its position is worth saving
  private var tracking = false
  private var position = 0.0
  private var duration = 0.0
  private var lastRegularSave: Double?

  /// Playback of `content`; `isLive` for a broadcast that is live now.
  public init(content: PlayerContent, isLive: Bool = false) {
    self.content = content
    if case .video = content {
      savesPosition = !isLive
    } else {
      savesPosition = false
    }
  }

  private func progress(ended: Bool, upload: ProgressUpload) -> PlaybackAction {
    .saveProgress(position: position, duration: duration, ended: ended, upload: upload)
  }

  /// Save the position of a video that has played.
  public func save(upload: ProgressUpload) -> [PlaybackAction] {
    if tracking && savesPosition {
      return [progress(ended: false, upload: upload)]
    } else {
      return []
    }
  }

  /// The player reported where it is, `clock` seconds on any steady clock.
  public mutating func timeReported(position: Double, duration: Double, clock: Double)
    -> [PlaybackAction]
  {
    self.position = position
    self.duration = duration
    guard playing else { return [] }
    if let last = lastRegularSave, clock - last >= Self.saveEvery {
      lastRegularSave = clock
      return save(upload: .later)
    } else {
      lastRegularSave = lastRegularSave ?? clock
      return []
    }
  }

  private mutating func finish() -> [PlaybackAction] {
    tracking = false
    if savesPosition {
      return [progress(ended: true, upload: .soon), .ended]
    } else {
      return [.markWatched, .ended]
    }
  }

  /// The player changed state, at `position` of `duration` seconds.
  public mutating func stateChanged(
    state: Int, position: Double, duration: Double, playlistIndex: Int? = nil,
    playlistLength: Int? = nil
  ) -> [PlaybackAction] {
    self.position = position
    self.duration = duration
    let wasPlaying = playing
    playing = state == YouTubePlayerState.playing
    tracking = tracking || playing
    if case .playlist = content {
      // playlistLength is what the player loaded, unavailable videos already skipped
      if state == YouTubePlayerState.ended, let playlistIndex, let playlistLength,
        playlistIndex == playlistLength - 1
      {
        return finish()
      } else {
        return []
      }
    } else if state == YouTubePlayerState.ended {
      return finish()
    } else if state == YouTubePlayerState.paused && wasPlaying {
      return save(upload: .soon)
    } else {
      return []
    }
  }
}
