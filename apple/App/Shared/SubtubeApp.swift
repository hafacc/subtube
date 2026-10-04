import SubtubeCore
import SwiftUI

@main
struct SubtubeApp: App {
  @State private var model = AppModel()

  #if DEBUG && os(macOS)
    init() {
      DebugSnapshot.scheduleIfAsked()
    }
  #endif

  var body: some Scene {
    #if os(macOS)
      Window(Strings.appName, id: "main") {
        RootView(model: model)
      }
      .defaultSize(width: 1280, height: 800)
      .commands { FeedCommands(model: model) }
      Settings {
        MacSettingsView(app: model)
          .preferredColorScheme(model.theme.colorScheme)
      }
    #else
      WindowGroup {
        RootView(model: model)
      }
    #endif
  }
}

/// The first run until it's finished and someone is signed in, then the
/// platform's main screen.
struct RootView: View {
  let model: AppModel

  var body: some View {
    Group {
      switch model.phase {
      case .checking:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .signedOut:
        NuxView(app: model)
      case .signedIn(let feed):
        if model.onboarded {
          PlatformMainView(app: model, feed: feed)
        } else {
          NuxView(app: model)
        }
      }
    }
    .task { await model.start() }
    .preferredColorScheme(model.theme.colorScheme)
    #if os(iOS)
      .tint(Color.gold)
    #endif
  }
}
