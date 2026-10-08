import Foundation
import Observation
import SubtubeCore
import SwiftUI
import WebKit

#if os(iOS)
  import UIKit.UIGestureRecognizerSubclass
#endif

/// One item playing: the web view with YouTube's player, and what its
/// reports save.
///
/// The session owns its web view, so the views that show it can come and go
/// (a list row scrolled away and back) without restarting playback. A video
/// starts where it was left; its position is saved as `Playback` says, and
/// ``close()`` saves it one last time. Its ``place`` says where it is drawn,
/// and moving it there neither reloads nor restarts it. While the web view
/// is covered or off screen the video is paused, and plays again once it is
/// clear.
@MainActor @Observable
final class PlayerSession: Identifiable {
  let id = UUID()
  let content: PlayerContent
  /// The card being played.
  let item: FeedItem
  /// The page it was started on: a channel's id, or nil for the feed.
  let startedOn: String?
  /// The list it was started from.
  let queue: PlayQueue
  /// Where it is drawn.
  var place: PlayerPlace {
    didSet {
      if place != oldValue {
        showsFrame = false
        unseenChecks = 0
        cardShows = true
      }
    }
  }
  /// Whether the bar with its title and buttons is drawn around the video:
  /// while the last tap or hover was on the video. A card's player never
  /// draws it (``isFramed``).
  var showsFrame = false
  /// Whether the frame is drawn now: never in a card, where the player
  /// looks like the card's thumbnail.
  var isFramed: Bool {
    showsFrame && place != .card
  }
  private(set) var loadFailed = false
  /// Whether at least half of the card holding the player shows, as its
  /// list last said.
  @ObservationIgnored var cardShows = true

  @ObservationIgnored private var playback: Playback
  @ObservationIgnored private weak var feed: FeedModel?
  @ObservationIgnored private var page: WKWebView?
  @ObservationIgnored private let startAt: Double
  @ObservationIgnored private var closed = false
  @ObservationIgnored private var covered = false
  /// How many checks in a row found the web view in no window.
  @ObservationIgnored private var unseenChecks = 0
  /// Until when a card keeps the player although under half of it shows:
  /// just after it starts there, while its list scrolls it into view, and
  /// just after YouTube's full screen ends.
  @ObservationIgnored private var settlesUntil = Date.distantPast
  @ObservationIgnored private var wasFullScreen = false
  /// Where the video was when the page last reported, to start again from
  /// after the web view's process died.
  @ObservationIgnored private var lastPosition: Double
  @ObservationIgnored private var navigation: PlayerNavigation?
  @ObservationIgnored private var coverChecks: Task<Void, Never>?
  /// The holder that asked for the web view while YouTube's full screen had it.
  @ObservationIgnored private weak var waitingHolder: PlayerHolder?
  #if os(iOS)
    @ObservationIgnored private var touches: TouchWatcher?
  #else
    @ObservationIgnored private var scrolls: ScrollWatcher?
  #endif

  /// Play one card in `place`, a video `startAt` seconds in.
  init(
    _ item: FeedItem, feed: FeedModel, startAt: Double, place: PlayerPlace, startedOn: String?,
    queue: PlayQueue
  ) {
    self.place = place
    self.startedOn = startedOn
    self.queue = queue
    switch item {
    case .video(let video): content = .video(video.videoId)
    case .playlist(let playlist): content = .playlist(playlist.playlistId)
    }
    self.item = item
    self.feed = feed
    self.startAt = startAt
    lastPosition = startAt
    settlesUntil = Date().addingTimeInterval(Self.settleTime)
    playback = Playback(content: content, isLive: item.isLive)
  }

  /// How long a card keeps the player after it starts there or comes back from full screen.
  private static let settleTime: TimeInterval = 0.5

  /// Whether a card under half showing still keeps the player for now.
  var isSettling: Bool {
    Date() < settlesUntil
  }

  /// The web view playing the item, made on first use; nil once closed.
  var webView: WKWebView? {
    if closed {
      return nil
    } else if let page {
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
      let navigation = PlayerNavigation(session: self)
      made.navigationDelegate = navigation
      made.uiDelegate = navigation
      self.navigation = navigation
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
      coverChecks = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(250))
          guard let self else { return }
          self.checkCover()
        }
      }
      #if os(macOS)
        scrolls = ScrollWatcher { [weak self] in self?.showsFrame = false }
      #endif
      return made
    }
  }

  /// Whether YouTube's full screen has the web view: it is in a view that
  /// is not one of ours. Until it is back the web view is not moved, and
  /// nothing here counts as covering it.
  var isFullScreen: Bool {
    if let holder = page?.superview {
      !(holder is PlayerHolder)
    } else {
      false
    }
  }

  /// Whether the web view is off screen or under something presented over
  /// the app.
  private var isCovered: Bool {
    if let window = page?.window {
      #if os(macOS)
        !window.isVisible || window.isMiniaturized || window.attachedSheet != nil
      #else
        window.rootViewController?.presentedViewController != nil
      #endif
    } else {
      true
    }
  }

  private func checkCover() {
    guard !closed, let page else { return }
    if isFullScreen {
      wasFullScreen = true
      return
    } else if wasFullScreen {
      wasFullScreen = false
      settlesUntil = Date().addingTimeInterval(Self.settleTime)
    }
    if let waiting = waitingHolder {
      waitingHolder = nil
      if waiting.window != nil {
        attach(page, to: waiting)
      }
    }
    unseenChecks = page.window == nil ? unseenChecks + 1 : 0
    // a card that never came on screen, or left it during full screen, can't keep the player
    if place == .card && !isSettling && (unseenChecks >= 4 || !cardShows) {
      place = .minimized
    }
    let now = isCovered
    if now != covered {
      covered = now
      showsFrame = now ? false : showsFrame
      page.evaluateJavaScript("cover(\(now))") { [weak self] _, error in
        // the page's script wasn't there yet: ask again at the next check
        if error != nil, self?.covered == now {
          self?.covered = !now
        }
      }
    }
  }

  private func attach(_ webView: WKWebView, to holder: PlayerHolder) {
    guard webView.superview !== holder else { return }
    webView.removeFromSuperview()
    webView.frame = holder.bounds
    #if os(macOS)
      webView.autoresizingMask = [.width, .height]
    #else
      webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    #endif
    holder.addSubview(webView)
    #if os(iOS)
      if let window = holder.window {
        watchTouches(in: window)
      }
    #endif
  }

  /// Put the web view in `holder`: `always` for a holder just made, else
  /// only when no holder on screen has it. During YouTube's full screen the
  /// holder waits until that is over.
  fileprivate func hold(in holder: PlayerHolder, always: Bool) {
    guard let webView else { return }
    if isFullScreen {
      waitingHolder = holder
    } else {
      // of two holders alive at once (a page pushed over a list), the one on screen keeps it
      let heldOffScreen = webView.superview?.window == nil && holder.window != nil
      if always || webView.superview == nil || heldOffScreen {
        attach(webView, to: holder)
      }
    }
  }

  /// A holder that has the web view came into a window.
  fileprivate func entered(_ holder: PlayerHolder) {
    #if os(iOS)
      if let window = holder.window, page?.superview === holder {
        watchTouches(in: window)
      }
    #endif
  }

  #if os(iOS)
    /// Watch the touches of the window the web view is in, without taking
    /// any: one on the video shows the frame, one elsewhere hides it.
    fileprivate func watchTouches(in window: UIWindow?) {
      guard !closed, touches?.view !== window else { return }
      if let touches {
        touches.view?.removeGestureRecognizer(touches)
      }
      touches = nil
      if let window {
        let watcher = TouchWatcher { [weak self] watcher, touch in
          if let self {
            self.touched(touch)
          } else {
            watcher.view?.removeGestureRecognizer(watcher)
          }
        }
        window.addGestureRecognizer(watcher)
        touches = watcher
      }
    }

    private func touched(_ touch: UITouch) {
      guard let page, let window = page.window else { return }
      let video = page.convert(page.bounds, to: window)
      let point = touch.location(in: window)
      if touch.view?.isDescendant(of: page) == true {
        showsFrame = true
      } else if !PlayerFrame.touchBox(around: video).contains(point) {
        showsFrame = false
      }
    }
  #endif

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
    if position > 0 {
      lastPosition = position
    }
    switch event {
    case "loadFailed":
      loadFailed = true
    case "error":
      // a video that can't play is over; a playlist's player skips it itself
      if case .video = content {
        feed?.playbackEnded(self)
      }
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

  /// The web view's process died: load the page again where the video was.
  fileprivate func reload() {
    if !closed, let page {
      covered = false
      page.loadHTMLString(
        PlayerPage.html(for: content, startAt: lastPosition), baseURL: PlayerPage.identity)
    }
  }

  /// Stop playing for good, saving where the video is.
  func close() {
    guard !closed else { return }
    closed = true
    coverChecks?.cancel()
    #if os(iOS)
      if let touches {
        touches.view?.removeGestureRecognizer(touches)
      }
      touches = nil
    #else
      scrolls = nil
    #endif
    waitingHolder = nil
    navigation = nil
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

/// Keeps the web view on the player's page: a link in YouTube's player
/// (its logo, the title, an end card) opens in the browser, and a page whose
/// process died is loaded again.
@MainActor
private final class PlayerNavigation: NSObject, WKNavigationDelegate, WKUIDelegate {
  private weak var session: PlayerSession?

  init(session: PlayerSession) {
    self.session = session
  }

  private func openInBrowser(_ url: URL?) {
    if let url, url.scheme == "https" || url.scheme == "http" {
      #if os(macOS)
        NSWorkspace.shared.open(url)
      #else
        UIApplication.shared.open(url)
      #endif
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
  ) async -> WKNavigationActionPolicy {
    // the player's frame loads what it likes; only the page itself must stay
    if navigationAction.targetFrame?.isMainFrame == true,
      navigationAction.navigationType == .linkActivated
    {
      openInBrowser(navigationAction.request.url)
      return .cancel
    } else {
      return .allow
    }
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    openInBrowser(navigationAction.request.url)
    return nil
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    session?.reload()
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
    #if DEBUG
      config["mute"] = CommandLine.arguments.contains("-mute")
    #endif
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
      let coverPaused = false;
      let coverPending = false;
      // pause while something covers the player, and play again once clear
      function cover(on) {
        if (!player || !player.getPlayerState) {
          // not ready: paused when it starts playing, if still covered then
          coverPending = on;
          return;
        }
        coverPending = false;
        const state = player.getPlayerState();
        if (on) {
          if (state === YT.PlayerState.PLAYING || state === YT.PlayerState.BUFFERING) {
            coverPaused = true;
            player.pauseVideo();
          }
        } else if (coverPaused) {
          coverPaused = false;
          player.playVideo();
        }
      }
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
              if (config.mute) {
                event.target.mute();
              }
              if (config.kind === "videos") {
                event.target.loadPlaylist(config.videoIds, 0, config.start);
              }
            },
            onStateChange: (event) => {
              if (coverPending && event.data === YT.PlayerState.PLAYING) {
                coverPending = false;
                coverPaused = true;
                event.target.pauseVideo();
              }
              report("state", event.data);
            },
            onError: (event) => post({ event: "error", code: event.data }),
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

/// The official YouTube IFrame player (so ads serve and views count),
/// filling the box it is given, with nothing over it; YouTube's own button
/// goes full screen.
///
/// While ``PlayerSession/isFramed`` a ``PlayerFrame`` is drawn behind and
/// around the box, so the video neither moves nor resizes.
/// `cornerRadius` rounds the box; the top corners are square under the
/// frame's bar.
struct YouTubePlayerView: View {
  let session: PlayerSession
  let feed: FeedModel
  var cornerRadius: CGFloat = 8
  /// What the frame's "Expand" does, for a minimized player.
  var onExpand: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let isMinimized = session.place == .minimized
    let topRadius = session.isFramed ? 0 : cornerRadius
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
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: topRadius, bottomLeadingRadius: cornerRadius,
        bottomTrailingRadius: cornerRadius, topTrailingRadius: topRadius, style: .continuous)
    )
    .background {
      ZStack {
        if session.isFramed {
          PlayerFrame(session: session, feed: feed, cornerRadius: cornerRadius, onExpand: onExpand)
            .transition(.opacity)
        }
      }
      .padding(.top, -PlayerFrame.barHeight)
      .padding([.horizontal, .bottom], -PlayerFrame.border)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: session.isFramed)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(session.item.title.isEmpty ? Strings.player : session.item.title)
    // the frame's buttons, which are there only after a hover or a tap
    .accessibilityAction(named: isMinimized ? Strings.expand : Strings.minimize) {
      if isMinimized {
        onExpand()
      } else {
        feed.minimize()
      }
    }
    .accessibilityAction(named: Strings.close, feed.closePlayer)
    .id(session.id)
  }
}

/// What is drawn around a minimized or large player while the last tap or
/// hover was on the video: a bar above it with the title, "Expand" for a
/// minimized player or "Minimize" for a large one, and "Close"; and a
/// hairline around it. It lies behind the video's box, larger than it by
/// the bar and the hairline.
struct PlayerFrame: View {
  let session: PlayerSession
  let feed: FeedModel
  let cornerRadius: CGFloat
  let onExpand: () -> Void

  /// The height of the bar above the video, its hairline included.
  static let barHeight: CGFloat = 37
  /// The width of the hairline around the video.
  static let border: CGFloat = 1

  #if os(macOS)
    private static let surface = Color(nsColor: .windowBackgroundColor)
  #else
    private static let surface = Color(.systemBackground)
  #endif

  /// The frame's box around a video's.
  static func box(around video: CGRect) -> CGRect {
    CGRect(
      x: video.minX - border, y: video.minY - barHeight, width: video.width + 2 * border,
      height: video.height + barHeight + border)
  }

  #if os(iOS)
    /// The side of a button's touch target.
    private static let target: CGFloat = 44
    /// How far the buttons' touch targets reach above the bar.
    private static let targetRise = target - (barHeight - border + buttonSide) / 2

    /// The frame's box with its buttons' touch targets, around a video's.
    static func touchBox(around video: CGRect) -> CGRect {
      let frame = box(around: video)
      return CGRect(
        x: frame.minX, y: frame.minY - targetRise, width: frame.width,
        height: frame.height + targetRise)
    }
  #endif

  /// The side of a button's drawn box.
  private static let buttonSide: CGFloat = 32

  private func button(_ title: String, _ symbol: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        #if os(iOS)
          // 44 pt each way, reaching up out of the bar and never down over the video
          .frame(width: Self.target, height: Self.buttonSide)
          .contentShape(
            Rectangle().size(width: Self.target, height: Self.target)
              .offset(y: Self.buttonSide - Self.target))
        #else
          .frame(width: Self.buttonSide, height: Self.buttonSide)
          .contentShape(Rectangle())
        #endif
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .help(title)
  }

  var body: some View {
    let shape = RoundedRectangle(
      cornerRadius: cornerRadius + Self.border, style: .continuous)
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Text(session.item.title)
          .font(.footnote.weight(.medium))
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        if session.place == .minimized {
          button(Strings.expand, "pip.exit", action: onExpand)
        } else {
          button(Strings.minimize, "pip.enter", action: feed.minimize)
        }
        button(Strings.close, "xmark", action: feed.closePlayer)
      }
      .padding(.leading, 12)
      .padding(.trailing, 2)
      .frame(height: Self.barHeight - Self.border)
      Spacer(minLength: 0)
    }
    .foregroundStyle(.primary)
    .background(Self.surface, in: shape)
    .overlay { shape.strokeBorder(Color.secondary.opacity(0.3), lineWidth: Self.border) }
  }
}

#if os(macOS)
  private typealias PlatformView = NSView
  private typealias PlatformViewRepresentable = NSViewRepresentable

  /// Reports every scroll in the app while it lives, and takes none.
  private final class ScrollWatcher {
    private var monitor: Any?

    init(onScroll: @escaping @MainActor () -> Void) {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        MainActor.assumeIsolated(onScroll)
        return event
      }
    }

    deinit {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }
  }
#else
  private typealias PlatformView = UIView
  private typealias PlatformViewRepresentable = UIViewRepresentable

  /// Reports every touch that begins in its window and takes none.
  private final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouch: (TouchWatcher, UITouch) -> Void

    init(onTouch: @escaping (TouchWatcher, UITouch) -> Void) {
      self.onTouch = onTouch
      super.init(target: nil, action: nil)
      cancelsTouchesInView = false
      delaysTouchesBegan = false
      delaysTouchesEnded = false
      delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      for touch in touches {
        onTouch(self, touch)
      }
      state = .failed
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
#endif

/// Holds the web view; a web view in any other view is in YouTube's full
/// screen. On iOS it tells the session which window it is in.
private final class PlayerHolder: PlatformView {
  weak var session: PlayerSession?

  #if os(iOS)
    override func didMoveToWindow() {
      super.didMoveToWindow()
      session?.entered(self)
    }
  #endif
}

/// Shows a session's web view. The view handed to SwiftUI is only a holder,
/// so dropping it doesn't end the session's playback.
private struct PlayerWebView: PlatformViewRepresentable {
  let session: PlayerSession

  private func makeHolder() -> PlayerHolder {
    let holder = PlayerHolder()
    holder.session = session
    session.hold(in: holder, always: true)
    return holder
  }

  #if os(macOS)
    func makeNSView(context: Context) -> PlayerHolder {
      makeHolder()
    }

    func updateNSView(_ holder: PlayerHolder, context: Context) {
      session.hold(in: holder, always: false)
    }
  #else
    func makeUIView(context: Context) -> PlayerHolder {
      makeHolder()
    }

    func updateUIView(_ holder: PlayerHolder, context: Context) {
      session.hold(in: holder, always: false)
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

extension View {
  /// While the player is minimized, leave empty room after a list's last
  /// row, as high as the minimized player and its margins, so the row can be
  /// scrolled clear of it.
  func minimizedPlayerRoom(_ feed: FeedModel) -> some View {
    modifier(MinimizedPlayerRoom(feed: feed))
  }
}

private struct MinimizedPlayerRoom: ViewModifier {
  let feed: FeedModel
  @State private var width: CGFloat = 0

  private var room: CGFloat {
    if feed.player?.place == .minimized {
      minimizedPlayerSize(viewWidth: width).height + 2 * minimizedPlayerMargin
    } else {
      0
    }
  }

  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Color.clear.frame(height: room).allowsHitTesting(false)
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
  }
}
