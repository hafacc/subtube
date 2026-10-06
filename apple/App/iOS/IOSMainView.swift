import SubtubeCore
import SwiftUI

/// iOS: Feed, Channels and Settings tabs; a card plays in place, and its
/// player moves to the bottom trailing corner, over the tab bar, when the
/// card is scrolled away or the page changes.
struct PlatformMainView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab = MainTab.feed
  @State private var feedPath: [ChannelRoute] = []
  @State private var channelsPath: [ChannelRoute] = []
  /// Counts taps on the Feed tab while the feed shows.
  @State private var feedTopTaps = 0
  /// The group the editor sheet is open for.
  @State private var groupTarget: GroupTarget?
  /// Where the playing card was started: what "Expand" goes back to.
  @State private var playerOrigin: Place?
  /// The bottom safe area inside a tab, which the tab bar is part of.
  @State private var tabBottomInset: CGFloat = 0

  /// A tab and what is pushed in the two tabs that push.
  private struct Place: Equatable {
    var tab: MainTab
    var feedPath: [ChannelRoute]
    var channelsPath: [ChannelRoute]
  }

  private var place: Place {
    Place(tab: tab, feedPath: feedPath, channelsPath: channelsPath)
  }

  /// "Expand": back to where the card was started and into the card. When
  /// that page no longer lists the item nothing happens: a phone has no
  /// large player to show it in.
  private func expand() {
    if let playerOrigin, feed.cardIsListed {
      tab = playerOrigin.tab
      feedPath = playerOrigin.feedPath
      channelsPath = playerOrigin.channelsPath
      // not left to the change handlers below, which run after this
      feed.selectedChannel = openChannel
      feed.expandToCard()
    }
  }

  /// The channel page on top of the tab in front, if any.
  private var openChannel: String? {
    switch tab {
    case .feed: feedPath.last?.channelId
    case .channels: channelsPath.last?.channelId
    case .settings: nil
    }
  }

  private enum MainTab: String {
    case feed
    case channels
    case settings
  }

  /// The tab in front; tapping Feed while the feed itself is showing scrolls
  /// it to the top and refreshes.
  private var tabSelection: Binding<MainTab> {
    Binding(
      get: { tab },
      set: { tapped in
        if tapped == .feed && tab == .feed && feedPath.isEmpty {
          feedTopTaps += 1
          feed.refresh()
        }
        tab = tapped
      })
  }

  var body: some View {
    TabView(selection: tabSelection) {
      Tab(Strings.feed, systemImage: "rectangle.stack", value: MainTab.feed) {
        IOSFeedTab(
          app: app, feed: feed, path: $feedPath, scrollToTop: feedTopTaps,
          onGroup: { groupTarget = $0 }
        )
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
          tabBottomInset = $0
        }
      }
      Tab(Strings.channels, systemImage: "slider.horizontal.3", value: MainTab.channels) {
        IOSChannelsTab(app: app, feed: feed, path: $channelsPath, onGroup: { groupTarget = $0 })
      }
      Tab(Strings.settings, systemImage: "gearshape", value: MainTab.settings) {
        IOSSettingsTab(app: app, feed: feed)
      }
    }
    .overlay {
      GeometryReader { proxy in
        if let session = feed.player, session.place == .minimized {
          let size = minimizedPlayerSize(viewWidth: proxy.size.width)
          YouTubePlayerView(session: session, feed: feed, onExpand: expand)
            .frame(width: size.width, height: size.height)
            .background {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            }
            .padding(.trailing, minimizedPlayerMargin)
            .padding(
              .bottom,
              max(0, tabBottomInset - proxy.safeAreaInsets.bottom) + minimizedPlayerMargin
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
      }
    }
    .onChange(of: openChannel) { _, channelId in
      feed.selectedChannel = channelId
    }
    .onChange(of: place) { _, new in
      // "Expand" comes back here with the player already in its card
      if new != playerOrigin {
        feed.minimizeCard()
      }
    }
    .onChange(of: feed.playStarts, initial: true) {
      if feed.player != nil {
        playerOrigin = place
      }
    }
    .sheet(item: $groupTarget) { target in
      GroupEditor(feed: feed, target: target, onClose: { groupTarget = nil })
    }
    // per feed, not per view: a feed made anew while this view stays must load too
    .task(id: ObjectIdentifier(feed)) { feed.appeared() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        feed.appeared()
      } else if phase == .background {
        // asks for the time the upload needs before the app is suspended
        let application = UIApplication.shared
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = application.beginBackgroundTask {
          application.endBackgroundTask(assertion)
        }
        Task {
          await feed.leftForeground()
          application.endBackgroundTask(assertion)
        }
      }
    }
    #if DEBUG
      .onAppear {
        if let forced = debugArgument("tab").flatMap(MainTab.init(rawValue:)) {
          tab = forced
        }
        if let seconds = debugArgument("expandAfter").flatMap(Double.init) {
          Task {
            try? await Task.sleep(for: .seconds(seconds))
            expand()
          }
        }
        if CommandLine.arguments.contains("-newGroup") {
          groupTarget = .new
        } else if let group = debugArgument("editGroup") {
          groupTarget = .existing(group)
        }
      }
    #endif
  }
}

/// A channel page pushed from the feed or the channels list.
private struct ChannelRoute: Hashable {
  let channelId: String
}

/// One channel's cards, with its filters a sheet away.
private struct IOSChannelPage: View {
  let app: AppModel
  let feed: FeedModel
  let channelId: String
  @State private var editingFilters = false

  var body: some View {
    IOSFeedList(app: app, feed: feed, openChannel: { _ in }, onNewGroup: {})
      .navigationTitle(feed.channel(channelId)?.title ?? "")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          if feed.selectedChannel == channelId {
            ChipTitleButtons(title: feed.feedTitle, onEdit: { _ in }, onClear: feed.clearFeedChips)
          }
          Button {
            editingFilters = true
          } label: {
            Label(Strings.filters, systemImage: "line.3.horizontal.decrease.circle")
          }
        }
      }
      .sheet(isPresented: $editingFilters) {
        IOSFilterSheet(feed: feed, channelId: channelId)
      }
      #if DEBUG
        .onAppear {
          if CommandLine.arguments.contains("-filter:\(channelId)") {
            editingFilters = true
          }
        }
      #endif
  }
}

private struct IOSFeedTab: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @Binding var path: [ChannelRoute]
  let scrollToTop: Int
  /// Opens the group editor.
  let onGroup: (GroupTarget) -> Void

  /// The feed's selected names; none while a channel's page covers it.
  private var title: ChipTitle {
    feed.selectedChannel == nil ? feed.feedTitle : ChipTitle()
  }

  var body: some View {
    NavigationStack(path: $path) {
      IOSFeedList(
        app: app, feed: feed, openChannel: { path.append(ChannelRoute(channelId: $0)) },
        onNewGroup: { onGroup(.new) }, scrollToTop: scrollToTop
      )
        .chipTitle(title, usual: Strings.feed, onEdit: { onGroup(.existing($0)) },
          onClear: feed.clearFeedChips)
        .navigationDestination(for: ChannelRoute.self) { route in
          IOSChannelPage(app: app, feed: feed, channelId: route.channelId)
        }
    }
  }
}

/// The feed (or the selected channel's page): the chips, then a column of
/// big cards, one of which may be playing in place.
private struct IOSFeedList: View {
  let app: AppModel
  let feed: FeedModel
  let openChannel: (String) -> Void
  /// Opens the editor for a new group.
  let onNewGroup: () -> Void
  /// Scrolls to the top each time it changes.
  var scrollToTop = 0

  var body: some View {
    ScrollViewReader { proxy in
      list
        .overlay(alignment: .top) {
          // not while a card plays: scrolled to the top edge, the bar would lie over the video
          LoadProgressBar(progress: feed.player?.place == .card ? nil : feed.loadProgress)
        }
        .onAppear {
          // "Expand" onto a page pushed again: its list wasn't there to see `cardScrolls` change
          if let player = feed.player, player.place == .card {
            proxy.scrollTo(player.item.id)
          }
        }
        .onChange(of: scrollToTop) {
          withAnimation {
            proxy.scrollTo(Self.chipsID, anchor: .top)
          }
        }
        .onChange(of: feed.cardScrolls) {
          // a pressed card, auto-play's next and an expanded one may be partly
          // off screen: scrolled no further than brings it in
          if let playing = feed.player?.item.id {
            withAnimation { proxy.scrollTo(playing) }
          }
        }

    }
  }

  private static let chipsID = "chips"
  private static let endID = "end"

  private var list: some View {
    List {
      FeedChipRow(feed: feed, onNewGroup: onNewGroup)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .id(Self.chipsID)
      if feed.error != nil || feed.notice != nil {
        FeedBanners(feed: feed, app: app)
          .listRowSeparator(.hidden)
      }
      ForEach(feed.shown) { item in
        ItemCard(
          item: item,
          watched: feed.watched.contains(item.id),
          progress: feed.bars[item.id],
          feed: feed,
          onOpenChannel: { openChannel(item.channelId) },
          large: true
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
        // never the card that holds the player: nothing is drawn over the video
        .loadingDimmed(
          feed.loading && !(feed.player?.item.id == item.id && feed.player?.place == .card))
        // not while a load runs: the bar's button is off then too
        .watchedSwipe(
          watched: feed.watched.contains(item.id),
          offered: feed.player?.item.id != item.id && !feed.loading
        ) {
          feed.toggleWatched(item.id)
        }
      }
      FeedEmptyState(feed: feed)
        .listRowSeparator(.hidden)
      if !feed.showsSkeletons {
        YouTubeAttribution()
          .frame(maxWidth: .infinity)
          .listRowSeparator(.hidden)
          .id(Self.endID)
      }
    }
    .listStyle(.plain)
    .minimizedPlayerRoom(feed)
    // in its own task: the list cancels this one when it goes away
    .refreshable { await Task { await feed.load() }.value }
    .startsAtEndWhenAsked(Self.endID)
  }
}

/// One channel's filters as a sheet.
struct IOSFilterSheet: View {
  let feed: FeedModel
  let channelId: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      FilterForm(feed: feed, channelId: channelId)
        .navigationTitle(feed.channel(channelId)?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(Strings.done) {
              // a field still being typed in hands over what it holds first
              UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
              dismiss()
            }
          }
        }
    }
    .presentationDragIndicator(.visible)
  }
}

private struct IOSChannelsTab: View {
  let app: AppModel
  let feed: FeedModel
  @Binding var path: [ChannelRoute]
  /// Opens the group editor.
  let onGroup: (GroupTarget) -> Void
  @State private var search = ""

  private static let endID = "end"

  private var rows: [ChannelFilter] {
    channelsMatching(feed.orderedChannels, search: search)
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        ChannelChipRow(feed: feed, onNewGroup: { onGroup(.new) })
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets())
        ChannelSearchField(text: $search)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        if feed.explainsNoChannels && rows.isEmpty {
          NoChannelsForFilter()
            .listRowSeparator(.hidden)
        }
        ForEach(rows, id: \.channelId) { channel in
          HStack(spacing: 12) {
            Button {
              path.append(ChannelRoute(channelId: channel.channelId))
            } label: {
              ChannelRowLabel(channel: channel, feed: feed)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            UnwatchedCount(channel: channel, feed: feed)
              .foregroundStyle(.secondary)
            ChannelSwitch(title: channel.title, isOn: feed.binding(channel, \.enabled))
          }
          .opacity(channel.enabled ? 1 : offChannelOpacity)
        }
        YouTubeAttribution()
          .frame(maxWidth: .infinity)
          .listRowSeparator(.hidden)
          .id(Self.endID)
      }
      .listStyle(.plain)
      .minimizedPlayerRoom(feed)
      .scrollDismissesKeyboard(.interactively)
      .startsAtEndWhenAsked(Self.endID)
      .chipTitle(
        feed.channelListTitle, usual: Strings.channels, onEdit: { onGroup(.existing($0)) },
        onClear: feed.clearChannelChips
      )
      .onAppear(perform: feed.reorderChannels)
      .onChange(of: search) { feed.reorderChannels() }
      .navigationDestination(for: ChannelRoute.self) { route in
        IOSChannelPage(app: app, feed: feed, channelId: route.channelId)
      }
      #if DEBUG
        .onAppear {
          for name in ["channel", "filter"] {
            if let channelId = debugArgument(name) {
              path = [ChannelRoute(channelId: channelId)]
            }
          }
        }
      #endif
    }
  }
}

private struct IOSSettingsTab: View {
  let app: AppModel
  let feed: FeedModel
  private static let endID = "end"

  var body: some View {
    NavigationStack {
      Form {
        Section {
          AccountSummary(feed: feed)
        }
        Section {
          SyncStatus(feed: feed, showsExplanation: false)
        } header: {
          Text(Strings.sync)
        } footer: {
          Text(Strings.syncExplanation)
        }
        Section(Strings.appearance) {
          LabeledContent(Strings.theme) {
            ThemePicker(app: app).labelsHidden().fixedSize()
          }
        }
        Section {
          Button(Strings.signOut, role: .destructive) {
            Task { await app.signOut() }
          }
          .frame(maxWidth: .infinity)
        } footer: {
          Text(Strings.signOutFootnote)
        }
        Section {
          DeleteProfileButton(app: app)
            .frame(maxWidth: .infinity)
        } footer: {
          DeleteProfileFootnote(app: app)
        }
        Section {
          LegalLinks()
        }
        .id(Self.endID)
      }
      .minimizedPlayerRoom(feed)
      .startsAtEndWhenAsked(Self.endID)
      .navigationTitle(Strings.settings)
    }
  }
}

extension View {
  /// The title of a tab's first page: the usual large one, or, while its
  /// chip row has names selected, those names as an inline title with "Edit
  /// group" and "Clear" beside it. No control sits beside a large title.
  fileprivate func chipTitle(
    _ title: ChipTitle, usual: String, onEdit: @escaping (String) -> Void,
    onClear: @escaping () -> Void
  ) -> some View {
    navigationTitle(title.names.isEmpty ? usual : title.text)
      .navigationBarTitleDisplayMode(title.names.isEmpty ? .large : .inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          ChipTitleButtons(title: title, onEdit: onEdit, onClear: onClear)
        }
      }
  }

  /// In a debug build launched with `-bottom`, scroll the list to the row
  /// with this id once it shows.
  @ViewBuilder
  fileprivate func startsAtEndWhenAsked(_ endID: String) -> some View {
    #if DEBUG
      ScrollViewReader { proxy in
        task {
          if CommandLine.arguments.contains("-bottom") {
            try? await Task.sleep(for: .seconds(1))
            proxy.scrollTo(endID, anchor: .bottom)
          }
        }
      }
    #else
      self
    #endif
  }
}
