import SubtubeCore
import SwiftUI

/// The signed-in account: avatar, name and address.
struct AccountSummary: View {
  let feed: FeedModel

  var body: some View {
    HStack(spacing: 12) {
      Avatar(
        url: feed.user?.photoLink ?? feed.account.photo ?? "",
        title: feed.user?.displayName ?? feed.account.name, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(feed.user?.displayName ?? feed.account.name).font(.headline)
        if let email = feed.user?.emailAddress ?? feed.account.email {
          Text(email).font(.callout).foregroundStyle(.secondary)
        }
      }
    }
    .task { await feed.loadUser() }
  }
}

/// "Synced with Google Drive" and when it last was.
struct SyncStatus: View {
  let feed: FeedModel
  var showsExplanation = true

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.icloud")
        .font(.title3)
        .foregroundStyle(Color.gold)
      VStack(alignment: .leading, spacing: 3) {
        Text(Strings.syncedWithDrive).font(.body.weight(.semibold))
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(lastSynced(now: context.date))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if showsExplanation {
          Text(Strings.syncExplanation)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
    .task {
      while !Task.isCancelled {
        await feed.refreshSyncTime()
        try? await Task.sleep(for: .seconds(5))
      }
    }
  }

  private func lastSynced(now: Date) -> String {
    if let date = feed.lastSyncedAt {
      // under a minute reads "now", never a count of seconds
      let shown = now.timeIntervalSince(date) < 60 ? now : date
      return Strings.lastSynced(
        shown.formatted(.relative(presentation: .named, unitsStyle: .wide)))
    } else {
      return Strings.syncing
    }
  }
}

/// Delete Profile, asking first.
struct DeleteProfileButton: View {
  let app: AppModel
  @State private var confirming = false

  var body: some View {
    Button(Strings.deleteProfile, role: .destructive) {
      confirming = true
    }
    .disabled(app.deletingProfile)
    #if DEBUG
      .onAppear {
        if CommandLine.arguments.contains("-confirmDelete") {
          confirming = true
        }
      }
    #endif
    .alert(Strings.deleteProfileTitle, isPresented: $confirming) {
      Button(Strings.deleteProfile, role: .destructive) {
        Task { await app.deleteProfile() }
      }
      Button(Strings.cancel, role: .cancel) {}
    } message: {
      Text(Strings.deleteProfileMessage)
    }
  }
}

/// What Delete Profile does, and why it last failed.
struct DeleteProfileFootnote: View {
  let app: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(Strings.deleteProfileDetail)
      if let error = app.deleteError {
        Text(error).foregroundStyle(.red)
      }
    }
  }
}

/// The addresses the apps link to: the two pages they also show themselves,
/// and those opened in the browser.
enum Links {
  static let privacyPolicy = URL(string: "https://subtube.hafa.cc/privacy")!
  static let terms = URL(string: "https://subtube.hafa.cc/terms")!
  static let feedback = URL(string: "https://github.com/hafacc/subtube/issues")!
  static let youTube = URL(string: "https://www.youtube.com/")!
}

/// "Privacy Policy", "Terms" and "Feedback" side by side: the first two show
/// their page through `show`, Feedback opens the issue list in the browser.
struct LegalLinks: View {
  let show: (InfoPageKind) -> Void

  var body: some View {
    HStack(spacing: 16) {
      Button(Strings.privacyPolicy) { show(.privacy) }
      Button(Strings.terms) { show(.terms) }
      Link(Strings.feedback, destination: Links.feedback)
    }
    #if os(macOS)
      // the link style draws the system's blue, whatever the tint
      .buttonStyle(.plain)
      .foregroundStyle(Color.gold)
    #else
      // each link takes its own taps in a list row
      .buttonStyle(.borderless)
    #endif
  }
}

/// What signing in agrees to, for directly under a sign-in button; its two
/// links show their page in a sheet.
struct SignInAgreement: View {
  @State private var shown: InfoPageKind?

  var body: some View {
    Text(Strings.signInAgreement)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .tint(Color.gold)
      .environment(
        \.openURL,
        OpenURLAction { url in
          if let kind = InfoPageKind(web: url) {
            shown = kind
            return .handled
          } else {
            return .systemAction
          }
        }
      )
      .sheet(item: $shown) { InfoPageSheet(kind: $0) }
  }
}

/// "Videos from YouTube", small and muted, as a link to YouTube.
struct YouTubeAttribution: View {
  var body: some View {
    Link(destination: Links.youTube) {
      Text(Strings.videosFromYouTube)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
  }
}

/// The theme choice: System, Light or Dark.
struct ThemePicker: View {
  @Bindable var app: AppModel

  var body: some View {
    #if os(macOS)
      SegmentedRow(
        label: Strings.theme, selection: $app.theme,
        options: Theme.allCases.map { ($0, Strings.themeOption($0)) })
    #else
      Picker(Strings.theme, selection: $app.theme) {
        ForEach(Theme.allCases) { theme in
          Text(Strings.themeOption(theme)).tag(theme)
        }
      }
      .pickerStyle(.segmented)
    #endif
  }
}
