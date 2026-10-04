import SubtubeCore
import SwiftUI

/// The player filling the window: video and its actions.
struct MacPlayerScreen: View {
  let session: PlayerSession
  let feed: FeedModel

  private func openChannel(_ channelId: String) {
    feed.player = nil
    feed.selectedChannel = channelId
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          YouTubePlayerView(session: session)
            .clipShape(RoundedRectangle(cornerRadius: 10))
          HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
              Text(session.title).font(.title2.bold()).textSelection(.enabled)
              PlayerMetaLine(session: session, onOpenChannel: openChannel)
            }
            Spacer()
            HStack(spacing: 8) {
              PlayerActions(session: session, feed: feed)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
          }
        }
        .padding(20)
      }
    }
    .navigationTitle(session.title)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          feed.player = nil
        } label: {
          Label(Strings.closePlayer, systemImage: "chevron.backward")
        }
        .keyboardShortcut(.cancelAction)
        .help(Strings.closePlayer)
      }
    }
  }
}
