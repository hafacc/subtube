import SubtubeCore
import SwiftUI

/// The first run: what subtube is, sign-in, which channels, one filter, done.
struct NuxView: View {
  let app: AppModel

  enum Step: Int, CaseIterable {
    case intro
    case signIn
    case channels
    case filterChannel
    case filterShorts
    case filterTitles
    case done

    /// The step's dot; the three filter screens share one.
    var dot: Int {
      switch self {
      case .intro: 0
      case .signIn: 1
      case .channels: 2
      case .filterChannel, .filterShorts, .filterTitles: 3
      case .done: 4
      }
    }

    static let dotCount = 5
  }

  @State private var step: Step
  @State private var channelSearch = ""
  /// The channel the filter step tries a filter on.
  @State private var sampleChannelId: String?
  /// The Shorts setting picked for every channel, or nil while untouched.
  @State private var shortsChoice: ShortsFilter?
  /// The channel switches as left on "Choose channels"; saved on Next.
  @State private var enabledDraft: [String: Bool] = [:]
  /// The example channel's filter as the filter screens left it; saved when
  /// the last one is left.
  @State private var exampleDraft: ChannelFilter?
  @State private var patternValid = true
  /// Whether the videos are being fetched after "Choose channels".
  @State private var preparing = false

  init(app: AppModel) {
    self.app = app
    if app.feed != nil {
      _step = State(initialValue: .channels)
    } else if app.onboarded {
      _step = State(initialValue: .signIn)
    } else {
      _step = State(initialValue: .intro)
    }
    #if DEBUG
      if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("-nuxStep:") }),
        let forced = Int(argument.dropFirst("-nuxStep:".count)).flatMap(Step.init(rawValue:))
      {
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
    case .channels: Task { await leaveChannels() }
    case .filterChannel: go(.filterShorts)
    case .filterShorts: go(.filterTitles)
    case .filterTitles:
      if let feed = app.feed, let exampleDraft, let stored = feed.channel(exampleDraft.channelId),
        let edited = setupFilterEdit(stored: stored, draft: exampleDraft)
      {
        feed.updateFilter(edited)
      }
      go(.done)
    case .done: app.finishOnboarding()
    }
  }

  /// Save what "Choose channels" changed, fetch the videos of the channels
  /// left on, and pick the example channel from them.
  private func leaveChannels() async {
    guard let feed = app.feed, !preparing else { return }
    let edits = setupChannelEdits(feed.channels, enabled: enabledDraft, shorts: shortsChoice)
    feed.saveFilters(edits)
    enabledDraft = [:]
    shortsChoice = nil
    if !edits.isEmpty || !feed.hasLoaded {
      preparing = true
      await feed.load()
      preparing = false
    }
    if feed.error == nil {
      pickExample(feed.exampleChannel())
      go(sampleChannelId == nil ? .done : .filterChannel)
    }
  }

  /// Start the filter screens on a channel, dropping edits not saved yet.
  private func pickExample(_ channelId: String?) {
    sampleChannelId = channelId
    var draft = channelId.flatMap { app.feed?.channel($0) }
    if draft?.regex.isEmpty == true {
      // the titles screen is about hiding; saved only once a pattern is typed
      draft?.mode = .exclude
    }
    exampleDraft = draft
    patternValid = true
  }

  private func retreat() {
    switch step {
    case .done where sampleChannelId == nil: go(.channels)
    default: go(Step(rawValue: step.rawValue - 1) ?? .intro)
    }
  }

  private var showsBack: Bool {
    switch step {
    case .intro, .done: false
    // signing out and back in doesn't undo the sign-in
    case .channels: app.feed == nil
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
        HStack(spacing: 10) {
          StepDots(index: step.dot, count: Step.dotCount)
          Spacer()
          if showsBack {
            Button(Strings.back, action: retreat)
          }
          primaryButton
        }
        .padding(20)
      }
      .frame(minWidth: 800, minHeight: 600)
      .onAppear(perform: pickSampleIfNeeded)
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
          StepDots(index: step.dot, count: Step.dotCount)
          Spacer()
          Color.clear.frame(width: showsBack ? 60 : 0, height: 1)
        }
        .frame(height: 44)
        .padding(.horizontal)
        if step.dot == Step.filterChannel.dot {
          // these are forms, which scroll themselves
          stepContent.padding(.top, 12)
        } else {
          ScrollView {
            stepContent
              .padding(.horizontal, 20)
              .padding(.top, 12)
          }
          .scrollDismissesKeyboard(.interactively)
        }
        primaryButton
          .padding(.horizontal, 20)
          .padding(.bottom, 12)
      }
      .background(
        step.dot == Step.filterChannel.dot ? Color(.systemGroupedBackground) : Color(.systemBackground)
      )
      .onAppear(perform: pickSampleIfNeeded)
    #endif
  }

  private func pickSampleIfNeeded() {
    let filterSteps: [Step] = [.filterChannel, .filterShorts, .filterTitles]
    if filterSteps.contains(step) && sampleChannelId == nil {
      pickExample(app.feed?.exampleChannel())
    }
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
      GoogleSignInButton(model: app, fullWidth: wide)
        .keyboardShortcut(.defaultAction)
        .onChange(of: app.feed != nil, initial: true) { _, signedIn in
          if signedIn && step == .signIn {
            go(.channels)
          }
        }
    case .channels:
      Button(action: advance) {
        if preparing {
          ProgressView().controlSize(.small)
        } else {
          Text(Strings.next)
        }
      }
      .buttonStyle(ProminentButtonStyle(fullWidth: wide))
      .keyboardShortcut(.defaultAction)
      .disabled(app.feed?.channelsLoaded != true || preparing)
    case .filterChannel, .filterShorts, .filterTitles:
      Button(Strings.next, action: advance)
        .buttonStyle(ProminentButtonStyle(fullWidth: wide))
        .keyboardShortcut(.defaultAction)
        .disabled(step == .filterTitles && !patternValid)
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
        NuxChannels(
          feed: feed, search: $channelSearch, shortsChoice: $shortsChoice, enabled: $enabledDraft)
      }
    case .filterChannel:
      if let feed = app.feed {
        NuxExampleChannel(
          feed: feed,
          channelId: Binding(get: { sampleChannelId }, set: { pickExample($0) }))
      }
    case .filterShorts, .filterTitles:
      if let feed = app.feed, let draft = Binding($exampleDraft) {
        NuxFilter(
          feed: feed, filter: draft, titles: step == .filterTitles, patternValid: $patternValid)
      }
    case .done: done
    }
  }

  private var intro: some View {
    VStack(alignment: horizontalAlignment, spacing: 24) {
      #if os(macOS)
        LogoMark(size: 88)
        VStack(spacing: 6) {
          Text(Strings.appName).font(.system(size: 30, weight: .bold))
          Text(Strings.nuxHeadline).font(.title3).foregroundStyle(.secondary)
        }
      #else
        HStack(spacing: 12) {
          LogoMark(size: 56)
          Text(Strings.appName).font(.largeTitle.bold())
        }
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
      Text(Strings.signInHeading).font(.title.bold())
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
  let feed: FeedModel
  @Binding var search: String
  @Binding var shortsChoice: ShortsFilter?
  @Binding var enabled: [String: Bool]

  /// The channels as Next would save them.
  private var drafts: [ChannelFilter] {
    setupDraft(feed.channels, enabled: enabled, shorts: shortsChoice)
  }

  private var matching: [ChannelFilter] {
    let query = search.trimmingCharacters(in: .whitespaces)
    if query.isEmpty {
      return drafts
    } else {
      return drafts.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
  }

  private func isOn(_ channel: ChannelFilter) -> Binding<Bool> {
    Binding(get: { channel.enabled }, set: { enabled[channel.channelId] = $0 })
  }

  var body: some View {
    let onCount = drafts.count(where: \.enabled)
    VStack(alignment: .leading, spacing: 12) {
      Text(Strings.chooseChannels).font(.title.bold())
      Text(Strings.chooseChannelsDetail).foregroundStyle(.secondary)
      let shorts = Binding(
        get: { shortsChoice ?? commonShorts(feed.channels) },
        set: { shortsChoice = $0 })
      ShortsPicker(selection: shorts)
      HStack {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField(Strings.searchChannels, text: $search)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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
      if let error = feed.error {
        Text(error).font(.callout).foregroundStyle(.red)
      }
      if !feed.channelsLoaded && feed.channels.isEmpty {
        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
      } else if feed.channels.isEmpty {
        Text(Strings.noSubscriptions).foregroundStyle(.secondary)
      } else {
        channelList
      }
      Text(Strings.onCount(onCount, of: feed.channels.count))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .task {
      if !feed.channelsLoaded {
        await feed.loadChannels()
      }
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
              Avatar(url: channel.thumbnail, title: channel.title, size: 28)
              Text(channel.title)
              Spacer()
              ChannelSwitch(title: channel.title, isOn: isOn(channel))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .opacity(channel.enabled ? 1 : 0.5)
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
          .opacity(channel.enabled ? 1 : 0.5)
          Divider()
        }
      }
    #endif
  }
}

/// A filter step's heading and what it asks, above its form.
private struct NuxFormHeading: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(.title.bold())
      Text(detail).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    #if os(iOS)
      .padding(.horizontal, 20)
    #endif
  }
}

/// Pick the channel the next two screens try a filter on.
private struct NuxExampleChannel: View {
  let feed: FeedModel
  @Binding var channelId: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      NuxFormHeading(title: Strings.tryAFilter, detail: Strings.tryAFilterDetail)
      Form {
        Picker(Strings.exampleChannel, selection: $channelId) {
          ForEach(feed.exampleCandidates, id: \.channelId) { channel in
            Text(channel.title).tag(Optional(channel.channelId))
          }
        }
        .pickerStyle(.menu)
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: channelId) {
      if let channelId {
        await feed.loadPreview(channelId)
      }
    }
  }
}

/// Try one filter on the example channel with the filter editor's own
/// controls, and watch its preview change: the Shorts choice, or a pattern.
/// Nothing is saved from here; the edits stay in `filter`.
private struct NuxFilter: View {
  let feed: FeedModel
  @Binding var filter: ChannelFilter
  let titles: Bool
  @Binding var patternValid: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      NuxFormHeading(
        title: titles ? Strings.hideTitles : Strings.hideShorts,
        detail: titles ? Strings.hideTitlesDetail : Strings.hideShortsDetail)
      Form {
        if titles {
          Section(Strings.patternHeading(filter.searchScope)) {
            TitlePatternFields(filter: $filter, onValidity: { patternValid = $0 })
          }
        } else {
          Section {
            ShortsPicker(selection: $filter.shortsFilter)
          }
        }
        FilterPreview(feed: feed, channel: filter)
      }
      .formStyle(.grouped)
      #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
      #endif
    }
    .task(id: filter.channelId) { await feed.loadPreview(filter.channelId) }
  }
}
