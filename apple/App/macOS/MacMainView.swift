import SubtubeCore
import SwiftUI

/// macOS: channels in the sidebar, the feed grid in the detail, the selected
/// channel's filters in the inspector; the player lies over the dimmed app,
/// or minimized in the window's bottom trailing corner with the app in use
/// behind it.
struct PlatformMainView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @Environment(\.scenePhase) private var scenePhase
  /// The width the details panel takes at the trailing edge; 0 when closed.
  @State private var panelWidth: CGFloat = 0
  #if DEBUG
    @Environment(\.openSettings) private var openSettings
  #endif

  var body: some View {
    ZStack {
      MacFeedSplitView(app: app, feed: feed, panelWidth: $panelWidth)
        .accessibilityHidden(feed.player?.place == .large)
      if let session = feed.player {
        MacPlayerOverlay(session: session, feed: feed, panelWidth: panelWidth)
      }
    }
    // per feed, not per view: a feed made anew while this view stays must load too
    .task(id: ObjectIdentifier(feed)) { feed.appeared() }
    #if DEBUG
      .task {
        if CommandLine.arguments.contains("-settings") {
          openSettings()
        }
      }
    #endif
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        feed.appeared()
      } else {
        Task { await feed.leftForeground() }
      }
    }
  }
}

/// The one player, large or minimized.
///
/// Large, it is the video as big as fits over the dimmed app, with room
/// kept above it for the frame's bar; a click on the dimmed area or Escape
/// minimizes it. Minimized, it is 356 by 200 in the window's bottom
/// trailing corner, beside the details panel when that is open, and the app
/// behind it is in use. One view draws both, so the web view never moves to
/// another parent. The frame shows while the pointer is over the video or
/// the frame.
private struct MacPlayerOverlay: View {
  let session: PlayerSession
  let feed: FeedModel
  let panelWidth: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let isLarge = session.place == .large
    GeometryReader { proxy in
      // sized by the whole window; the details panel only moves it over
      let small = minimizedPlayerSize(viewWidth: proxy.size.width)
      let size =
        isLarge
        ? largePlayerSize(
          viewWidth: proxy.size.width, viewHeight: proxy.size.height,
          barHeight: PlayerFrame.barHeight)
        : small
      ZStack(alignment: isLarge ? .center : .bottomTrailing) {
        if isLarge {
          Button(action: feed.minimize) {
            Color.black.opacity(0.6).ignoresSafeArea()
          }
          .buttonStyle(.plain)
          .keyboardShortcut(.cancelAction)
          .accessibilityLabel(Strings.minimize)
          .transition(.opacity)
        }
        YouTubePlayerView(session: session, feed: feed, onExpand: feed.enlarge)
          .frame(width: size.width, height: size.height)
          .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(.black)
              .shadow(color: .black.opacity(0.35), radius: isLarge ? 32 : 12, y: isLarge ? 16 : 4)
          }
          // room for the frame's bar, so the pointer over it still counts as over the player
          .padding(.top, PlayerFrame.barHeight)
          .onHover { session.showsFrame = $0 }
          .padding(.trailing, isLarge ? 0 : minimizedPlayerMargin + panelWidth)
          .padding(.bottom, isLarge ? 0 : minimizedPlayerMargin)
      }
      .frame(
        maxWidth: .infinity, maxHeight: .infinity, alignment: isLarge ? .center : .bottomTrailing)
    }
    // the one holder moves and grows: the web view stays where it is in it
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isLarge)
  }
}

private struct MacFeedSplitView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  /// The width the details panel takes; 0 when closed.
  @Binding var panelWidth: CGFloat
  /// The details panel's width as last laid out.
  @State private var inspectorWidth: CGFloat = 0
  @State private var showInspector: Bool
  @State private var columns = NavigationSplitViewVisibility.automatic
  /// The group the details panel edits, in place of a channel's filters.
  @State private var groupTarget: GroupTarget?
  /// Whether the details panel was open before the group editor took it.
  @State private var inspectorBefore = false

  init(app: AppModel, feed: FeedModel, panelWidth: Binding<CGFloat>) {
    self.app = app
    self.feed = feed
    _panelWidth = panelWidth
    _showInspector = State(initialValue: feed.selectedChannel != nil)
    #if DEBUG
      if CommandLine.arguments.contains("-sidebarCollapsed") {
        _columns = State(initialValue: .detailOnly)
      }
      if CommandLine.arguments.contains("-newGroup") {
        _groupTarget = State(initialValue: .new)
        _showInspector = State(initialValue: true)
      } else if let group = debugArgument("editGroup") {
        _groupTarget = State(initialValue: .existing(group))
        _showInspector = State(initialValue: true)
      }
    #endif
  }

  /// Open the group editor in the details panel, in place of what it shows.
  private func editGroup(_ target: GroupTarget) {
    if groupTarget == nil {
      inspectorBefore = showInspector
    }
    groupTarget = target
    showInspector = true
  }

  /// Drop the group editor's draft and give the panel back.
  private func closeGroupEditor() {
    if groupTarget != nil {
      groupTarget = nil
      showInspector = inspectorBefore
    }
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columns) {
      MacSidebar(feed: feed)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
          // at the sidebar's trailing edge, where the system's own button sits
          if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
          }
          ToolbarItem { ChannelsButton(columns: $columns) }
        }
    } detail: {
      MacFeedGrid(app: app, feed: feed, onGroup: editGroup)
        .inspector(isPresented: $showInspector) {
          Group {
            if let groupTarget {
              GroupEditor(feed: feed, target: groupTarget, onClose: closeGroupEditor)
                .id(groupTarget)
            } else if let channelId = feed.selectedChannel {
              FilterForm(feed: feed, channelId: channelId)
            } else {
              Text(Strings.noChannelSelected)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
          .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { inspectorWidth = $0 }
          .accessibilityLabel(
            groupTarget != nil
              ? (groupTarget == .new ? Strings.newGroup : Strings.editGroup)
              : feed.selectedChannel.flatMap(feed.channel).map { Strings.filtersFor($0.title) }
                ?? Strings.inspector)
          .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
          MacFeedToolbar(
            feed: feed, showInspector: $showInspector, groupTarget: $groupTarget,
            onGroup: editGroup)
        }
        .onChange(of: feed.selectedChannel) { closeGroupEditor() }
        .onChange(of: showInspector) { _, shown in
          if !shown {
            groupTarget = nil
          }
        }
        .onChange(of: showInspector ? inspectorWidth : 0, initial: true) { _, width in
          panelWidth = width
        }
    }
  }
}

/// Shows or hides the sidebar, drawn as what the sidebar holds.
private struct ChannelsButton: View {
  @Binding var columns: NavigationSplitViewVisibility

  private var isCollapsed: Bool {
    columns == .detailOnly
  }

  var body: some View {
    let title = isCollapsed ? Strings.showChannels : Strings.hideChannels
    Button {
      withAnimation {
        columns = isCollapsed ? .all : .detailOnly
      }
    } label: {
      Label(title, systemImage: "play.square.stack")
    }
    .help(title)
  }
}

/// Feed with its unwatched count, then every channel, newest video first.
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
          UnwatchedBadge(count: feed.unwatchedCount)
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
            HStack {
              Text(channel.title)
              Spacer()
              UnwatchedCount(channel: channel, feed: feed)
            }
          } icon: {
            Avatar(url: channel.thumbnail, title: channel.title)
          }
          .foregroundStyle(isSelected ? Color.ink : Color.primary)
          .opacity(channel.enabled ? 1 : offChannelOpacity)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .simultaneousGesture(refreshOnReclick(.channel(channel.channelId)))
          .tag(Row.channel(channel.channelId))
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
  @Binding var groupTarget: GroupTarget?
  /// Opens the group editor.
  let onGroup: (GroupTarget) -> Void

  /// Whether the panel shows what the button is for: a channel's filters.
  private var showsFilters: Bool {
    showInspector && groupTarget == nil
  }

  /// The names in the system title's place, over the count its subtitle
  /// held: removing the title takes the subtitle with it.
  private func names(_ title: ChipTitle) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(feed.selectedChannel.flatMap(feed.channel)?.title ?? title.text)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
      if feed.selectedChannel == nil {
        Text(Strings.videoCount(feed.shown.count))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: 360, alignment: .leading)
  }

  var body: some ToolbarContent {
    let title = feed.feedTitle
    if !title.names.isEmpty {
      // ahead of the system title's place, which the names take
      if #available(macOS 26.0, *) {
        ToolbarItem(placement: .navigation) { names(title) }
          .sharedBackgroundVisibility(.hidden)
      } else {
        ToolbarItem(placement: .navigation) { names(title) }
      }
      ToolbarItemGroup(placement: .navigation) {
        ChipTitleButtons(
          title: title, onEdit: { onGroup(.existing($0)) }, onClear: feed.clearFeedChips)
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        if groupTarget != nil {
          // the filters take the panel from the group editor
          groupTarget = nil
        } else {
          showInspector.toggle()
        }
      } label: {
        Label(
          showsFilters ? Strings.hideInspector : Strings.showInspector,
          systemImage: "line.3.horizontal.decrease")
      }
      .help(showsFilters ? Strings.hideInspector : Strings.showInspector)
    }
  }
}

/// The feed or a channel page: the chips, then a grid of cards.
private struct MacFeedGrid: View {
  let app: AppModel
  let feed: FeedModel
  /// Opens the group editor.
  let onGroup: (GroupTarget) -> Void

  /// The window's title: the channel's name, or the feed's selected names.
  private var title: String {
    let selected = feed.feedTitle
    return feed.selectedChannel.flatMap(feed.channel)?.title
      ?? (selected.names.isEmpty ? Strings.feed : selected.text)
  }

  /// The space beside the chips and around the cards, which puts both under
  /// the window's title.
  private static let margin: CGFloat = 20

  private var subtitle: String {
    if feed.selectedChannel != nil {
      return ""
    } else {
      return Strings.videoCount(feed.shown.count)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      FeedChipRow(feed: feed, inset: Self.margin, onNewGroup: { onGroup(.new) })
      Divider()
      ScrollView {
        VStack(spacing: 16) {
          if feed.error != nil || feed.notice != nil {
            FeedBanners(feed: feed, app: app)
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)],
            alignment: .leading, spacing: 18
          ) {
            ForEach(feed.shown) { item in
              ItemCard(
                item: item,
                watched: feed.watched.contains(item.id),
                progress: feed.bars[item.id],
                feed: feed,
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
        .padding(Self.margin)
      }
      .minimizedPlayerRoom(feed)
    }
    .overlay(alignment: .top) {
      LoadProgressBar(progress: feed.loadProgress)
    }
    .navigationTitle(title)
    // the toolbar item that shows the names draws the count itself
    .navigationSubtitle(feed.feedTitle.names.isEmpty ? subtitle : "")
    .toolbar(removing: feed.feedTitle.names.isEmpty ? nil : .title)
  }
}
