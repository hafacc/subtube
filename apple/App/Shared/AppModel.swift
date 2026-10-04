import AuthenticationServices
import Foundation
import Observation
import SubtubeCore
import SwiftUI

/// Who is signed in, the feed that belongs to them, and the app-wide settings.
@MainActor @Observable
final class AppModel {
  enum Phase {
    /// Looking for a remembered sign-in.
    case checking
    case signedOut
    case signedIn(FeedModel)
  }

  private static let accountKey = "subtube.account"
  private static let onboardedKey = "subtube.onboarded"
  private static let themeKey = "subtube.theme"

  let auth = GoogleAuth()
  private(set) var phase: Phase = .checking
  private(set) var signingIn = false
  private(set) var error: String?
  private(set) var deletingProfile = false
  /// Why the last Delete Profile didn't happen.
  private(set) var deleteError: String?

  /// Whether this device finished the first run.
  private(set) var onboarded = UserDefaults.standard.bool(forKey: AppModel.onboardedKey)

  var theme: Theme = Theme(rawValue: UserDefaults.standard.string(forKey: AppModel.themeKey) ?? "")
    ?? .system
  {
    didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
  }

  /// The signed-in account's feed, or nil.
  var feed: FeedModel? {
    if case .signedIn(let feed) = phase {
      return feed
    } else {
      return nil
    }
  }

  /// Restore a remembered sign-in without UI.
  func start() async {
    guard case .checking = phase else { return }
    #if DEBUG
      if CommandLine.arguments.contains("-demo") {
        onboarded = !CommandLine.arguments.contains("-nux")
        let arguments = CommandLine.arguments
        if arguments.contains("-signedOut") {
          phase = .signedOut
        } else {
          let feed = FeedModel.demo(auth: auth)
          phase = .signedIn(feed)
          if let channelId = arguments.first(where: { $0.hasPrefix("-select:") }) {
            feed.selectedChannel = String(channelId.dropFirst("-select:".count))
          }
          if arguments.contains("-hideWatched") {
            feed.hideWatched = true
          }
          if arguments.contains("-play") {
            feed.demoPlay()
          }
        }
        return
      }
    #endif
    guard await auth.isSignedIn else {
      phase = .signedOut
      return
    }
    do {
      if let saved = UserDefaults.standard.data(forKey: Self.accountKey),
        let account = try? JSONDecoder().decode(ChannelSummary.self, from: saved)
      {
        try await skipSetupIfSynced()
        phase = .signedIn(makeFeed(account))
      } else {
        try await openAccount()
      }
    } catch {
      self.error = error.localizedDescription
      phase = .signedOut
    }
  }

  /// Sign in interactively. `authenticate` opens Google's page and returns
  /// the redirect it ends on.
  func signIn(authenticate: (URL, String) async throws -> URL) async {
    signingIn = true
    error = nil
    defer { signingIn = false }
    do {
      let request = auth.authorizationRequest()
      let callback = try await authenticate(request.url, request.callbackScheme)
      try await auth.completeSignIn(callback: callback, request: request)
      try await openAccount()
    } catch ASWebAuthenticationSessionError.canceledLogin {
      // closing Google's page is not an error
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func openAccount() async throws {
    let account = try await YouTubeClient(accessToken: await auth.validToken()).myChannel()
    UserDefaults.standard.set(try JSONEncoder().encode(account), forKey: Self.accountKey)
    try await skipSetupIfSynced()
    if let feed, feed.account.channelId == account.channelId {
      feed.reconnected()
    } else {
      phase = .signedIn(makeFeed(account))
    }
  }

  private func makeFeed(_ account: ChannelSummary) -> FeedModel {
    let feed = FeedModel(account: account, auth: auth)
    feed.onProfileDeleted = { [weak self] in self?.profileDeletedElsewhere(account) }
    return feed
  }

  /// The profile is gone from Drive: start setup again, still signed in,
  /// unless another device has set the account up again meanwhile.
  private func profileDeletedElsewhere(_ account: ChannelSummary) {
    setOnboarded(false)
    Task {
      // a failed check leaves setup showing, which asks again at sign-in
      try? await skipSetupIfSynced()
      phase = .signedIn(makeFeed(account))
    }
  }

  /// Delete the profile everywhere, then sign out to the first setup screen.
  func deleteProfile() async {
    guard let feed, !deletingProfile else { return }
    deletingProfile = true
    deleteError = nil
    defer { deletingProfile = false }
    do {
      try await feed.deleteProfile()
    } catch {
      appLog.error("delete profile failed: \(String(describing: error), privacy: .public)")
      deleteError = Strings.deleteProfileFailed
      return
    }
    setOnboarded(false)
    await signOut()
  }

  private func setOnboarded(_ value: Bool) {
    onboarded = value
    UserDefaults.standard.set(value, forKey: Self.onboardedKey)
  }

  /// Finish the first run without showing it when the account's Drive app
  /// folder already holds a device's file.
  private func skipSetupIfSynced() async throws {
    guard !onboarded else { return }
    let files: [DriveFile]
    do {
      files = try await DriveClient(accessToken: await auth.validToken()).listAppFiles()
    } catch GoogleAPIError.tokenExpired {
      files = try await DriveClient(accessToken: await auth.refreshedToken()).listAppFiles()
    }
    if hasSyncedProfile(files.map(\.name)) {
      finishOnboarding()
    }
  }

  func finishOnboarding() {
    setOnboarded(true)
  }

  func signOut() async {
    if let feed {
      // upload unsaved marks while the token still works
      await feed.flush()
    }
    await auth.signOut()
    UserDefaults.standard.removeObject(forKey: Self.accountKey)
    phase = .signedOut
  }
}

/// Starts Google's sign-in in a web authentication session.
struct SignInButton<Label: View>: View {
  let model: AppModel
  @ViewBuilder let label: Label
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  var body: some View {
    Button {
      Task {
        await model.signIn { url, scheme in
          try await webAuthenticationSession.authenticate(
            using: url, callbackURLScheme: scheme, preferredBrowserSession: .shared)
        }
      }
    } label: {
      label
    }
    .disabled(model.signingIn)
  }
}

/// "Sign In with Google" with the G mark, as a Sunflower button.
struct GoogleSignInButton: View {
  let model: AppModel
  var fullWidth = false

  var body: some View {
    SignInButton(model: model) {
      HStack(spacing: 8) {
        if model.signingIn {
          ProgressView().controlSize(.small)
        } else {
          GoogleMark()
        }
        Text(Strings.signIn)
      }
    }
    .buttonStyle(ProminentButtonStyle(fullWidth: fullWidth))
  }
}
