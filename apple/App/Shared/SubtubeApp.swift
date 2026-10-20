import SubtubeCore
import SwiftUI

@main
struct SubtubeApp: App {
  @State private var app = AppModel()
  #if os(macOS)
    @NSApplicationDelegateAdaptor private var delegate: MacAppDelegate
  #endif

  #if DEBUG && os(macOS)
    init() {
      DebugSnapshot.scheduleIfAsked()
    }
  #endif

  var body: some Scene {
    #if os(macOS)
      Window(Strings.appName, id: "main") {
        RootView(app: app)
      }
      .defaultSize(width: 1280, height: 800)
      .commands { FeedCommands(app: app) }
      Settings {
        MacSettingsView(app: app)
          .preferredColorScheme(app.theme.colorScheme)
      }
    #else
      WindowGroup {
        RootView(app: app)
      }
    #endif
  }
}

/// The first run until it's finished and someone is signed in, then the
/// platform's main screen; on iOS `LaunchSplash` over it until the first
/// feed after launch has loaded.
struct RootView: View {
  let app: AppModel
  #if os(iOS)
    /// Whether the splash has gone; it never comes back.
    @State private var splashGone = false

    private var showsSplash: Bool {
      if splashGone {
        return false
      } else {
        switch app.phase {
        case .checking: return true
        case .signedOut: return false
        case .signedIn(let feed): return app.onboarded && !feed.fullLoadEnded
        }
      }
    }
  #endif

  var body: some View {
    Group {
      switch app.phase {
      case .checking:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .signedOut:
        NuxView(app: app)
      case .signedIn(let feed):
        if app.onboarded {
          PlatformMainView(app: app, feed: feed)
        } else {
          NuxView(app: app)
        }
      }
    }
    #if os(iOS)
      .overlay {
        if showsSplash {
          LaunchSplash(feed: app.feed)
            .transition(.opacity)
        }
      }
      // after the bar's run to the end
      .animation(.easeInOut(duration: 0.35).delay(0.2), value: showsSplash)
      .onChange(of: showsSplash) { _, shows in
        if !shows {
          splashGone = true
        }
      }
    #endif
    .task { await app.start() }
    .preferredColorScheme(app.theme.colorScheme)
    #if os(iOS)
      .tint(Color.gold)
    #endif
  }
}

#if os(macOS)
  /// Quits once the one window closes.
  final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      true
    }
  }
#endif
