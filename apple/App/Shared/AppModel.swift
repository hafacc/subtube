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
  /// Set once any account finished the first run here; setup then opens on sign-in.
  private static let introSeenKey = "subtube.onboarded"
  private static let themeKey = "subtube.theme"
  private static let perAccountKey = "subtube.onboarded.perAccount"

  private static func onboardedKey(_ accountId: String) -> String {
    "subtube.onboarded.\(accountId)"
  }

  let auth = GoogleAuth()
  private(set) var phase: Phase = .checking
  private(set) var signingIn = false
  private(set) var error: String?
  private(set) var deletingProfile = false
  /// Why the last Delete Profile didn't happen.
  private(set) var deleteError: String?

  /// Whether the signed-in account finished the first run on this device.
  private(set) var onboarded = false
  /// Whether the first run was ever finished on this device, by any account.
  private(set) var introSeen = UserDefaults.standard.bool(forKey: AppModel.introSeenKey)

  var theme: Theme = AppModel.startingTheme {
    didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
  }

  /// The saved theme; a debug build's `-theme:<light|dark>` goes before it
  /// and is not saved.
  private static var startingTheme: Theme {
    #if DEBUG
      if let asked = debugArgument("theme").flatMap(Theme.init(rawValue:)) {
        return asked
      }
    #endif
    return Theme(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") ?? .system
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
        introSeen = onboarded
        if CommandLine.arguments.contains("-signedOut") {
          phase = .signedOut
        } else {
          let feed = FeedModel.demo(auth: auth)
          phase = .signedIn(feed)
          if let channelId = debugArgument("select") {
            feed.selectedChannel = channelId
          }
          if CommandLine.arguments.contains("-play") {
            feed.demoPlay(videoId: debugArgument("video"))
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
        // the mark was one per device before it was kept per account
        if introSeen, !UserDefaults.standard.bool(forKey: Self.perAccountKey) {
          markOnboarded(account.channelId)
        }
        UserDefaults.standard.set(true, forKey: Self.perAccountKey)
        try await open(account)
      } else {
        try await openAccount()
      }
    } catch {
      self.error = Strings.message(for: error, signedOut: Strings.signInAgain)
      phase = .signedOut
    }
  }

  /// Sign in interactively; says whether someone is now signed in.
  /// `authenticate` opens Google's page and returns the redirect it ends on.
  @discardableResult
  func signIn(authenticate: (URL, String) async throws -> URL) async -> Bool {
    signingIn = true
    error = nil
    defer { signingIn = false }
    do {
      let request = auth.authorizationRequest()
      let callback = try await authenticate(request.url, request.callbackScheme)
      try await auth.completeSignIn(callback: callback, request: request)
      do {
        try await openAccount()
      } catch {
        // a sign-in the app can't use isn't kept
        if feed == nil {
          await auth.signOut(revoke: false)
        }
        throw error
      }
      return true
    } catch ASWebAuthenticationSessionError.canceledLogin {
      // closing Google's page is not an error
      return false
    } catch {
      appLog.error("sign-in failed: \(String(describing: error), privacy: .public)")
      self.error = Strings.message(for: error, signedOut: Strings.signInAgain)
      return false
    }
  }

  private func openAccount() async throws {
    let account = try await YouTubeClient(accessToken: await auth.validToken()).myChannel()
    UserDefaults.standard.set(try JSONEncoder().encode(account), forKey: Self.accountKey)
    try await open(account)
  }

  /// Show an account's feed, or setup when it hasn't finished that here and
  /// no other device has.
  private func open(_ account: ChannelSummary) async throws {
    let defaults = UserDefaults.standard
    var done = defaults.bool(forKey: Self.onboardedKey(account.channelId))
    if !done {
      done = try await isSetUpElsewhere()
      if done {
        markOnboarded(account.channelId)
      }
    }
    onboarded = done
    if let feed, feed.account.channelId == account.channelId {
      feed.reconnected(items: done)
    } else {
      phase = .signedIn(makeFeed(account))
    }
  }

  private func makeFeed(_ account: ChannelSummary) -> FeedModel {
    let feed = FeedModel(account: account, auth: auth)
    feed.onProfileDeleted = { [weak self, weak feed] in
      if let feed {
        self?.profileDeletedElsewhere(feed)
      }
    }
    return feed
  }

  /// The profile is gone from Drive: start setup again, still signed in,
  /// unless another device has set the account up again meanwhile.
  private func profileDeletedElsewhere(_ deleted: FeedModel) {
    guard !deletingProfile, feed === deleted else { return }
    let account = deleted.account
    setOnboarded(false, account.channelId)
    deleted.player = nil
    Task {
      // a failed check leaves setup showing, which asks again at sign-in
      let elsewhere = (try? await isSetUpElsewhere()) ?? false
      if feed === deleted, !deletingProfile {
        if elsewhere {
          setOnboarded(true, account.channelId)
        }
        phase = .signedIn(makeFeed(account))
      }
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
    let accountId = feed.account.channelId
    await signOut(revoke: true)
    UserDefaults.standard.removeObject(forKey: Self.onboardedKey(accountId))
  }

  private func markOnboarded(_ accountId: String) {
    UserDefaults.standard.set(true, forKey: Self.onboardedKey(accountId))
    UserDefaults.standard.set(true, forKey: Self.introSeenKey)
    introSeen = true
  }

  private func setOnboarded(_ value: Bool, _ accountId: String) {
    onboarded = value
    if value {
      markOnboarded(accountId)
    } else {
      UserDefaults.standard.removeObject(forKey: Self.onboardedKey(accountId))
    }
  }

  /// Whether the account's Drive app folder holds another device's file;
  /// this device's own, written by a setup not finished here, doesn't count.
  private func isSetUpElsewhere() async throws -> Bool {
    let files: [DriveFile]
    do {
      files = try await DriveClient(accessToken: await auth.validToken()).listAppFiles()
    } catch GoogleAPIError.tokenExpired {
      files = try await DriveClient(accessToken: await auth.refreshedToken()).listAppFiles()
    }
    return setUpElsewhere(files.map(\.name), ownName: "device-\(deviceId()).json")
  }

  func finishOnboarding() {
    if let feed {
      setOnboarded(true, feed.account.channelId)
    }
  }

  /// Upload what is unsent and forget the account on this device. Google's
  /// grant stays, so other devices stay signed in, unless `revoke` is set,
  /// as Delete Profile does.
  func signOut(revoke: Bool = false) async {
    let leaving = feed
    // off the main screen at once; the upload and Google's answer can take a while
    phase = .signedOut
    onboarded = false
    if let leaving {
      // save what is playing and upload unsaved edits while the token still works
      leaving.player = nil
      await leaving.flush()
    }
    await auth.signOut(revoke: revoke)
    UserDefaults.standard.removeObject(forKey: Self.accountKey)
  }
}

/// Starts Google's sign-in in a web authentication session.
struct SignInButton<Label: View>: View {
  let app: AppModel
  /// Called once someone is signed in.
  var onSignedIn: () -> Void = {}
  @ViewBuilder let label: Label
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  var body: some View {
    Button {
      Task {
        let signedIn = await app.signIn { url, scheme in
          try await webAuthenticationSession.authenticate(
            using: url, callbackURLScheme: scheme, preferredBrowserSession: .shared)
        }
        if signedIn {
          onSignedIn()
        }
      }
    } label: {
      label
    }
    .disabled(app.signingIn)
  }
}

/// Google's own "Sign in with Google" button: its four-colour mark on a
/// neutral fill, white in light and near-black in dark, as Google's sign-in
/// branding asks. Every place that offers the sign-in uses it.
struct GoogleSignInButton: View {
  let app: AppModel
  var fullWidth = false
  /// Called once someone is signed in.
  var onSignedIn: () -> Void = {}

  var body: some View {
    SignInButton(app: app, onSignedIn: onSignedIn) {
      HStack(spacing: 12) {
        if app.signingIn {
          ProgressView().controlSize(.small).frame(width: 18, height: 18)
        } else {
          Image("GoogleG")
            .resizable()
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
        }
        Text(Strings.signIn)
      }
    }
    .buttonStyle(GoogleButtonStyle(fullWidth: fullWidth))
  }
}

/// The neutral box of Google's sign-in button, sized like the app's main button.
private struct GoogleButtonStyle: ButtonStyle {
  var fullWidth = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  // Google's light and dark button colours
  private var fill: Color {
    colorScheme == .dark
      ? Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x14 / 255) : .white
  }

  private var stroke: Color {
    colorScheme == .dark
      ? Color(red: 0x8E / 255, green: 0x91 / 255, blue: 0x8F / 255)
      : Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255)
  }

  private var text: Color {
    colorScheme == .dark
      ? Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255)
      : Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
  }

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: fullWidth ? 25 : 6, style: .continuous)
    configuration.label
      .font(fullWidth ? .headline.weight(.medium) : .body.weight(.medium))
      .foregroundStyle(text)
      .padding(.horizontal, 12)
      .frame(maxWidth: fullWidth ? .infinity : nil)
      .frame(minHeight: fullWidth ? 50 : 40)
      .background(fill, in: shape)
      .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
      .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.5))
      .contentShape(Rectangle())
  }
}
