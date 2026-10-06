import SubtubeCore
import SwiftUI

/// The Feed menu, and no File ▸ New: subtube has one window.
struct FeedCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(replacing: .newItem) {}
    CommandMenu(Strings.feed) {
      let feed = model.feed
      Button(Strings.refresh) { feed?.refresh() }
        .keyboardShortcut("r")
        .disabled(feed == nil)
    }
  }
}
