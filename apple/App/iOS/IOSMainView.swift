import SubtubeCore
import SwiftUI

/// iOS: Feed, Channels and Settings tabs; a card plays in place.
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
    .onChange(of: openChannel) { _, channelId in
      feed.selectedChannel = channelId
    }
    .onAppear(perform: feed.appeared)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        feed.appeared()
      } else {
        Task { await feed.leftForeground() }
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
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
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

  var body: some View {
    NavigationStack(path: $path) {
      IOSFeedList(
        app: app, feed: feed, openChannel: { path.append(ChannelRoute(channelId: $0)) },
        scrollToTop: scrollToTop
      )
        .navigationTitle(Strings.feed)
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
  /// Scrolls to the top each time it changes.
  var scrollToTop = 0

  var body: some View {
    ScrollViewReader { proxy in
      list
        .overlay(alignment: .top) {
          LoadProgressBar(progress: feed.loadProgress)
        }
        .onChange(of: scrollToTop) {
          withAnimation {
            proxy.scrollTo(Self.chipsID, anchor: .top)
          }
        }
        .onChange(of: feed.player?.item.id) { _, playing in
          // auto-play's next card may be off screen; a tapped one already shows
          if let playing {
            withAnimation { proxy.scrollTo(playing) }
          }
        }
    }
  }

  private static let chipsID = "chips"
  private static let endID = "end"

  private var list: some View {
    List {
      FeedChipRow(feed: feed)
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
          player: feed.player?.item.id == item.id ? feed.player : nil,
          onOpen: { feed.open(item) },
          onOpenChannel: { openChannel(item.channelId) },
          large: true
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
        .loadingDimmed(feed.loading)
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
    .refreshable { await feed.load() }
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

  private static let endID = "end"

  private var rows: [ChannelFilter] {
    let query = search.trimmingCharacters(in: .whitespaces)
    return feed.orderedChannels.filter {
      query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        ChannelChipRow(feed: feed)
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
          .opacity(channel.enabled ? 1 : 0.5)
        }
        YouTubeAttribution()
          .frame(maxWidth: .infinity)
          .listRowSeparator(.hidden)
          .id(Self.endID)
      }
      .listStyle(.plain)
      .scrollDismissesKeyboard(.interactively)
      .startsAtEndWhenAsked(Self.endID)
      .navigationTitle(Strings.channels)
      .onAppear(perform: feed.reorderChannels)
      .onChange(of: search) { feed.reorderChannels() }
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
      .startsAtEndWhenAsked(Self.endID)
      .navigationTitle(Strings.settings)
    }
  }
}

extension View {
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
