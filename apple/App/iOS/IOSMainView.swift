import SubtubeCore
import SwiftUI

/// iOS: Feed, Channels and Settings tabs; the player covers the screen.
struct PlatformMainView: View {
  let app: AppModel
  @Bindable var feed: FeedModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab = MainTab.feed
  @State private var feedPath: [ChannelRoute] = []
  @State private var channelsPath: [ChannelRoute] = []
  /// Counts taps on the Feed tab while the feed shows.
  @State private var feedTopTaps = 0

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
        IOSFeedTab(app: app, feed: feed, path: $feedPath, scrollToTop: feedTopTaps)
      }
      Tab(Strings.channels, systemImage: "slider.horizontal.3", value: MainTab.channels) {
        IOSChannelsTab(app: app, feed: feed, path: $channelsPath)
      }
      Tab(Strings.settings, systemImage: "gearshape", value: MainTab.settings) {
        IOSSettingsTab(app: app, feed: feed)
      }
    }
    .fullScreenCover(item: $feed.player) { session in
      IOSPlayerScreen(session: session, feed: feed)
    }
    .onChange(of: openChannel) { _, channelId in
      feed.selectedChannel = channelId
    }
    .onAppear(perform: feed.appeared)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        feed.appeared()
      } else {
        Task { await feed.flush() }
      }
    }
    #if DEBUG
      .onAppear {
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("-tab:") }),
          let forced = MainTab(rawValue: String(argument.dropFirst("-tab:".count)))
        {
          tab = forced
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
    IOSFeedList(app: app, feed: feed, openChannel: { _ in })
      .navigationTitle(feed.channel(channelId)?.title ?? "")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          HideWatchedButton(feed: feed)
          Button {
            editingFilters = true
          } label: {
            Label(Strings.filters, systemImage: "gearshape")
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

  var body: some View {
    NavigationStack(path: $path) {
      IOSFeedList(
        app: app, feed: feed, openChannel: { path.append(ChannelRoute(channelId: $0)) },
        scrollToTop: scrollToTop
      )
        .navigationTitle(Strings.feed)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            HideWatchedButton(feed: feed)
          }
        }
        .navigationDestination(for: ChannelRoute.self) { route in
          IOSChannelPage(app: app, feed: feed, channelId: route.channelId)
        }
    }
  }
}

/// Hide Watched for the feed and channel pages alike.
private struct HideWatchedButton: View {
  let feed: FeedModel

  var body: some View {
    Button {
      feed.hideWatched.toggle()
    } label: {
      Label(Strings.hideWatched, systemImage: feed.hideWatched ? "eye.slash" : "eye")
    }
    .accessibilityAddTraits(feed.hideWatched ? .isSelected : [])
  }
}

/// The feed (or the selected channel's page) as a column of big cards.
private struct IOSFeedList: View {
  let app: AppModel
  let feed: FeedModel
  let openChannel: (String) -> Void
  /// Scrolls to the top each time it changes.
  var scrollToTop = 0

  var body: some View {
    ScrollViewReader { proxy in
      list.onChange(of: scrollToTop) {
        if let first = feed.shown.first {
          withAnimation { proxy.scrollTo(first.id, anchor: .top) }
        }
      }
    }
  }

  private var list: some View {
    List {
      if feed.error != nil || feed.notice != nil {
        FeedBanners(feed: feed, app: app)
          .listRowSeparator(.hidden)
      }
      ForEach(feed.shown) { item in
        let watched = feed.watched.contains(item.id)
        ItemCard(
          item: item,
          watched: watched,
          onOpen: { feed.open(item) },
          onOpenChannel: { openChannel(item.channelId) },
          onToggleWatched: { feed.toggleWatched(item) },
          large: true
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
          Button {
            feed.toggleWatched(item)
          } label: {
            Label(watched ? Strings.markAsUnwatched : Strings.markAsWatched, systemImage: "eye")
          }
          .tint(Color.gold)
        }
        .loadingDimmed(feed.loading)
      }
      FeedEmptyState(feed: feed)
        .listRowSeparator(.hidden)
    }
    .listStyle(.plain)
    .refreshable { await feed.load() }
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
            Button(Strings.done) { dismiss() }
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
  @State private var search = ""

  private var rows: [ChannelFilter] {
    let query = search.trimmingCharacters(in: .whitespaces)
    return feed.orderedChannels.filter {
      query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      List(rows, id: \.channelId) { channel in
        HStack(spacing: 12) {
          Button {
            path.append(ChannelRoute(channelId: channel.channelId))
          } label: {
            ChannelRowLabel(channel: channel, feed: feed)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          ChannelSwitch(title: channel.title, isOn: feed.binding(channel, \.enabled))
        }
        .opacity(channel.enabled ? 1 : 0.5)
      }
      .listStyle(.plain)
      .searchable(
        text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Strings.searchChannels)
      .navigationTitle(Strings.channels)
      .navigationDestination(for: ChannelRoute.self) { route in
        IOSChannelPage(app: app, feed: feed, channelId: route.channelId)
      }
      #if DEBUG
        .onAppear {
          for name in ["-channel:", "-filter:"] {
            if let argument = CommandLine.arguments.first(where: { $0.hasPrefix(name) }) {
              path = [ChannelRoute(channelId: String(argument.dropFirst(name.count)))]
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
          PrivacyPolicyLink()
        }
      }
      #if DEBUG
        .defaultScrollAnchor(CommandLine.arguments.contains("-bottom") ? .bottom : .top)
      #endif
      .navigationTitle(Strings.settings)
    }
  }
}

/// The player over everything: video and its actions.
private struct IOSPlayerScreen: View {
  let session: PlayerSession
  let feed: FeedModel

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          YouTubePlayerView(session: session)
          VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.title3.bold())
            PlayerMetaLine(session: session, onOpenChannel: { _ in }, fullDate: false)
              .font(.subheadline)
          }
          .padding(.horizontal)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              PlayerActions(session: session, feed: feed)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.horizontal)
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            feed.player = nil
          } label: {
            Label(Strings.closePlayer, systemImage: "chevron.down")
          }
        }
      }
    }
  }
}
