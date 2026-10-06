import SubtubeCore
import SwiftUI

/// macOS: channels in the sidebar, the feed grid in the detail, the selected
/// channel's filters in the inspector; the player lies over the dimmed app.
struct PlatformMainView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack {
      MacFeedSplitView(app: app, feed: feed)
        .accessibilityHidden(feed.player != nil)
      if let session = feed.player {
        MacPlayerOverlay(session: session, feed: feed)
      }
    }
    .onAppear(perform: feed.appeared)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        feed.appeared()
      } else {
        Task { await feed.leftForeground() }
      }
    }
  }
}

/// Nothing but the video, as large as fits, over the dimmed app. A click on
/// the dimmed area or Escape closes it.
private struct MacPlayerOverlay: View {
  let session: PlayerSession
  let feed: FeedModel

  var body: some View {
    ZStack {
      Color.black.opacity(0.6)
        .ignoresSafeArea()
        .onTapGesture { feed.player = nil }
      YouTubePlayerView(session: session)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(radius: 32, y: 16)
        .padding(32)
        .accessibilityLabel(session.item.title.isEmpty ? Strings.player : session.item.title)
    }
    .background {
      // not hidden(): a hidden button's shortcut doesn't fire
      Button(Strings.cancel) { feed.player = nil }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .accessibilityHidden(true)
    }
  }
}

private struct MacFeedSplitView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @State private var showInspector: Bool
  @State private var columns = NavigationSplitViewVisibility.automatic

  init(app: AppModel, feed: FeedModel) {
    self.app = app
    self.feed = feed
    _showInspector = State(initialValue: feed.selectedChannel != nil)
    #if DEBUG
      if CommandLine.arguments.contains("-sidebarCollapsed") {
        _columns = State(initialValue: .detailOnly)
      }
    #endif
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columns) {
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
      Section {
        ForEach(feed.orderedChannels, id: \.channelId) { channel in
          let isSelected = selected == .channel(channel.channelId)
          Label {
            HStack {
              Text(channel.title)
              Spacer()
              UnwatchedCount(channel: channel, feed: feed)
            }
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
        if feed.explainsNoChannels && feed.orderedChannels.isEmpty {
          NoChannelsForFilter()
            .padding(.vertical, 24)
        }
      } header: {
        VStack(alignment: .leading, spacing: 0) {
          Text(Strings.channels)
          ChannelChipRow(feed: feed, inset: 0)
        }
      }
    }
    .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
      YouTubeAttribution()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    // the sidebar never leaves the screen, so these stand in for its appearing
    .onAppear(perform: feed.reorderChannels)
    .onChange(of: feed.selectedChannel) { feed.reorderChannels() }
    .onChange(of: feed.player == nil) { feed.reorderChannels() }
  }
}

private struct MacFeedToolbar: ToolbarContent {
  @Bindable var feed: FeedModel
  @Binding var showInspector: Bool

  var body: some ToolbarContent {
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

/// The feed or a channel page: the chips, then a grid of cards.
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
    VStack(spacing: 0) {
      FeedChipRow(feed: feed)
      Divider()
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
                progress: feed.bars[item.id],
                onOpen: { feed.open(item) },
                onOpenChannel: { feed.selectedChannel = item.channelId }
              )
            }
          }
          .loadingDimmed(feed.loading)
          FeedEmptyState(feed: feed)
          if !feed.showsSkeletons {
            YouTubeAttribution().padding(.top, 8)
          }
        }
        .padding(20)
      }
    }
    .overlay(alignment: .top) {
      LoadProgressBar(progress: feed.loadProgress)
    }
    .navigationTitle(title)
    .navigationSubtitle(subtitle)
  }
}
