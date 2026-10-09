import SubtubeCore
import SwiftUI

/// The first run: what subtube is, sign-in, which channels, Shorts, where
/// to start, done.
struct NuxView: View {
  let app: AppModel

  enum Step: Int, CaseIterable {
    case intro
    case signIn
    case channels
    case shorts
    case start
    case done
  }

  @State private var step: Step
  @State private var channelSearch = ""
  /// The Shorts setting picked for every channel, or nil while untouched.
  @State private var shortsChoice: ShortsFilter?
  /// Where the feed starts; everything older is marked watched.
  @State private var startFrom = StartFrom.all
  /// The channel switches as left on "Choose channels"; saved on Next.
  @State private var enabledDraft: [String: Bool] = [:]

  init(app: AppModel) {
    self.app = app
    if app.feed != nil {
      _step = State(initialValue: .channels)
    } else if app.introSeen {
      _step = State(initialValue: .signIn)
    } else {
      _step = State(initialValue: .intro)
    }
    #if DEBUG
      if let forced = debugArgument("nuxStep").flatMap(Int.init).flatMap(Step.init(rawValue:)) {
        _step = State(initialValue: forced)
      }
    #endif
  }

  private func go(_ target: Step) {
    withAnimation(.snappy) { step = target }
  }

  private func advance() {
    switch step {
    case .intro: go(.signIn)
    case .signIn: break
    case .channels: leaveChannels()
    case .shorts: leaveShorts()
    case .start: go(.done)
    case .done: finish()
    }
  }

  /// Save the switches and start fetching the channels left on, and no
  /// others.
  private func leaveChannels() {
    guard let feed = app.feed else { return }
    feed.saveFilters(setupChannelEdits(feed.channels, enabled: enabledDraft, shorts: nil))
    enabledDraft = [:]
    feed.prefetchEnabled()
    go(.shorts)
  }

  /// Save the Shorts choice; one that filters needs the Shorts lists the
  /// fetch left out.
  private func leaveShorts() {
    guard let feed = app.feed else { return }
    feed.saveFilters(setupChannelEdits(feed.channels, enabled: [:], shorts: shortsChoice))
    shortsChoice = nil
    feed.prefetchEnabled()
    go(.start)
  }

  /// Keep the starting point for the channels that are on, each until a load
  /// fetches it, and open the feed.
  private func finish() {
    if let feed = app.feed {
      keepPendingStart(
        accountId: feed.account.channelId,
        PendingStart(
          start: startFrom, cutoff: epochMilliseconds(),
          channels: feed.channels.filter(\.enabled).map(\.channelId)))
    }
    app.finishOnboarding()
  }

  private func retreat() {
    go(Step(rawValue: step.rawValue - 1) ?? .intro)
  }

  private var showsBack: Bool {
    switch step {
    case .intro, .done: false
    default: true
    }
  }

  var body: some View {
    #if os(macOS)
      VStack(spacing: 0) {
        stepContent
          .frame(maxWidth: 560, maxHeight: .infinity)
          .padding(.horizontal, 40)
          .padding(.top, 20)
        if step == .signIn {
          VStack(spacing: 10) {
            primaryButton
            SignInAgreement().multilineTextAlignment(.center)
          }
          .padding(.horizontal, 40)
        }
        HStack(spacing: 10) {
          StepDots(index: step.rawValue, count: Step.allCases.count)
          Spacer()
          if showsBack {
            Button(Strings.back, action: retreat)
          }
          if step != .signIn {
            primaryButton
          }
        }
        .padding(20)
      }
      .frame(minWidth: 800, minHeight: 600)
    #else
      VStack(spacing: 0) {
        HStack {
          if showsBack {
            Button(action: retreat) {
              Label(Strings.back, systemImage: "chevron.backward")
            }
            .foregroundStyle(Color.gold)
          }
          Spacer()
          StepDots(index: step.rawValue, count: Step.allCases.count)
          Spacer()
          Color.clear.frame(width: showsBack ? 60 : 0, height: 1)
        }
        .frame(height: 44)
        .padding(.horizontal)
        ScrollView {
          stepContent
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        VStack(spacing: 10) {
          primaryButton
          if step == .signIn {
            SignInAgreement().multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
      }
      .background(Color(.systemBackground))
    #endif
  }

  @ViewBuilder
  private var primaryButton: some View {
    #if os(macOS)
      let wide = false
    #else
      let wide = true
    #endif
    switch step {
    case .intro:
      Button(Strings.getStarted, action: advance)
        .buttonStyle(ProminentButtonStyle(fullWidth: wide))
        .keyboardShortcut(.defaultAction)
    case .signIn:
      // a first sign-in replaces this whole view; one after Back moves on from here
      GoogleSignInButton(app: app, fullWidth: wide, onSignedIn: { go(.channels) })
        .keyboardShortcut(.defaultAction)
    case .channels:
      Button(Strings.next, action: advance)
        .buttonStyle(ProminentButtonStyle(fullWidth: wide))
        .keyboardShortcut(.defaultAction)
        .disabled(app.feed?.channelsLoaded != true)
    case .shorts, .start:
      Button(Strings.next, action: advance)
        .buttonStyle(ProminentButtonStyle(fullWidth: wide))
        .keyboardShortcut(.defaultAction)
    case .done:
      Button(Strings.openMyFeed, action: advance)
        .buttonStyle(ProminentButtonStyle(fullWidth: wide))
        .keyboardShortcut(.defaultAction)
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .intro: intro
    case .signIn: signIn
    case .channels:
      if let feed = app.feed {
        NuxChannels(app: app, feed: feed, search: $channelSearch, enabled: $enabledDraft)
      }
    case .shorts:
      if let feed = app.feed {
        choice(Strings.shorts, Strings.shortsSetupDetail) {
          ShortsPicker(
            selection: Binding(
              get: { shortsChoice ?? commonShorts(feed.channels) }, set: { shortsChoice = $0 }))
        }
      }
    case .start:
      choice(Strings.whereToStart, Strings.whereToStartDetail) {
        SegmentedRow(
          label: Strings.whereToStart, selection: $startFrom,
          options: [StartFrom.day, .week, .all].map { ($0, Strings.startOption($0)) },
          showsHeading: true)
      }
    case .done: done
    }
  }

  private var loading: Bool { app.feed?.loading ?? false }

  private var intro: some View {
    VStack(alignment: horizontalAlignment, spacing: 24) {
      #if os(macOS)
        VStack(spacing: 6) {
          Wordmark(font: .system(size: 30, weight: .bold), loading: loading)
          Text(Strings.nuxHeadline).font(.title3).foregroundStyle(.secondary)
        }
      #else
        Wordmark(font: .largeTitle.bold(), loading: loading)
          .padding(.top, 36)
        Text(Strings.nuxHeadline).font(.title.bold())
      #endif
      VStack(alignment: .leading, spacing: 14) {
        bullet("list.bullet.below.rectangle", Strings.nuxBulletNewest)
        bullet("line.3.horizontal.decrease", Strings.nuxBulletFilters)
        bullet("checkmark.circle", Strings.nuxBulletWatched)
      }
    }
    .multilineTextAlignment(textAlignment)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var horizontalAlignment: HorizontalAlignment {
    #if os(macOS)
      .center
    #else
      .leading
    #endif
  }

  private var textAlignment: TextAlignment {
    #if os(macOS)
      .center
    #else
      .leading
    #endif
  }

  private func bullet(_ symbol: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: symbol).foregroundStyle(Color.gold).frame(width: 22)
      Text(text).multilineTextAlignment(.leading)
    }
  }

  private var signIn: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(Strings.signIn).font(.title.bold())
      Text(Strings.permissionsIntro).foregroundStyle(.secondary)
      permission("play.rectangle", Strings.permissionYouTube, Strings.permissionYouTubeDetail)
      permission("externaldrive", Strings.permissionDrive, Strings.permissionDriveDetail)
      Text(Strings.noServer).font(.footnote).foregroundStyle(.secondary)
      if let error = app.error {
        Text(error).font(.callout).foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func permission(_ symbol: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(Color.gold)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline)
        Text(detail).foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  /// A screen with one of the app's own controls: heading, what it does,
  /// and the control in a card.
  private func choice(_ heading: String, _ detail: String, @ViewBuilder control: () -> some View)
    -> some View
  {
    VStack(alignment: .leading, spacing: 16) {
      Text(heading).font(.title.bold())
      Text(detail).foregroundStyle(.secondary)
      control()
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var done: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(Color.ink)
        .frame(width: 72, height: 72)
        .background(Color.sunflower, in: Circle())
      Text(Strings.youreSet).font(.title.bold())
      Text(Strings.doneDetail)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.top, 40)
  }
}

/// Turn subscriptions on or off before the first feed.
private struct NuxChannels: View {
  let app: AppModel
  let feed: FeedModel
  @Binding var search: String
  @Binding var enabled: [String: Bool]

  /// The channels as Next would save them.
  private var drafts: [ChannelFilter] {
    setupDraft(feed.channels, enabled: enabled, shorts: nil)
  }

  private var matching: [ChannelFilter] {
    channelsByName(channelsMatching(drafts, search: search))
  }

  /// A load that failed, with "Refresh" to try it again and, when only that
  /// helps, the sign-in.
  @ViewBuilder
  private var loadError: some View {
    if let error = feed.error {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(error).font(.callout).foregroundStyle(.red)
        Spacer(minLength: 0)
        if feed.needsReconnect {
          SignInButton(app: app) { Text(Strings.signInShort) }
        } else {
          Button(Strings.refresh) {
            Task { await feed.loadChannels() }
          }
          .disabled(feed.loading)
        }
      }
      .buttonStyle(.borderless)
      .foregroundStyle(Color.gold)
    }
  }

  private var skeletonRows: some View {
    VStack(spacing: 0) {
      ForEach(0..<16, id: \.self) { _ in
        HStack(spacing: 12) {
          Circle().fill(Color.secondary.opacity(0.15)).frame(width: 28, height: 28)
          SkeletonLine(width: 180)
          Spacer()
        }
        .padding(.vertical, 10)
        Divider()
      }
    }
    .skeleton()
  }

  private func isOn(_ channel: ChannelFilter) -> Binding<Bool> {
    Binding(get: { channel.enabled }, set: { enabled[channel.channelId] = $0 })
  }

  var body: some View {
    Group {
      if !feed.channelsLoaded && feed.channels.isEmpty && feed.error == nil {
        // while loading, the rows' stand-ins alone
        skeletonRows.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      } else {
        loaded
      }
    }
    .task {
      if !feed.channelsLoaded {
        await feed.loadChannels()
      }
    }
  }

  private var loaded: some View {
    let onCount = drafts.count(where: \.enabled)
    return VStack(alignment: .leading, spacing: 12) {
      Text(Strings.chooseChannels).font(.title.bold())
      Text(Strings.chooseChannelsDetail).foregroundStyle(.secondary)
      HStack {
        ChannelSearchField(text: $search)
        Button(onCount > 0 ? Strings.turnAllOff : Strings.turnAllOn) {
          let target = onCount == 0
          for channel in feed.channels {
            enabled[channel.channelId] = target
          }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.gold)
        .disabled(feed.channels.isEmpty)
      }
      loadError
      if feed.channels.isEmpty {
        if feed.channelsLoaded {
          Text(Strings.noSubscriptions).foregroundStyle(.secondary)
        }
      } else {
        channelList
      }
      Text(Strings.onCount(onCount, of: feed.channels.count))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  /// The rows; on macOS they scroll inside the step, on iOS the whole step
  /// scrolls and the rows are the Channels tab's.
  @ViewBuilder
  private var channelList: some View {
    #if os(macOS)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(matching, id: \.channelId) { channel in
            HStack(spacing: 10) {
              HStack(spacing: 10) {
                Avatar(url: channel.thumbnail, title: channel.title, size: 28)
                Text(channel.title)
              }
              .opacity(channel.enabled ? 1 : offChannelOpacity)
              Spacer()
              ChannelSwitch(title: channel.title, isOn: isOn(channel))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            Divider()
          }
        }
      }
      .frame(maxHeight: .infinity)
      .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    #else
      LazyVStack(spacing: 0) {
        Divider()
        ForEach(matching, id: \.channelId) { channel in
          HStack(spacing: 12) {
            ChannelRowLabel(channel: channel, feed: feed)
            ChannelSwitch(title: channel.title, isOn: isOn(channel))
          }
          .padding(.vertical, 10)
          Divider()
        }
      }
    #endif
  }
}
