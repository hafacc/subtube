import Foundation
import Observation
import SubtubeCore
import SwiftUI
import WebKit

/// One opening of the player: what it plays, where it is, and what leaving
/// each video marks watched.
@MainActor @Observable
final class PlayerSession: Identifiable {
  let id = UUID()
  let content: PlayerContent
  /// The card being played.
  let item: FeedItem
  private var tracker: PlayerTracker

  private(set) var currentVideoId: String?
  /// What the player itself reports about the current video, for videos
  /// inside a playlist that the feed has no card for.
  private(set) var reportedTitle: String?
  private(set) var reportedDuration: Int?
  private(set) var loadFailed = false

  @ObservationIgnored private weak var feed: FeedModel?
  @ObservationIgnored weak var webView: WKWebView?

  /// Play one card: a video, or a real playlist marked when it ends.
  init(_ item: FeedItem, feed: FeedModel) {
    switch item {
    case .video(let video):
      content = .video(video.videoId)
      currentVideoId = video.videoId
    case .playlist(let playlist):
      content = .playlist(playlist.playlistId)
    }
    self.item = item
    tracker = PlayerTracker(content: content)
    self.feed = feed
  }

  var title: String {
    if case .video(let video) = item {
      return video.title
    } else {
      return reportedTitle ?? item.title
    }
  }

  var publishedDate: Date? {
    if case .video = item {
      return item.publishedDate
    } else {
      return nil
    }
  }

  var durationSeconds: Int? {
    if case .video(let video) = item, let duration = video.durationSeconds, duration > 0 {
      return duration
    } else {
      return reportedDuration
    }
  }

  /// Marks taken off by hand in this player.
  private var unmarked: Set<String> = []

  /// What "Mark Watched" marks: the card being played.
  var markTarget: String { item.id }

  /// Whether there is a next video to skip to.
  var hasNext: Bool {
    switch content {
    case .playlist: true
    case .video: false
    }
  }

  /// The current video on youtube.com.
  var youTubeURL: URL? {
    youTubePage(for: content)
  }

  func next() {
    webView?.evaluateJavaScript("player && player.nextVideo()")
  }

  func markCurrentWatched() {
    unmarked.remove(markTarget)
    feed?.markWatched(markTarget)
  }

  /// Mark the card being played watched, or take its mark off; a mark taken
  /// off here isn't put back when the video is left.
  func toggleCurrentWatched() {
    guard let feed else { return }
    if feed.watched.contains(markTarget) {
      unmarked.insert(markTarget)
      feed.unmarkWatched(markTarget)
    } else {
      markCurrentWatched()
    }
  }

  fileprivate func stateChanged(
    state: Int, videoId: String?, playlistIndex: Int?, playlistLength: Int?, title: String?,
    duration: Double?
  ) {
    let marks = tracker.stateChanged(
      state: state, videoId: videoId, playlistIndex: playlistIndex, playlistLength: playlistLength)
    for mark in marks where !unmarked.contains(mark) {
      feed?.markWatched(mark)
    }
    if let videoId, !videoId.isEmpty {
      currentVideoId = videoId
    }
    if let title, !title.isEmpty {
      reportedTitle = title
    }
    if let duration, duration > 0 {
      reportedDuration = Int(duration.rounded())
    }
  }

  fileprivate func failedToLoad() {
    loadFailed = true
  }

  /// The player is going away: mark whatever was playing.
  fileprivate func closed() {
    if let mark = tracker.closed(), !unmarked.contains(mark) {
      feed?.markWatched(mark)
    }
  }
}

/// Builds the page the web view loads. Its base URL gives YouTube the referrer
/// the embed requires; without one it refuses to play (error 153).
enum PlayerPage {
  static let baseURL = URL(string: "https://subtube.hafa.cc")!
  static let messageHandler = "subtube"

  static func html(for content: PlayerContent) -> String {
    let config: [String: Any]
    switch content {
    case .video(let videoId): config = ["kind": "videos", "videoIds": [videoId]]
    case .playlist(let playlistId): config = ["kind": "playlist", "playlistId": playlistId]
    }
    let json =
      (try? JSONSerialization.data(withJSONObject: config)).map {
        String(decoding: $0, as: UTF8.self)
      } ?? "{}"
    return """
      <!doctype html>
      <html><head>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{width:100%;height:100%}</style>
      </head><body><div id="player"></div>
      <script>
      const config = \(json);
      let player = null;
      const post = (message) => window.webkit.messageHandlers.\(messageHandler).postMessage(message);
      const tag = document.createElement("script");
      tag.src = "https://www.youtube.com/iframe_api";
      tag.onerror = () => post({ event: "loadFailed" });
      document.head.appendChild(tag);
      function onYouTubeIframeAPIReady() {
        // a video list is loaded from its ids in onReady: passing videoId with the
        // playlist param unreliably drops the first id
        const playerVars = config.kind === "playlist"
          ? { autoplay: 1, rel: 0, playsinline: 1, fs: 1, listType: "playlist", list: config.playlistId }
          : { rel: 0, playsinline: 1, fs: 1 };
        player = new YT.Player("player", {
          width: "100%",
          height: "100%",
          playerVars,
          events: {
            onReady: (event) => {
              if (config.kind === "videos") {
                event.target.loadPlaylist(config.videoIds, 0);
              }
            },
            onStateChange: (event) => {
              const target = event.target;
              const playlist = target.getPlaylist ? target.getPlaylist() : null;
              const data = target.getVideoData ? target.getVideoData() : {};
              post({
                event: "state",
                state: event.data,
                videoId: data.video_id || null,
                title: data.title || null,
                duration: target.getDuration ? target.getDuration() : null,
                playlistIndex: target.getPlaylistIndex ? target.getPlaylistIndex() : null,
                playlistLength: playlist ? playlist.length : null,
              });
            },
          },
        });
      }
      </script>
      </body></html>
      """
  }
}

/// Receives the page's player events and hands them to the session.
@MainActor
final class PlayerCoordinator: NSObject, WKScriptMessageHandler {
  let session: PlayerSession

  init(session: PlayerSession) {
    self.session = session
  }

  func makeWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(self, name: PlayerPage.messageHandler)
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.preferences.isElementFullscreenEnabled = true
    #if os(iOS)
      configuration.allowsInlineMediaPlayback = true
    #endif
    let webView = WKWebView(frame: .zero, configuration: configuration)
    #if os(macOS)
      webView.setValue(false, forKey: "drawsBackground")
    #else
      webView.isOpaque = false
      webView.backgroundColor = .black
      webView.scrollView.isScrollEnabled = false
    #endif
    webView.loadHTMLString(PlayerPage.html(for: session.content), baseURL: PlayerPage.baseURL)
    session.webView = webView
    return webView
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard let body = message.body as? [String: Any], let event = body["event"] as? String else {
      return
    }
    if event == "loadFailed" {
      session.failedToLoad()
    } else if event == "state", let state = body["state"] as? Int {
      session.stateChanged(
        state: state,
        videoId: body["videoId"] as? String,
        playlistIndex: body["playlistIndex"] as? Int,
        playlistLength: body["playlistLength"] as? Int,
        title: body["title"] as? String,
        duration: body["duration"] as? Double
      )
    }
  }

  func close(_ webView: WKWebView) {
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: PlayerPage.messageHandler)
    webView.loadHTMLString("", baseURL: nil)
    session.closed()
  }
}

/// The official YouTube IFrame player (so ads serve and views count) in a web
/// view, with YouTube's full-screen button allowed.
struct YouTubePlayerView: View {
  let session: PlayerSession

  var body: some View {
    ZStack {
      Color.black
      if session.loadFailed {
        Text(Strings.playerFailed)
          .foregroundStyle(.white.opacity(0.7))
          .multilineTextAlignment(.center)
          .padding()
      } else {
        YouTubeWebView(session: session)
      }
    }
    .aspectRatio(16 / 9, contentMode: .fit)
  }
}

#if os(macOS)
  private struct YouTubeWebView: NSViewRepresentable {
    let session: PlayerSession

    func makeCoordinator() -> PlayerCoordinator { PlayerCoordinator(session: session) }

    func makeNSView(context: Context) -> WKWebView { context.coordinator.makeWebView() }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: PlayerCoordinator) {
      coordinator.close(webView)
    }
  }
#else
  private struct YouTubeWebView: UIViewRepresentable {
    let session: PlayerSession

    func makeCoordinator() -> PlayerCoordinator { PlayerCoordinator(session: session) }

    func makeUIView(context: Context) -> WKWebView { context.coordinator.makeWebView() }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: PlayerCoordinator) {
      coordinator.close(webView)
    }
  }
#endif

/// "Channel · Sep 26, 2026 · 24:10" under the playing video's title.
struct PlayerMetaLine: View {
  let session: PlayerSession
  let onOpenChannel: (String) -> Void
  var fullDate = true

  var body: some View {
    HStack(spacing: 4) {
      Button(session.item.channelTitle) { onOpenChannel(session.item.channelId) }
        .buttonStyle(.plain)
        .foregroundStyle(Color.gold)
      if let date = session.publishedDate {
        Text("·")
        Text(fullDate ? date.formatted(.dateTime.month(.abbreviated).day().year()) : date.shortFeedDate)
      }
      if case .playlist(let playlist) = session.item {
        Text("·")
        Text(Strings.videoCount(playlist.itemCount))
      } else if let duration = session.durationSeconds {
        Text("·")
        Text(formatDuration(duration))
      }
    }
    .foregroundStyle(.secondary)
  }
}

/// Mark Watched, Open on YouTube and Next under the player.
struct PlayerActions: View {
  let session: PlayerSession
  let feed: FeedModel
  @Environment(\.openURL) private var openURL

  private var isWatched: Bool {
    feed.watched.contains(session.markTarget)
  }

  var body: some View {
    Button {
      session.toggleCurrentWatched()
    } label: {
      Label(
        isWatched ? Strings.markAsUnwatched : Strings.markAsWatched,
        systemImage: isWatched ? "checkmark.circle.fill" : "checkmark")
    }
    Button {
      if let url = session.youTubeURL {
        openURL(url)
      }
    } label: {
      Label(Strings.openOnYouTube, systemImage: "arrow.up.right.square")
    }
    if session.hasNext {
      Button(action: session.next) {
        Label(Strings.next, systemImage: "forward.end")
      }
    }
  }
}

/// The duration chip, or the playlist icon with its video count.
struct ItemBadge: View {
  let item: FeedItem

  var body: some View {
    switch item {
    case .video(let video):
      if let duration = video.durationSeconds, duration > 0 {
        ThumbnailBadge { Text(formatDuration(duration)) }
      }
    case .playlist(let playlist):
      ThumbnailBadge {
        Image(systemName: "list.and.film")
        Text("\(playlist.itemCount)")
      }
    }
  }
}
