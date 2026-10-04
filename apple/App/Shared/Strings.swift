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
  static let hideWatched = String(localized: "Hide Watched")
  static let filters = String(localized: "Filters")
  static let nextVideo = String(localized: "Next Video")
  static let markAsWatched = String(localized: "Mark as Watched")
  static let markAllAsWatched = String(localized: "Mark All as Watched")
  static let markAllAsUnwatched = String(localized: "Mark All as Unwatched")
  static let markAsUnwatched = String(localized: "Mark as Unwatched")
  static let inspector = String(localized: "Details")
  static let showInspector = String(localized: "Show Details")
  static let hideInspector = String(localized: "Hide Details")
  static let shortBadge = String(localized: "Short")
  static let watchedBadge = String(localized: "watched")
  static let noChannelSelected = String(localized: "Select a channel to edit its filters.")
  static let noMatches = String(localized: "Nothing new. You're caught up.")
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

  static let closePlayer = String(localized: "Close Player")
  static let openOnYouTube = String(localized: "Open on YouTube")

  static let showInFeed = String(localized: "Show in Feed")
  static let show = String(localized: "Show")
  static let uploads = String(localized: "Uploads")
  static let playlists = String(localized: "Playlists")
  static func patternHeading(_ scope: FilterScope) -> String {
    switch scope {
    case .title: String(localized: "Title Pattern")
    case .description: String(localized: "Description Pattern")
    case .both: String(localized: "Text Pattern")
    }
  }

  static let matches = String(localized: "Matches")
  static let matchIn = String(localized: "Match in")
  static let scopeTitle = String(localized: "Title")
  static let scopeBoth = String(localized: "Both")
  static let scopeDescription = String(localized: "Description")
  static let matchCase = String(localized: "Match Case")
  static let shorts = String(localized: "Shorts")
  static let live = String(localized: "Live")
  #if os(macOS)
    static let hideVideosUnder = String(localized: "Hide videos under")
  #else
    static let hideVideosUnder = String(localized: "Hide Videos Under")
  #endif
  static let seconds = String(localized: "seconds")
  static let noRecentVideos = String(localized: "No recent videos.")
  static let previewFailed = String(localized: "Couldn't load this channel's videos.")

  static func showChannelInFeed(_ title: String) -> String {
    String(localized: "Show \(title) in Feed")
  }

  static func filtersFor(_ title: String) -> String {
    String(localized: "Filters for \(title)")
  }

  static let choiceShow = String(localized: "Show")
  static let choiceHide = String(localized: "Hide")
  static let choiceOnly = String(localized: "Only")

  static func shortsOption(_ filter: ShortsFilter) -> String {
    switch filter {
    case .all: choiceShow
    case .normal: choiceHide
    case .shorts: choiceOnly
    }
  }

  static func liveOption(_ filter: LiveFilter) -> String {
    switch filter {
    case .all: choiceShow
    case .normal: choiceHide
    case .vod: choiceOnly
    }
  }

  static func scopeOption(_ scope: FilterScope) -> String {
    switch scope {
    case .title: scopeTitle
    case .both: scopeBoth
    case .description: scopeDescription
    }
  }

  static let summaryOff = String(localized: "Off")
  static let summaryAllVideos = String(localized: "All videos")
  static let summaryPlaylists = String(localized: "Playlists")
  static let summaryNoShorts = String(localized: "No Shorts")
  static let summaryShortsOnly = String(localized: "Shorts only")
  static let summaryRegularOnly = String(localized: "Regular uploads only")
  static let summaryLiveOnly = String(localized: "Live & replays only")
  static let summaryFollowed = String(localized: "Followed in SubTube")

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
    String(localized: "Hides videos under \(seconds) seconds")
  }

  static let general = String(localized: "General")
  static let account = String(localized: "Account")
  static let sync = String(localized: "Sync")
  static let syncedWithDrive = String(localized: "Synced with Google Drive")
  static let syncExplanation = String(
    localized:
      "Your channels, filters and watched list are kept in a hidden SubTube folder in your Drive.")
  static let syncing = String(localized: "Syncing…")
  static let appearance = String(localized: "Appearance")
  static let theme = String(localized: "Theme")
  static let signOut = String(localized: "Sign Out")
  static let signOutFootnote = String(
    localized: "Your settings stay in your Drive. Sign back in to get them.")

  static let deleteProfile = String(localized: "Delete Profile")
  static let deleteProfileDetail = String(
    localized:
      "Deletes your filters, followed channels and watched marks from Google Drive, on all your devices. Your YouTube account isn't changed."
  )
  static let deleteProfileTitle = String(localized: "Delete your profile?")
  static let deleteProfileMessage = String(
    localized:
      "This deletes your filters, followed channels and watched marks from Google Drive and from this device. It can't be undone."
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
    localized: "New videos from the channels you subscribe to, newest first.")
  static let nuxBulletFilters = String(
    localized: "Filters for each channel hide Shorts, live streams, or titles you don't want.")
  static let nuxBulletWatched = String(
    localized: "What you've watched is remembered on all your devices.")
  static let getStarted = String(localized: "Get Started")
  #if os(macOS)
    static let signInHeading = String(localized: "Sign In with Google")
    static let chooseChannels = String(localized: "Choose Channels")
    static let tryAFilter = String(localized: "Try a Filter")
    static let hideTitles = String(localized: "Hide Titles")
    static let youreSet = String(localized: "You're Set")
    static let doneDetail = String(
      localized:
        "Your feed starts with the newest video you haven't watched. Click one to play it. When you close it, it's marked watched."
    )
  #else
    static let signInHeading = String(localized: "Sign in with Google")
    static let chooseChannels = String(localized: "Choose channels")
    static let tryAFilter = String(localized: "Try a filter")
    static let hideTitles = String(localized: "Hide titles")
    static let youreSet = String(localized: "You're set")
    static let doneDetail = String(
      localized:
        "Your feed starts with the newest video you haven't watched. Tap one to play it. When you close it, it's marked watched."
    )
  #endif
  static let noServer = String(
    localized:
      "SubTube has no server of its own. Your data stays in your Google account and on this device."
  )
  static let signIn = String(localized: "Sign In with Google")
  static let signInShort = String(localized: "Sign In")
  static let privacyPolicy = String(localized: "Privacy Policy")
  static let permissionsIntro = String(localized: "SubTube asks Google for two permissions:")
  static let permissionYouTube = String(localized: "Read your YouTube subscriptions")
  static let permissionYouTubeDetail = String(
    localized: "So it knows which channels to show. It can't change anything on your YouTube account.")
  static let permissionDrive = String(localized: "Keep its settings in your Google Drive")
  static let permissionDriveDetail = String(
    localized:
      "In a hidden folder that only SubTube can open. It holds your filters and what you've watched. SubTube can't see your other files."
  )
  static let chooseChannelsDetail = String(
    localized: "Your subscriptions start on. Turn off any you don't want in your feed.")
  static let noSubscriptions = String(
    localized:
      "You don't subscribe to any channels yet. Subscribe on YouTube and they'll show up here.")
  static let searchChannels = String(localized: "Search channels")
  static let turnAllOff = String(localized: "Turn All Off")
  static let turnAllOn = String(localized: "Turn All On")
  static let hideShorts = String(localized: "Hide Shorts")
  static let exampleChannel = String(localized: "Example channel")
  static let tryAFilterDetail = String(
    localized:
      "Each channel can have its own filter. Let's set one up on an example channel. You can change it any time under Channels."
  )
  static let hideShortsDetail = String(
    localized: "Choose whether this channel shows Shorts. The preview shows what you'd see.")
  static let hideTitlesDetail = String(
    localized: "Type a word, and videos with it in the title are hidden, like “live” or “trailer”.")
  static let openMyFeed = String(localized: "Open My Feed")

  static let hidden = String(localized: "Hidden")

  static func previewCount(_ shown: Int, of total: Int) -> String {
    String(localized: "Preview: \(shown) of \(total) shown")
  }

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
      "Couldn't load the YouTube player. Check your connection or any content blockers, then close and reopen."
  )
}
