import Foundation
import SubtubeCore

/// Every user-facing string in the apps.
enum Strings {
  static let appName = String(localized: "SubTube")
  static let feed = String(localized: "Feed")
  static let channels = String(localized: "Channels")
  static let settings = String(localized: "Settings")
  static let done = String(localized: "Done")
  static let cancel = String(localized: "Cancel")
  static let next = String(localized: "Next")
  static let back = String(localized: "Back")

  static let refresh = String(localized: "Refresh")
  static let filters = String(localized: "Filters")
  static let inspector = String(localized: "Details")
  static let showChannels = String(localized: "Show Channels")
  static let hideChannels = String(localized: "Hide Channels")
  static let shortBadge = String(localized: "Short")
  static let watched = String(localized: "Watched")
  static let noMatches = String(localized: "Nothing new. You're caught up.")
  static let noVideosForFilter = String(localized: "No videos for the selected filter.")
  static let noChannelsForFilter = String(localized: "No channels for the selected filter.")
  static let clear = String(localized: "Clear")
  static let save = String(localized: "Save")
  static let name = String(localized: "Name")
  static let latest = String(localized: "Latest")
  static let unwatched = String(localized: "Unwatched")
  static let title = String(localized: "Title")
  static let deleteGroup = String(localized: "Delete Group")
  #if os(macOS)
    static let newGroup = String(localized: "New Group")
    static let editGroup = String(localized: "Edit Group")
  #else
    static let newGroup = String(localized: "New group")
    static let editGroup = String(localized: "Edit group")
  #endif
  #if os(macOS)
    static let markWatched = String(localized: "Mark Watched")
    static let markUnwatched = String(localized: "Mark Unwatched")
  #else
    static let markWatched = String(localized: "Mark watched")
    static let markUnwatched = String(localized: "Mark unwatched")
  #endif
  static let expand = String(localized: "Expand")
  static let minimize = String(localized: "Minimize")
  static let close = String(localized: "Close")
  static let dismiss = String(localized: "Dismiss")

  static func videoCount(_ count: Int) -> String {
    count == 1 ? String(localized: "1 video") : String(localized: "\(count) videos")
  }

  static func unwatchedCount(_ count: Int) -> String {
    String(localized: "\(count) unwatched")
  }

  static func play(_ title: String) -> String {
    String(localized: "Play \(title)")
  }

  static let player = String(localized: "Player")

  static let autoplay = String(localized: "Auto-play")
  #if os(macOS)
    static let sortAndFilter = String(localized: "Sort and Filter")
  #else
    static let sortAndFilter = String(localized: "Sort and filter")
  #endif

  static func feedSortOption(_ sort: FeedSort) -> String {
    switch sort {
    case .newest: latest
    case .oldest: String(localized: "Oldest")
    case .shortest: String(localized: "Shortest")
    case .longest: String(localized: "Longest")
    case .title: String(localized: "Title A–Z")
    case .titleReversed: String(localized: "Title Z–A")
    case .random: String(localized: "Random")
    }
  }

  static let allTime = String(localized: "All time")
  static let pastDay = String(localized: "Past day")
  static let pastWeek = String(localized: "Past week")

  static func timeChipOption(_ timeChip: TimeChip) -> String {
    switch timeChip {
    case .anyTime: allTime
    case .day: pastDay
    case .week: pastWeek
    case .month: String(localized: "Past month")
    }
  }

  static func channelSortOption(_ sort: ChannelSort) -> String {
    switch sort {
    case .newest: latest
    case .name: name
    case .unwatched: unwatched
    }
  }

  static func startOption(_ start: StartFrom) -> String {
    switch start {
    case .day: pastDay
    case .week: pastWeek
    case .all: allTime
    }
  }

  static let showInFeed = String(localized: "Show in Feed")
  static let videos = String(localized: "Videos")
  static let show = String(localized: "Show")
  static let uploads = String(localized: "Uploads")
  static let playlists = String(localized: "Playlists")
  static func patternHeading(_ scope: FilterScope) -> String {
    switch scope {
    case .title: String(localized: "Title Phrases")
    case .description: String(localized: "Description Phrases")
    case .both: String(localized: "Text Phrases")
    }
  }

  static let matches = String(localized: "Matches")
  static let matchIn = String(localized: "Match In")
  static let scopeBoth = String(localized: "Both")
  static let scopeDescription = String(localized: "Description")
  static let caseHeading = String(localized: "Case")
  static let caseIgnore = String(localized: "Ignore")
  static let caseMatch = String(localized: "Match")
  static let addPhrase = String(localized: "Add a phrase")
  static let phrasesDetail = String(
    localized: "Videos match if they contain any of these phrases.")
  static let topics = String(localized: "Topics")
  static let topicsDetail = String(
    localized: "Only videos with a selected topic are shown. None selected shows all.")
  static let shorts = String(localized: "Shorts")
  static let live = String(localized: "Live")
  static let hideVideosUnder = String(localized: "Hide Videos Under")
  static let seconds = String(localized: "seconds")

  static func showChannelInFeed(_ title: String) -> String {
    String(localized: "Show \(title) in Feed")
  }

  static func filtersFor(_ title: String) -> String {
    String(localized: "Filters for \(title)")
  }

  static let choiceHide = String(localized: "Hide")
  static let choiceOnly = String(localized: "Only")

  static func shortsOption(_ filter: ShortsFilter) -> String {
    switch filter {
    case .all: show
    case .normal: choiceHide
    case .shorts: choiceOnly
    }
  }

  static func liveOption(_ filter: LiveFilter) -> String {
    switch filter {
    case .all: show
    case .normal: choiceHide
    case .vod: choiceOnly
    }
  }

  static func scopeOption(_ scope: FilterScope) -> String {
    switch scope {
    case .title: title
    case .both: scopeBoth
    case .description: scopeDescription
    }
  }

  static let summaryOff = String(localized: "Off")
  static let summaryAllVideos = String(localized: "All videos")
  static let summaryNoShorts = String(localized: "No Shorts")
  static let summaryShortsOnly = String(localized: "Shorts only")
  static let summaryNoLive = String(localized: "No live")
  static let summaryLiveOnly = String(localized: "Live only")
  static let summaryFollowed = String(localized: "Followed in SubTube")
  static let subscribedOnYouTube = String(localized: "Subscribed on YouTube")

  static func summaryOnlyMatching(_ pattern: String, scope: FilterScope) -> String {
    switch scope {
    case .title: String(localized: "Only titles matching \(pattern)")
    case .both: String(localized: "Only titles or descriptions matching \(pattern)")
    case .description: String(localized: "Only descriptions matching \(pattern)")
    }
  }

  static func summaryHidesMatching(_ pattern: String, scope: FilterScope) -> String {
    switch scope {
    case .title: String(localized: "Hides titles matching \(pattern)")
    case .both: String(localized: "Hides titles or descriptions matching \(pattern)")
    case .description: String(localized: "Hides descriptions matching \(pattern)")
    }
  }

  static func summaryHidesUnder(_ seconds: Int) -> String {
    seconds == 1
      ? String(localized: "Hides videos under 1 second")
      : String(localized: "Hides videos under \(seconds) seconds")
  }

  static func summaryOnlyTopics(_ topics: String) -> String {
    String(localized: "Only \(topics)")
  }

  /// One part of a channel's filter summary, as the channels list words it.
  static func summary(_ part: FilterSummaryPart) -> String {
    switch part {
    case .playlists: playlists
    case .matching(let phrases, let mode, let scope):
      mode == .exclude
        ? summaryHidesMatching(phrases.joined(separator: ", "), scope: scope)
        : summaryOnlyMatching(phrases.joined(separator: ", "), scope: scope)
    case .noShorts: summaryNoShorts
    case .shortsOnly: summaryShortsOnly
    case .noLive: summaryNoLive
    case .liveOnly: summaryLiveOnly
    case .hidesUnder(let seconds): summaryHidesUnder(seconds)
    case .topics(let names): summaryOnlyTopics(names.joined(separator: ", "))
    case .allVideos: summaryAllVideos
    }
  }

  static let chipSort = String(localized: "Sort")
  static let chipTime = String(localized: "Time")
  static let chipShow = String(localized: "Show")

  /// A cycling chip's name for a screen reader: what it sets, then its choice.
  static func chipSetting(_ setting: String, value: String) -> String {
    String(localized: "\(setting): \(value)")
  }

  static func removePhrase(_ phrase: String) -> String {
    String(localized: "Remove \(phrase)")
  }

  static let general = String(localized: "General")
  static let account = String(localized: "Account")
  static let sync = String(localized: "Sync")
  static let syncedWithDrive = String(localized: "Synced with Google Drive")
  static let syncExplanation = String(
    localized:
      "Your channels, filters and what you've watched are kept in a hidden SubTube folder in your Google Drive.")
  static let syncing = String(localized: "Syncing…")
  static let appearance = String(localized: "Appearance")
  static let theme = String(localized: "Theme")
  static let signOut = String(localized: "Sign Out")
  static let signOutFootnote = String(
    localized:
      "Your channels, filters and what you've watched stay in your Google Drive. Sign back in to get them."
  )

  static let deleteProfile = String(localized: "Delete Profile")
  static let deleteProfileDetail = String(
    localized:
      "Deletes your filters, followed channels and what you've watched from Google Drive, on all your devices. Your YouTube account isn't changed."
  )
  static let deleteProfileTitle = String(localized: "Delete your profile?")
  static let deleteProfileMessage = String(
    localized:
      "This deletes your filters, followed channels and what you've watched from Google Drive and from this device. It can't be undone."
  )
  static let deleteProfileFailed = String(
    localized: "Couldn't delete your profile. Check your connection and try again.")

  static func lastSynced(_ relative: String) -> String {
    String(localized: "Last synced \(relative)")
  }

  static func themeOption(_ theme: Theme) -> String {
    switch theme {
    case .system: String(localized: "System")
    case .light: String(localized: "Light")
    case .dark: String(localized: "Dark")
    }
  }

  static let nuxHeadline = String(localized: "Your subscriptions, your filters, no algorithm.")
  static let nuxBulletNewest = String(
    localized: "New videos from the channels you subscribe to, latest first.")
  static let nuxBulletFilters = String(
    localized: "Filters for each channel hide Shorts, live streams, or titles you don't want.")
  static let nuxBulletWatched = String(
    localized: "What you've watched is remembered on all your devices.")
  static let getStarted = String(localized: "Get Started")
  #if os(macOS)
    static let chooseChannels = String(localized: "Choose Channels")
    static let youreSet = String(localized: "You're Set")
    static let doneDetail = String(
      localized:
        "Your feed starts with the latest video you haven't watched. Click one to play it.")
  #else
    static let chooseChannels = String(localized: "Choose channels")
    static let youreSet = String(localized: "You're set")
    static let doneDetail = String(
      localized:
        "Your feed starts with the latest video you haven't watched. Tap one to play it.")
  #endif
  #if os(macOS)
    static let whereToStart = String(localized: "Where to Start")
  #else
    static let whereToStart = String(localized: "Where to start")
  #endif
  static let noServer = String(
    localized:
      "SubTube has no server of its own. Your data stays in your Google account and on this device."
  )
  /// The sign-in button and the heading over it, in Google's own wording on every platform.
  static let signIn = String(localized: "Sign in with Google")
  static let signInShort = String(localized: "Sign In")
  static let privacyPolicy = String(localized: "Privacy Policy")
  static let terms = String(localized: "Terms")
  static let videosFromYouTube = String(localized: "Videos from YouTube")

  /// The line under a sign-in button, with "Terms" and "Privacy Policy" as links.
  static var signInAgreement: AttributedString {
    var line = AttributedString(
      localized: "By signing in, you agree to SubTube's Terms and Privacy Policy.")
    for (phrase, address) in [(terms, Links.terms), (privacyPolicy, Links.privacyPolicy)] {
      if let range = line.range(of: phrase) {
        line[range].link = address
      }
    }
    return line
  }
  static let permissionsIntro = String(localized: "SubTube asks Google for two permissions:")
  static let permissionYouTube = String(localized: "Read your YouTube subscriptions")
  static let permissionYouTubeDetail = String(
    localized: "So it knows which channels to show. It can't change anything on your YouTube account.")
  static let permissionDrive = String(localized: "Keep your filters in your Google Drive")
  static let permissionDriveDetail = String(
    localized:
      "In a hidden folder that only SubTube can open. It holds your filters and what you've watched. SubTube can't see your other files."
  )
  static let chooseChannelsDetail = String(
    localized: "Your subscriptions start on. Turn off any you don't want in your feed.")
  static let shortsSetupDetail = String(
    localized:
      "This applies to every channel. You can change it for a single channel under Channels.")
  static let whereToStartDetail = String(localized: "Older videos are marked as watched.")
  static let noSubscriptions = String(
    localized:
      "You don't subscribe to any channels yet. Subscribe on YouTube and they'll show up here.")
  static let searchChannels = String(localized: "Search channels")
  static let turnAllOff = String(localized: "Turn All Off")
  static let turnAllOn = String(localized: "Turn All On")
  static let openMyFeed = String(localized: "Open My Feed")

  static func onCount(_ count: Int, of total: Int) -> String {
    String(localized: "\(count) of \(total) on")
  }

  static func step(_ index: Int, of total: Int) -> String {
    String(localized: "Step \(index) of \(total)")
  }

  static let partialLoad = String(
    localized: "Some channels couldn't be loaded; showing partial results.")
  static let reconnectToLoad = String(localized: "Sign in again to load your feed.")
  static let sessionEnded = String(localized: "Your Google session ended. Sign in again to refresh.")
  static let needsPermissions = String(
    localized: "SubTube needs both permissions Google asks for. Sign in again and allow them.")
  static let playerFailed = String(
    localized:
      "Couldn't load the YouTube player. Check your connection or any content blockers, then try again."
  )
  static let signInAgain = String(localized: "Sign in again to continue.")
  static let noYouTubeChannel = String(localized: "This Google account has no YouTube channel.")
  static let dailyLimit = String(
    localized: "SubTube has reached YouTube's daily limit. Try again after midnight Pacific time.")
  static let couldntReachGoogle = String(
    localized: "Couldn't reach Google. Check your connection and try again.")

  /// What a failed sign-in or load says: `signedOut` when only signing in
  /// helps, nothing for work that was called off or a sign-in the user
  /// closed, and for anything without a message of its own that Google
  /// couldn't be reached.
  static func message(for error: Error, signedOut: String) -> String? {
    switch error {
    case AuthError.declined: nil
    case AuthError.signInRequired: signedOut
    case GoogleAPIError.tokenExpired: sessionEnded
    case GoogleAPIError.insufficientScope: needsPermissions
    case GoogleAPIError.noChannel: noYouTubeChannel
    case GoogleAPIError.dailyLimit: dailyLimit
    default: isCancellation(error) ? nil : couldntReachGoogle
    }
  }

  /// Whether signing in again is what fixes an error.
  static func signingInFixes(_ error: Error) -> Bool {
    switch error {
    case AuthError.signInRequired, GoogleAPIError.tokenExpired, GoogleAPIError.insufficientScope:
      true
    default: false
    }
  }
}
