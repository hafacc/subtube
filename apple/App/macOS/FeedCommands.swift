import SubtubeCore
import SwiftUI

/// The Feed menu, and no File ▸ New: subtube has one window.
struct FeedCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(replacing: .newItem) {}
    CommandMenu(Strings.feed) {
      let feed = model.feed
      let session = feed?.player
      Button(Strings.refresh) { feed?.refresh() }
        .keyboardShortcut("r")
        .disabled(feed == nil)
      Divider()
      Toggle(
        Strings.hideWatched,
        isOn: Binding(get: { feed?.hideWatched ?? true }, set: { feed?.hideWatched = $0 })
      )
      .keyboardShortcut("h", modifiers: [.command, .shift])
      .disabled(feed == nil)
      Divider()
      Button(Strings.nextVideo) { session?.next() }
        .keyboardShortcut(.rightArrow)
        .disabled(session?.hasNext != true)
      Button(Strings.markAsWatched) { session?.markCurrentWatched() }
        .keyboardShortcut("k")
        .disabled(session == nil)
    }
  }
}
