import SubtubeCore
import SwiftUI

@main
struct SubtubeApp: App {
  @State private var app = AppModel()

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
/// platform's main screen.
struct RootView: View {
  let app: AppModel

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
    .task { await app.start() }
    .preferredColorScheme(app.theme.colorScheme)
    #if os(iOS)
      .tint(Color.gold)
    #endif
  }
}
