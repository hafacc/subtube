import SubtubeCore
import SwiftUI

/// macOS: channels in the sidebar, the headed feed grid in the detail, a channel's
/// filters in the inspector, opened from its sidebar row; the player lies over the dimmed app,
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
      } else if phase == .background {
        // not on `.inactive`: the window only lost the focus, and a video goes on playing
        Task { await feed.leftForeground() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
      _ in feed.quitting()
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
    _showInspector = State(initialValue: false)
    #if DEBUG
      if CommandLine.arguments.contains("-filters") && feed.selectedChannel != nil {
        _showInspector = State(initialValue: true)
      }
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

  /// The channel whose filters the details panel shows.
  private var filtersChannel: String? {
    showInspector && groupTarget == nil ? feed.selectedChannel : nil
  }

  /// Open the details panel on a channel's filters, on that channel's page,
  /// or close it when it already shows them.
  private func toggleFilters(_ channelId: String) {
    if filtersChannel == channelId {
      showInspector = false
    } else {
      // the filters take the panel from the group editor
      groupTarget = nil
      feed.selectedChannel = channelId
      showInspector = true
    }
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columns) {
      MacSidebar(feed: feed, filtersChannel: filtersChannel, onFilters: toggleFilters)
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
            } else if let channel = feed.selectedChannel.flatMap(feed.channel) {
              MacFiltersPanel(feed: feed, channel: channel) { showInspector = false }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .background(Color.page.ignoresSafeArea())
          .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { inspectorWidth = $0 }
          .accessibilityLabel(
            groupTarget != nil
              ? (groupTarget == .new ? Strings.newGroup : Strings.editGroup)
              : feed.selectedChannel.flatMap(feed.channel).map { Strings.filtersFor($0.title) }
                ?? Strings.inspector)
          .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .onChange(of: feed.selectedChannel) { _, channelId in
          closeGroupEditor()
          if channelId == nil {
            showInspector = false
          }
        }
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

/// A channel's filters in the details panel, under a header: the channel's
/// avatar, its name over where it comes from, and the × that closes the
/// panel.
private struct MacFiltersPanel: View {
  let feed: FeedModel
  let channel: ChannelFilter
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Avatar(url: channel.thumbnail, title: channel.title, size: 36)
        VStack(alignment: .leading, spacing: 1) {
          Text(channel.title)
            .font(.title3.bold())
            .lineLimit(1)
          Text(
            feed.isFollowedOnly(channel.channelId)
              ? Strings.summaryFollowed : Strings.subscribedOnYouTube
          )
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
        }
        Spacer(minLength: 8)
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .frame(width: 24, height: 24)
            .overlay { Circle().strokeBorder(Color.secondary.opacity(0.35)) }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.close)
        .help(Strings.close)
      }
      .padding(.horizontal, panelInset)
      .padding(.top, 14)
      .padding(.bottom, 12)
      FilterForm(feed: feed, channelId: channel.channelId)
    }
  }
}

/// Opens a channel's filters from its sidebar row; drawn only while `shown`.
private struct RowFiltersButton: View {
  let title: String
  let isSelected: Bool
  let shown: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "line.3.horizontal.decrease")
        .foregroundStyle(isSelected ? Color.ink : Color.secondary)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(Strings.filters)
    .accessibilityLabel(Strings.filtersFor(title))
    .opacity(shown ? 1 : 0)
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

/// Feed with its unwatched count, then every channel, newest unwatched
/// video first:
/// its avatar, its name and under that how many videos are unwatched, or
/// "Off".
///
/// The rows are drawn here, not by a list, so the selected one is Sunflower
/// whatever the system's accent is. Clicking the row already showing
/// refreshes it. With the keyboard on the sidebar, the up and down arrows
/// move the selection.
private struct MacSidebar: View {
  @Bindable var feed: FeedModel
  /// The channel whose filters the details panel shows.
  let filtersChannel: String?
  /// Opens a channel's filters, or closes them when they show.
  let onFilters: (String) -> Void
  /// The row the pointer is over.
  @State private var hovered: Row?
  @FocusState private var isFocused: Bool

  private enum Row: Hashable {
    case feed
    case channel(String)
  }

  private var selected: Row {
    feed.selectedChannel.map(Row.channel) ?? .feed
  }

  private func select(_ row: Row) {
    switch row {
    case .feed: feed.selectedChannel = nil
    case .channel(let channelId): feed.selectedChannel = channelId
    }
  }

  private func press(_ row: Row) {
    isFocused = true
    if row == selected {
      feed.refresh()
    } else {
      select(row)
    }
  }

  /// Move the selection by `offset` rows.
  private func step(_ offset: Int) -> KeyPress.Result {
    let rows = [Row.feed] + feed.orderedChannels.map { Row.channel($0.channelId) }
    if let index = rows.firstIndex(of: selected), rows.indices.contains(index + offset) {
      select(rows[index + offset])
    }
    return .handled
  }

  /// What a channel's row says under its name; nil for nothing unwatched.
  private func detail(_ channel: ChannelFilter) -> String? {
    let count = feed.unwatchedByChannel[channel.channelId] ?? 0
    if !channel.enabled {
      return Strings.summaryOff
    } else if count > 0 {
      return Strings.unwatchedCount(count)
    } else {
      return nil
    }
  }

  /// A row's box: its fill when selected or under the pointer, and the
  /// press that selects or refreshes it, on `label` only.
  private func row<Label: View, Trailing: View>(
    _ row: Row, height: CGFloat, @ViewBuilder label: () -> Label,
    @ViewBuilder trailing: () -> Trailing = { EmptyView() }
  ) -> some View {
    let isSelected = row == selected
    return HStack(spacing: 6) {
      label()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { press(row) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { press(row) }
      trailing()
    }
    .padding(.horizontal, 8)
    .frame(height: height)
    .foregroundStyle(isSelected ? Color.ink : Color.primary)
    .background(
      isSelected ? Color.sunflower : hovered == row ? Color.hoverFill : Color.clear,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .onHover { isOver in
      if isOver {
        hovered = row
      } else if hovered == row {
        hovered = nil
      }
    }
    .id(row)
  }

  private var feedRow: some View {
    row(.feed, height: 30) {
      HStack(spacing: 8) {
        Image(systemName: "tray")
          .foregroundStyle(selected == .feed ? Color.ink : Color.gold)
          .frame(width: 26)
        Text(Strings.feed)
        Spacer(minLength: 0)
        UnwatchedBadge(count: feed.unwatchedCount)
      }
    }
  }

  private func channelRow(_ channel: ChannelFilter) -> some View {
    let isSelected = selected == .channel(channel.channelId)
    return row(.channel(channel.channelId), height: 44) {
      HStack(spacing: 8) {
        Avatar(url: channel.thumbnail, title: channel.title, size: 26)
        VStack(alignment: .leading, spacing: 1) {
          Text(channel.title)
            .fontWeight(.medium)
            .lineLimit(1)
          if let detail = detail(channel) {
            Text(detail)
              .font(.subheadline)
              .foregroundStyle(isSelected ? Color.ink : Color.secondary)
              .lineLimit(1)
          }
        }
      }
      .opacity(channel.enabled ? 1 : offChannelOpacity)
    } trailing: {
      RowFiltersButton(
        title: channel.title, isSelected: isSelected,
        shown: isSelected || hovered == .channel(channel.channelId)
      ) {
        onFilters(channel.channelId)
      }
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          feedRow
          Text(Strings.channels)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .padding(.leading, 8)
            .padding(.top, 14)
            .padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)
          ForEach(feed.orderedChannels, id: \.channelId) { channel in
            channelRow(channel)
          }
          YouTubeAttribution()
            .padding(.horizontal, 6)
            .padding(.top, 18)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
      }
      .onChange(of: selected) { _, row in proxy.scrollTo(row) }
    }
    .focusable(interactions: .edit)
    .focused($isFocused)
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { step(-1) }
    .onKeyPress(.downArrow) { step(1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Strings.channels)
    // the sidebar never leaves the screen, so these stand in for its appearing
    .onAppear(perform: feed.reorderChannels)
    .onChange(of: feed.selectedChannel) { feed.reorderChannels() }
    .onChange(of: feed.player == nil) { feed.reorderChannels() }
  }
}

/// What heads a page, in the toolbar title's place: the name, large, with
/// the pencil "Edit Group" and the × "Clear" after it while chips are
/// selected, over the video count.
private struct MacPageHeading: View {
  let feed: FeedModel
  let title: String
  /// Opens the group editor.
  let onGroup: (GroupTarget) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        Text(title)
          .font(.largeTitle.bold())
          .lineLimit(1)
          .truncationMode(.tail)
          .accessibilityAddTraits(.isHeader)
        ChipTitleButtons(
          title: feed.feedTitle, onEdit: { onGroup(.existing($0)) }, onClear: feed.clearFeedChips
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
      }
      Text(Strings.videoCount(feed.shown.count))
        .font(.callout)
        .foregroundStyle(.secondary)
        // a count of the stand-in cards would be none
        .opacity(feed.showsSkeletons ? 0 : 1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A page with nothing to show: a Sunflower disk with a check mark, what
/// the grid would say as a heading, and "Refresh".
private struct MacEmptyState: View {
  let feed: FeedModel

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "checkmark")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(Color.ink)
        .frame(width: 64, height: 64)
        .background(Color.sunflower, in: Circle())
        .accessibilityHidden(true)
      Text(feed.emptyText)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      Button(Strings.refresh, action: feed.refresh)
        .controlSize(.large)
    }
  }
}

/// Fades a scrolling page out over its top edge once it is scrolled, where
/// it meets the heading with no line between.
private struct ScrollTopFade: ViewModifier {
  @State private var scrolled = false
  private static let height: CGFloat = 16

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top > 1
      } action: { _, now in
        scrolled = now
      }
      .mask {
        VStack(spacing: 0) {
          LinearGradient(
            colors: [.black.opacity(scrolled ? 0 : 1), .black], startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: Self.height)
          Color.black
        }
        // the room kept for the minimized player is a safe area inset the cards scroll through
        .ignoresSafeArea(edges: .bottom)
      }
      .animation(.easeOut(duration: 0.15), value: scrolled)
  }
}

/// The feed or a channel page: its heading and the chips, which stay in
/// place, over a scrolling grid of cards, or the empty state centered.
private struct MacFeedGrid: View {
  let app: AppModel
  let feed: FeedModel
  /// Opens the group editor.
  let onGroup: (GroupTarget) -> Void

  /// The page's and the window's title: the channel's name, or the feed's
  /// selected names.
  private var title: String {
    let selected = feed.feedTitle
    return feed.selectedChannel.flatMap(feed.channel)?.title
      ?? (selected.names.isEmpty ? Strings.feed : selected.text)
  }

  /// The space beside the heading, the chips and the cards.
  private static let margin: CGFloat = 20

  private var showsEmptyState: Bool {
    feed.shown.isEmpty && !feed.showsSkeletons && feed.error == nil
  }

  /// The card drawn as under the pointer, for pictures.
  private var cardShownHovered: String? {
    #if DEBUG
      debugArgument("cardHover").flatMap(Int.init).flatMap { index in
        feed.shown.indices.contains(index) ? feed.shown[index].id : nil
      }
    #else
      nil
    #endif
  }

  private var cards: some View {
    ScrollView {
      VStack(spacing: 16) {
        if feed.error != nil || feed.notice != nil {
          FeedBanners(feed: feed, app: app)
        }
        LazyVGrid(columns: feedGridColumns, alignment: .leading, spacing: 18) {
          let hovered = cardShownHovered
          ForEach(feed.shown) { item in
            ItemCard(
              item: item,
              feed: feed,
              onOpenChannel: { feed.selectedChannel = item.channelId },
              showsAvatar: feed.selectedChannel == nil,
              asHovered: item.id == hovered
            )
          }
        }
        .loadingDimmed(feed.loading)
        FeedEmptyState(feed: feed)
        if !feed.showsSkeletons {
          YouTubeAttribution().padding(.top, 8)
        }
      }
      .padding(.horizontal, Self.margin)
      .padding(.top, 12)
      .padding(.bottom, Self.margin)
    }
    .modifier(ScrollTopFade())
    .minimizedPlayerRoom(feed)
  }

  private var emptyPage: some View {
    VStack(spacing: 0) {
      if feed.notice != nil {
        FeedBanners(feed: feed, app: app)
      }
      Spacer(minLength: 0)
      MacEmptyState(feed: feed)
      Spacer(minLength: 0)
      YouTubeAttribution()
    }
    .padding(Self.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var body: some View {
    VStack(spacing: 0) {
      MacPageHeading(feed: feed, title: title, onGroup: onGroup)
        .padding(.horizontal, Self.margin)
        .padding(.top, 4)
      FeedChipRow(feed: feed, inset: Self.margin, onNewGroup: { onGroup(.new) })
      if showsEmptyState {
        emptyPage
      } else {
        cards
      }
    }
    .overlay(alignment: .top) {
      LoadProgressBar(feed: feed)
    }
    // kept for the Window menu and Mission Control; the page shows it itself
    .navigationTitle(title)
    .toolbar(removing: .title)
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
  }
}
