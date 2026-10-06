import Foundation
import Observation
import SubtubeCore
import SwiftUI
import WebKit

/// One item playing: the web view with YouTube's player, and what its
/// reports save.
///
/// The session owns its web view, so the views that show it can come and go
/// (a list row scrolled away and back) without restarting playback. A video
/// starts where it was left; its position is saved as `Playback` says, and
/// ``close()`` saves it one last time.
@MainActor @Observable
final class PlayerSession: Identifiable {
  let id = UUID()
  let content: PlayerContent
  /// The card being played.
  let item: FeedItem
  private(set) var loadFailed = false

  @ObservationIgnored private var playback: Playback
  @ObservationIgnored private weak var feed: FeedModel?
  @ObservationIgnored private var page: WKWebView?
  @ObservationIgnored private let startAt: Double
  @ObservationIgnored private var closed = false

  /// Play one card, a video `startAt` seconds in.
  init(_ item: FeedItem, feed: FeedModel, startAt: Double) {
    switch item {
    case .video(let video): content = .video(video.videoId)
    case .playlist(let playlist): content = .playlist(playlist.playlistId)
    }
    self.item = item
    self.feed = feed
    self.startAt = startAt
    playback = Playback(content: content, isLive: item.isLive)
  }

  /// The web view playing the item, made on first use.
  var webView: WKWebView {
    if let page {
      return page
    } else {
      let configuration = WKWebViewConfiguration()
      configuration.userContentController.add(
        PlayerMessages(session: self), name: PlayerPage.messageHandler)
      configuration.mediaTypesRequiringUserActionForPlayback = []
      configuration.preferences.isElementFullscreenEnabled = true
      #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
      #endif
      let made = WKWebView(frame: .zero, configuration: configuration)
      #if os(macOS)
        made.setValue(false, forKey: "drawsBackground")
      #else
        made.isOpaque = false
        made.backgroundColor = .black
        made.scrollView.isScrollEnabled = false
      #endif
      made.loadHTMLString(
        PlayerPage.html(for: content, startAt: startAt), baseURL: PlayerPage.identity)
      page = made
      return made
    }
  }

  private func perform(_ actions: [PlaybackAction]) {
    for action in actions {
      switch action {
      case .saveProgress(let position, let duration, let ended, let upload):
        feed?.recordProgress(
          item.id, position: position, playerDuration: duration, ended: ended, upload: upload)
      case .markWatched:
        feed?.markWatched(item.id)
      case .ended:
        feed?.playbackEnded(self)
      }
    }
  }

  fileprivate func received(_ message: [String: Any]) {
    guard !closed, let event = message["event"] as? String else { return }
    let position = message["time"] as? Double ?? 0
    let duration = message["duration"] as? Double ?? 0
    switch event {
    case "loadFailed":
      loadFailed = true
    case "time":
      perform(
        playback.timeReported(
          position: position, duration: duration, clock: ProcessInfo.processInfo.systemUptime))
    case "state":
      if let state = message["state"] as? Int {
        perform(
          playback.stateChanged(
            state: state, position: position, duration: duration,
            playlistIndex: message["playlistIndex"] as? Int,
            playlistLength: message["playlistLength"] as? Int))
      }
    default:
      break
    }
  }

  /// Save where the video is, as last reported.
  func save(upload: ProgressUpload) {
    perform(playback.save(upload: upload))
  }

  /// Stop playing for good, saving where the video is.
  func close() {
    guard !closed else { return }
    closed = true
    save(upload: .soon)
    if let page {
      page.configuration.userContentController.removeScriptMessageHandler(
        forName: PlayerPage.messageHandler)
      page.loadHTMLString("", baseURL: nil)
      page.removeFromSuperview()
    }
    page = nil
  }
}

/// Hands the page's player events to the session, without keeping it alive.
@MainActor
private final class PlayerMessages: NSObject, WKScriptMessageHandler {
  private weak var session: PlayerSession?

  init(session: PlayerSession) {
    self.session = session
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    if let body = message.body as? [String: Any] {
      session?.received(body)
    }
  }
}

/// Builds the page the web view loads. Its base URL gives YouTube the referrer
/// the embed requires; without one it refuses to play (error 153).
enum PlayerPage {
  /// `https://<bundle id>`: YouTube asks a native app's embed to name the
  /// app, not a website, as its origin and referrer.
  static let identity = Bundle.main.bundleIdentifier.flatMap {
    URL(string: "https://\($0.lowercased())")
  }
  static let messageHandler = "subtube"

  static func html(for content: PlayerContent, startAt: Double) -> String {
    var config: [String: Any]
    switch content {
    case .video(let videoId):
      config = ["kind": "videos", "videoIds": [videoId], "start": startAt]
    case .playlist(let playlistId): config = ["kind": "playlist", "playlistId": playlistId]
    }
    config["identity"] = identity?.absoluteString ?? ""
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
      const report = (event, state) => {
        const playlist = player.getPlaylist ? player.getPlaylist() : null;
        post({
          event,
          state,
          time: player.getCurrentTime ? player.getCurrentTime() : 0,
          duration: player.getDuration ? player.getDuration() : 0,
          playlistIndex: player.getPlaylistIndex ? player.getPlaylistIndex() : null,
          playlistLength: playlist ? playlist.length : null,
        });
      };
      const tag = document.createElement("script");
      tag.src = "https://www.youtube.com/iframe_api";
      tag.onerror = () => post({ event: "loadFailed" });
      document.head.appendChild(tag);
      function onYouTubeIframeAPIReady() {
        // a video is loaded from its id in onReady: passing videoId with the
        // playlist param unreliably drops the first id
        const playerVars = config.kind === "playlist"
          ? { autoplay: 1, rel: 0, playsinline: 1, fs: 1, listType: "playlist", list: config.playlistId }
          : { rel: 0, playsinline: 1, fs: 1 };
        if (config.identity) {
          playerVars.origin = config.identity;
          playerVars.widget_referrer = config.identity;
        }
        player = new YT.Player("player", {
          width: "100%",
          height: "100%",
          playerVars,
          events: {
            onReady: (event) => {
              if (config.kind === "videos") {
                event.target.loadPlaylist(config.videoIds, 0, config.start);
              }
            },
            onStateChange: (event) => report("state", event.data),
          },
        });
        // read when the frame's page loads, so it must be set before then
        player.getIframe().allowFullscreen = true;
        setInterval(() => {
          if (player.getPlayerState && player.getPlayerState() === YT.PlayerState.PLAYING) {
            report("time", null);
          }
        }, 1000);
      }
      </script>
      </body></html>
      """
  }
}

/// The official YouTube IFrame player (so ads serve and views count) in a
/// 16:9 box, with nothing around it; YouTube's own button goes full screen.
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
        PlayerWebView(session: session)
      }
    }
    .aspectRatio(16 / 9, contentMode: .fit)
    .id(session.id)
  }
}

#if os(macOS)
  private typealias PlatformView = NSView
  private typealias PlatformViewRepresentable = NSViewRepresentable
#else
  private typealias PlatformView = UIView
  private typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Shows a session's web view. The view handed to SwiftUI is only a holder,
/// so dropping it doesn't end the session's playback.
private struct PlayerWebView: PlatformViewRepresentable {
  let session: PlayerSession

  private func hold(_ holder: PlatformView, always: Bool) {
    let webView = session.webView
    // of two holders alive at once (a page pushed over a list), the one on screen keeps it
    let heldOffScreen = webView.superview?.window == nil && holder.window != nil
    guard webView.superview !== holder, always || webView.superview == nil || heldOffScreen
    else { return }
    webView.removeFromSuperview()
    webView.frame = holder.bounds
    #if os(macOS)
      webView.autoresizingMask = [.width, .height]
    #else
      webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    #endif
    holder.addSubview(webView)
  }

  #if os(macOS)
    func makeNSView(context: Context) -> NSView {
      let holder = NSView()
      hold(holder, always: true)
      return holder
    }

    func updateNSView(_ holder: NSView, context: Context) {
      hold(holder, always: false)
    }
  #else
    func makeUIView(context: Context) -> UIView {
      let holder = UIView()
      hold(holder, always: true)
      return holder
    }

    func updateUIView(_ holder: UIView, context: Context) {
      hold(holder, always: false)
    }
  #endif
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
