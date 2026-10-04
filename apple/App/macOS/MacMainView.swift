import SubtubeCore
import SwiftUI

/// macOS: channels in the sidebar, the feed grid in the detail, the selected
/// channel's filters in the inspector; the player takes over the window.
struct PlatformMainView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if let session = feed.player {
        MacPlayerScreen(session: session, feed: feed)
      } else {
        MacFeedSplitView(app: app, feed: feed)
      }
    }
    .onAppear(perform: feed.appeared)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        feed.appeared()
      } else {
        Task { await feed.flush() }
      }
    }
  }
}

private struct MacFeedSplitView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @State private var showInspector: Bool

  init(app: AppModel, feed: FeedModel) {
    self.app = app
    self.feed = feed
    _showInspector = State(initialValue: feed.selectedChannel != nil)
  }

  var body: some View {
    NavigationSplitView {
      MacSidebar(feed: feed)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
    } detail: {
      MacFeedGrid(app: app, feed: feed)
        .inspector(isPresented: $showInspector) {
          Group {
            if let channelId = feed.selectedChannel {
              FilterForm(feed: feed, channelId: channelId)
            } else {
              Text(Strings.noChannelSelected)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
          .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
          .accessibilityLabel(
            feed.selectedChannel.flatMap(feed.channel).map { Strings.filtersFor($0.title) }
              ?? Strings.inspector)
        }
        .toolbar {
          MacFeedToolbar(feed: feed, showInspector: $showInspector)
        }
    }
  }
}

/// Feed with its unwatched count, then every channel.
private struct MacSidebar: View {
  @Bindable var feed: FeedModel

  private enum Row: Hashable {
    case feed
    case channel(String)
  }

  /// When the selection last moved, to tell a click on the row already
  /// selected from the click that selected it.
  @State private var selectionMovedAt = Date.distantPast

  private var selection: Binding<Row?> {
    Binding(
      get: { feed.selectedChannel.map(Row.channel) ?? .feed },
      set: { row in
        if row != feed.selectedChannel.map(Row.channel) ?? .feed {
          selectionMovedAt = Date()
        }
        switch row {
        case .channel(let channelId): feed.selectedChannel = channelId
        case .feed, nil: feed.selectedChannel = nil
        }
      })
  }

  /// Clicking the row already showing refreshes it. The list reports no
  /// selection change for that click, so the row watches for it itself.
  private func refreshOnReclick(_ row: Row) -> some Gesture {
    TapGesture().onEnded {
      if selection.wrappedValue == row && Date().timeIntervalSince(selectionMovedAt) > 0.5 {
        feed.refresh()
      }
    }
  }

  var body: some View {
    let selected = selection.wrappedValue
    List(selection: selection) {
      Label {
        HStack {
          Text(Strings.feed)
          Spacer()
          let count = feed.unwatchedCount
          if count > 0 {
            Text("\(count)")
              .font(.caption.weight(.semibold))
              .accessibilityLabel(Strings.unwatchedCount(count))
          }
        }
      } icon: {
        Image(systemName: "tray")
          .foregroundStyle(selected == .feed ? Color.ink : Color.gold)
      }
      .foregroundStyle(selected == .feed ? Color.ink : Color.primary)
      .contentShape(Rectangle())
      .simultaneousGesture(refreshOnReclick(.feed))
      .tag(Row.feed)
      Section(Strings.channels) {
        ForEach(feed.orderedChannels, id: \.channelId) { channel in
          let isSelected = selected == .channel(channel.channelId)
          Label {
            Text(channel.title)
          } icon: {
            Avatar(url: channel.thumbnail, title: channel.title)
          }
          .foregroundStyle(isSelected ? Color.ink : Color.primary)
          .opacity(channel.enabled ? 1 : 0.45)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .simultaneousGesture(refreshOnReclick(.channel(channel.channelId)))
          .tag(Row.channel(channel.channelId))
        }
      }
    }
  }
}

private struct MacFeedToolbar: ToolbarContent {
  @Bindable var feed: FeedModel
  @Binding var showInspector: Bool

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        feed.hideWatched.toggle()
      } label: {
        Label(Strings.hideWatched, systemImage: feed.hideWatched ? "eye.slash" : "eye")
      }
      .help(Strings.hideWatched)
      .accessibilityAddTraits(feed.hideWatched ? .isSelected : [])
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        showInspector.toggle()
      } label: {
        Label(showInspector ? Strings.hideInspector : Strings.showInspector, systemImage: "sidebar.right")
      }
      .help(showInspector ? Strings.hideInspector : Strings.showInspector)
    }
  }
}

/// The feed or a channel page as a grid of cards.
private struct MacFeedGrid: View {
  let app: AppModel
  let feed: FeedModel

  private var title: String {
    feed.selectedChannel.flatMap(feed.channel)?.title ?? Strings.feed
  }

  private var subtitle: String {
    if feed.selectedChannel != nil {
      return ""
    } else {
      return Strings.videoCount(feed.shown.count)
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        FeedBanners(feed: feed, app: app)
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)],
          alignment: .leading, spacing: 18
        ) {
          ForEach(feed.shown) { item in
            ItemCard(
              item: item,
              watched: feed.watched.contains(item.id),
              onOpen: { feed.open(item) },
              onOpenChannel: { feed.selectedChannel = item.channelId },
              onToggleWatched: { feed.toggleWatched(item) }
            )
          }
        }
        .loadingDimmed(feed.loading)
        FeedEmptyState(feed: feed)
      }
      .padding(20)
    }
    .navigationTitle(title)
    .navigationSubtitle(subtitle)
  }
}
