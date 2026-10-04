import Foundation

/// What the player plays.
public enum PlayerContent: Sendable, Hashable {
  /// One video, marked watched when the player closes.
  case video(String)
  /// A real YouTube playlist, marked as a whole once its last video ends.
  case playlist(String)
}

/// What "Open on YouTube" opens: the video's watch page, or the playlist's
/// own page.
public func youTubePage(for content: PlayerContent) -> URL? {
  var components = URLComponents()
  components.scheme = "https"
  components.host = "www.youtube.com"
  switch content {
  case .video(let videoId):
    components.path = "/watch"
    components.queryItems = [URLQueryItem(name: "v", value: videoId)]
  case .playlist(let playlistId):
    components.path = "/playlist"
    components.queryItems = [URLQueryItem(name: "list", value: playlistId)]
  }
  return components.url
}

/// The IFrame API's `PlayerState` values this tracker reads.
public enum YouTubePlayerState {
  public static let ended = 0
  public static let playing = 1
}

/// Decides what to mark watched as the player moves, the way the web app's
/// player does: a video is marked when the player closes, but only once
/// playback ever started; a playlist is
/// marked only when its final video ends, so closing it early leaves it
/// unwatched.
public struct PlayerTracker: Sendable {
  public let content: PlayerContent
  private var started = false

  public init(content: PlayerContent) {
    self.content = content
  }

  /// The player changed state. Returns the ids to mark watched now.
  public mutating func stateChanged(
    state: Int, videoId: String?, playlistIndex: Int?, playlistLength: Int?
  ) -> [String] {
    if state == YouTubePlayerState.playing {
      started = true
    }
    switch content {
    case .playlist(let playlistId):
      // playlistLength is what the player actually loaded, with unavailable
      // videos already skipped, so its last index is the true end
      if state == YouTubePlayerState.ended, let playlistIndex, let playlistLength,
        playlistIndex == playlistLength - 1
      {
        return [playlistId]
      }
      return []
    case .video:
      return []
    }
  }

  /// The player closed. Returns the id to mark watched, if any.
  public func closed() -> String? {
    guard started, case .video(let videoId) = content else { return nil }
    return videoId
  }
}
