import CryptoKit
import Foundation
import os
import Security

/// The Google OAuth client the Apple apps sign in with. Public: a client id
/// grants nothing on its own, and an iOS client has no secret.
public enum GoogleClient {
  /// The iOS OAuth client (bundle id `cc.hafa.subtube`), which serves macOS
  /// too. It must be in the same Google Cloud project as the other platforms'
  /// clients, or the Drive app folder won't be shared.
  public static let iOSClientID = "932619996481-sslva839spduo9jbe3tn4ov47cc5gg4q.apps.googleusercontent.com"

  /// The reversed client id, which Google redirects back to.
  public static var redirectScheme: String {
    let prefix = iOSClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    return "com.googleusercontent.apps.\(prefix)"
  }

  public static var redirectURI: String { "\(redirectScheme):/oauthredirect" }

  public static let scopes = [
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/drive.appdata",
  ]

  static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
  static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
  static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
}

/// Why signing in or renewing a token failed.
public enum AuthError: Error, Sendable, Equatable {
  /// Only an interactive sign-in can produce a token.
  case signInRequired
  /// Google's redirect didn't carry what was asked for.
  case invalidCallback(String)
  /// The token endpoint refused, with its body.
  case tokenRequestFailed(String)
}

extension AuthError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .signInRequired: "Sign in again to continue."
    case .invalidCallback(let detail): "Google sign-in failed: \(detail)"
    case .tokenRequestFailed(let detail): "Google sign-in failed: \(detail)"
    }
  }
}

/// One interactive sign-in in progress: the URL to open and what checks its
/// answer.
public struct AuthorizationRequest: Sendable {
  public var url: URL
  public var callbackScheme: String
  let verifier: String
  let state: String
}

private func base64URL(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

private func randomToken(byteCount: Int = 32) -> String {
  var generator = SystemRandomNumberGenerator()
  return base64URL(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

/// The S256 PKCE challenge for a verifier.
func pkceChallenge(_ verifier: String) -> String {
  base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
}

/// A generic-password item in the Keychain.
public struct KeychainItem: Sendable {
  public var service: String
  public var account: String

  public init(service: String, account: String) {
    self.service = service
    self.account = account
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  public func read() -> String? {
    var query = query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  public func write(_ value: String) {
    let attributes: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
  }

  public func delete() {
    SecItemDelete(query as CFDictionary)
  }
}

/// Google sign-in for the Apple apps: Authorization Code + PKCE against the iOS
/// client, no secret. The refresh token lives in the Keychain; access tokens
/// live only in memory and are re-minted from it silently.
public actor GoogleAuth: AccessTokenSource {
  // Renew a little before expiry so in-flight calls never 401.
  private static let refreshMargin: TimeInterval = 5 * 60

  private let keychain: KeychainItem
  private let session: URLSession
  private var accessToken: String?
  private var expiresAt = Date.distantPast
  private var renewal: Task<String, Error>?

  public init(
    keychain: KeychainItem = KeychainItem(service: "cc.hafa.subtube", account: "google-refresh-token"),
    session: URLSession = .shared
  ) {
    self.keychain = keychain
    self.session = session
  }

  /// Whether a sign-in is remembered, so a token can be had without UI.
  public var isSignedIn: Bool { keychain.read() != nil }

  /// Start an interactive sign-in; open `url` in a web authentication session
  /// and hand its callback to ``completeSignIn(callback:request:)``.
  public nonisolated func authorizationRequest() -> AuthorizationRequest {
    let verifier = randomToken()
    let state = randomToken(byteCount: 16)
    var components = URLComponents(
      url: GoogleClient.authorizationEndpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: GoogleClient.iOSClientID),
      URLQueryItem(name: "redirect_uri", value: GoogleClient.redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: GoogleClient.scopes.joined(separator: " ")),
      URLQueryItem(name: "code_challenge", value: pkceChallenge(verifier)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state),
    ]
    return AuthorizationRequest(
      url: components.url!, callbackScheme: GoogleClient.redirectScheme, verifier: verifier,
      state: state)
  }

  /// Exchange the code in Google's redirect for tokens, and remember the
  /// sign-in.
  public func completeSignIn(callback: URL, request: AuthorizationRequest) async throws {
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    if let error = value("error") {
      throw AuthError.invalidCallback(error)
    }
    guard value("state") == request.state else {
      throw AuthError.invalidCallback("state mismatch")
    }
    guard let code = value("code") else {
      throw AuthError.invalidCallback("no code")
    }
    let response = try await tokenRequest([
      "client_id": GoogleClient.iOSClientID,
      "code": code,
      "code_verifier": request.verifier,
      "grant_type": "authorization_code",
      "redirect_uri": GoogleClient.redirectURI,
    ])
    guard let refreshToken = response.refreshToken else {
      throw AuthError.tokenRequestFailed("no refresh token")
    }
    keychain.write(refreshToken)
    apply(response)
  }

  private struct TokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Double
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case expiresIn = "expires_in"
      case refreshToken = "refresh_token"
    }
  }

  private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
    var request = URLRequest(url: GoogleClient.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(formEncode(form).utf8)
    let (body, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let text = String(decoding: body, as: UTF8.self)
    if status == 400 && text.contains("invalid_grant") {
      // revoked or expired: only a new sign-in helps
      keychain.delete()
      throw AuthError.signInRequired
    }
    guard (200..<300).contains(status) else {
      // worded like any other failed Google request; the body is only logged
      Logger(subsystem: "cc.hafa.subtube", category: "auth")
        .error("token request failed: \(status) \(text, privacy: .public)")
      throw GoogleAPIError.http(status: status, body: text)
    }
    return try JSONDecoder().decode(TokenResponse.self, from: body)
  }

  private func apply(_ response: TokenResponse) {
    accessToken = response.accessToken
    expiresAt = Date().addingTimeInterval(response.expiresIn)
  }

  public func validToken() async throws -> String {
    if let accessToken, Date() < expiresAt.addingTimeInterval(-Self.refreshMargin) {
      return accessToken
    } else {
      return try await refreshedToken()
    }
  }

  public func refreshedToken() async throws -> String {
    if let renewal {
      return try await renewal.value
    }
    let task = Task { try await self.renew() }
    renewal = task
    defer { renewal = nil }
    return try await task.value
  }

  private func renew() async throws -> String {
    guard let refreshToken = keychain.read() else {
      throw AuthError.signInRequired
    }
    let response = try await tokenRequest([
      "client_id": GoogleClient.iOSClientID,
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
    ])
    apply(response)
    return response.accessToken
  }

  /// Forget the sign-in and revoke it at Google, which also ends every access
  /// token minted from it.
  public func signOut() async {
    let refreshToken = keychain.read()
    keychain.delete()
    accessToken = nil
    expiresAt = .distantPast
    guard let refreshToken else { return }
    var request = URLRequest(url: GoogleClient.revokeEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(formEncode(["token": refreshToken]).utf8)
    // an unrevoked grant still can't be used without the deleted refresh token
    _ = try? await session.data(for: request)
  }
}

private func formEncode(_ form: [String: String]) -> String {
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-._~")
  return form.sorted { $0.key < $1.key }
    .map { key, value in
      "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
    }
    .joined(separator: "&")
}
