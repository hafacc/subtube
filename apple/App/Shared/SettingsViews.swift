import SubtubeCore
import SwiftUI

/// The signed-in account: avatar, name and address.
struct AccountSummary: View {
  let feed: FeedModel

  var body: some View {
    HStack(spacing: 12) {
      Avatar(
        url: feed.user?.photoLink ?? feed.account.thumbnail,
        title: feed.user?.displayName ?? feed.account.title, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(feed.user?.displayName ?? feed.account.title).font(.headline)
        if let email = feed.user?.emailAddress {
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

/// The pages the apps link to, all opened in the browser.
enum Links {
  static let privacyPolicy = URL(string: "https://subtube.hafa.cc/privacy")!
  static let terms = URL(string: "https://subtube.hafa.cc/terms")!
  static let youTube = URL(string: "https://www.youtube.com/")!
}

/// "Privacy Policy" and "Terms" side by side, each opening its page.
struct LegalLinks: View {
  var body: some View {
    HStack(spacing: 16) {
      Link(Strings.privacyPolicy, destination: Links.privacyPolicy)
      Link(Strings.terms, destination: Links.terms)
    }
    // each link takes its own taps in a list row
    .buttonStyle(.borderless)
  }
}

/// What signing in agrees to, for directly under a sign-in button.
struct SignInAgreement: View {
  var body: some View {
    Text(Strings.signInAgreement)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .tint(Color.gold)
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
    Picker(Strings.theme, selection: $app.theme) {
      ForEach(Theme.allCases) { theme in
        Text(Strings.themeOption(theme)).tag(theme)
      }
    }
    .pickerStyle(.segmented)
  }
}
