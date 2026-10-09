import Foundation
import Testing

@testable import SubtubeCore

@Suite struct PlaylistIdTests {
  @Test func swapsTheChannelPrefix() {
    #expect(uploadsPlaylistId("UCabcdef12345") == "UUabcdef12345")
    #expect(shortsPlaylistId("UCabcdef12345") == "UUSHabcdef12345")
  }
}

@Suite struct ParseIsoDurationTests {
  @Test func parsesHoursMinutesAndSeconds() {
    #expect(parseIsoDuration("PT1H2M3S") == 3723)
    #expect(parseIsoDuration("PT45S") == 45)
    #expect(parseIsoDuration("PT3M") == 180)
    #expect(parseIsoDuration("PT2H") == 7200)
  }

  @Test func parsesDays() {
    #expect(parseIsoDuration("P1DT2H") == 93600)
    #expect(parseIsoDuration("P1D") == 86400)
    #expect(parseIsoDuration("P2D") == 172_800)
  }

  @Test func liveAndUnparseableYieldZero() {
    #expect(parseIsoDuration("P0D") == 0)
    #expect(parseIsoDuration("") == 0)
    #expect(parseIsoDuration("garbage") == 0)
  }
}

@Suite struct VideoListResponseTests {
  @Test func decodesAnUpcomingVideoWithoutDuration() throws {
    let json = """
      {"items": [{"id": "upcoming", "snippet": {"liveBroadcastContent": "upcoming"},
        "contentDetails": {}}]}
      """
    let response = try JSONDecoder().decode(VideoListResponse.self, from: Data(json.utf8))
    #expect(response.items.first?.contentDetails.duration == nil)
    #expect(parseIsoDuration(response.items.first?.contentDetails.duration ?? "") == 0)
  }
}

@Suite struct VideoCategoryTests {
  @Test func asksForNoTopicDetailsAndKeepsTheSnippet() {
    let parts = videoDetailParts.split(separator: ",").map(String.init)
    #expect(!parts.contains("topicDetails"))
    #expect(parts.contains("snippet"))
  }

  @Test func decodesTheCategoryId() throws {
    let json = """
      {"items": [
        {"id": "music", "snippet": {"liveBroadcastContent": "none", "categoryId": "10"},
          "contentDetails": {"duration": "PT3M"},
          "topicDetails": {"topicCategories": ["https://en.wikipedia.org/wiki/Rock_music"]}},
        {"id": "none", "snippet": {"liveBroadcastContent": "none"},
          "contentDetails": {"duration": "PT3M"}}]}
      """
    let response = try JSONDecoder().decode(VideoListResponse.self, from: Data(json.utf8))
    #expect(response.items.map(\.snippet.categoryId) == ["10", nil])
  }
}

@Suite struct DailyLimitTests {
  private func body(_ reason: String) -> Data {
    Data(#"{"error": {"code": 403, "errors": [{"domain": "youtube.quota", "reason": "\#(reason)"}]}}"#.utf8)
  }

  @Test func isA403WhoseReasonIsTheDailyQuota() {
    #expect(isDailyLimit(status: 403, body: body("quotaExceeded")))
    #expect(isDailyLimit(status: 403, body: body("dailyLimitExceeded")))
    #expect(!isDailyLimit(status: 403, body: body("rateLimitExceeded")))
    #expect(!isDailyLimit(status: 403, body: body("forbidden")))
    #expect(!isDailyLimit(status: 429, body: body("quotaExceeded")))
    #expect(!isDailyLimit(status: 403, body: Data("quotaExceeded".utf8)))
    #expect(!isDailyLimit(status: 403, body: Data(#"{"error": {"errors": "quotaExceeded"}}"#.utf8)))
  }

  private func response(_ status: Int) throws -> HTTPURLResponse {
    let url = try #require(URL(string: "https://example.com"))
    return try #require(
      HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
  }

  @Test func onlyAYouTubeAnswerIsReadForIt() throws {
    #expect(throws: GoogleAPIError.dailyLimit) {
      try checkGoogleResponse(try response(403), body: body("quotaExceeded"), youTube: true)
    }
    #expect(throws: GoogleAPIError.http(status: 403, body: String(decoding: body("quotaExceeded"), as: UTF8.self))) {
      try checkGoogleResponse(try response(403), body: body("quotaExceeded"))
    }
    #expect(throws: GoogleAPIError.http(status: 403, body: String(decoding: body("rateLimitExceeded"), as: UTF8.self))) {
      try checkGoogleResponse(try response(403), body: body("rateLimitExceeded"), youTube: true)
    }
  }
}

@Suite struct HTMLEntitiesTests {
  @Test func decodesNamedAndNumericEntities() {
    #expect(decodeHTMLEntities("Tom &amp; Jerry") == "Tom & Jerry")
    #expect(decodeHTMLEntities("don&#39;t &#x2014; &quot;x&quot;") == "don't \u{2014} \"x\"")
    #expect(decodeHTMLEntities("a & b &bogus; c") == "a & b &bogus; c")
  }
}

/// Answers every request with one status and body, or fails it, and counts
/// them per playlist id.
private final class StatusStub: URLProtocol, @unchecked Sendable {
  static let serverError = #"{"error": {"status": "INTERNAL", "message": "Internal error encountered."}}"#
  static let notFound =
    #"{"error": {"code": 404, "errors": [{"domain": "youtube.playlistItem", "reason": "playlistNotFound"}]}}"#

  nonisolated(unsafe) static var status = 500
  nonisolated(unsafe) static var body = serverError
  nonisolated(unsafe) static var counts: [String: Int] = [:]
  private static let lock = NSLock()

  /// A session answering `status` with `body`; a status of 0 fails every request.
  static func session(status: Int, body: String = serverError) -> URLSession {
    lock.withLock {
      Self.status = status
      Self.body = body
      counts = [:]
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StatusStub.self]
    return URLSession(configuration: configuration)
  }

  static func count(_ playlistId: String) -> Int {
    lock.withLock { counts[playlistId] ?? 0 }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    let playlistId = items?.first { $0.name == "playlistId" }?.value ?? ""
    let (status, body) = Self.lock.withLock {
      Self.counts[playlistId, default: 0] += 1
      return (Self.status, Self.body)
    }
    if status == 0 {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    } else {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}

private actor ProbeCount {
  private(set) var count = 0
  func bump() { count += 1 }
}

@Suite(.serialized) struct ShortsListFailureTests {
  private let channelId = "UC7-E5xhZBZdW-8d7V80mzfg"

  @Test func aServerErrorOnTheShortsListMeansItCouldNotBeRead() async throws {
    let client = YouTubeClient(accessToken: "token", session: StatusStub.session(status: 500))
    #expect(try await client.shortIds(channelId: channelId) == nil)
    #expect(StatusStub.count(shortsPlaylistId(channelId)) == 2)
  }

  @Test func aFailedRequestForTheShortsListMeansItCouldNotBeRead() async throws {
    let client = YouTubeClient(accessToken: "token", session: StatusStub.session(status: 0))
    #expect(try await client.shortIds(channelId: channelId) == nil)
  }

  @Test func aShortsListThatIsNotFoundIsAnEmptyOneSoNothingIsProbed() async throws {
    let client = YouTubeClient(
      accessToken: "token", session: StatusStub.session(status: 404, body: StatusStub.notFound))
    #expect(try await client.shortIds(channelId: channelId) == [])
    let probed = ProbeCount()
    let marked = try await client.markShorts(
      [makeVideo("clip", durationSeconds: 60)], channelId: channelId, maxResults: 50,
      probe: { _ in
        await probed.bump()
        return true
      })
    #expect(marked.map(\.isShort) == [false])
    #expect(await probed.count == 0)
  }

  @Test func anUploadsListThatIsNotFoundIsAnEmptyOne() async throws {
    let client = YouTubeClient(
      accessToken: "token", session: StatusStub.session(status: 404, body: StatusStub.notFound))
    #expect(try await client.uploads(channelId: channelId, channelTitle: "Channel").isEmpty)
    #expect(StatusStub.count(uploadsPlaylistId(channelId)) == 1)
  }

  @Test func theMissingPermissionAnswerIsToldFromOther403s() throws {
    let url = try #require(URL(string: "https://example.com"))
    let refused = try #require(
      HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))
    #expect(throws: GoogleAPIError.insufficientScope) {
      try checkGoogleResponse(refused, body: Data(#"{"reason": "insufficientPermissions"}"#.utf8))
    }
    #expect(throws: GoogleAPIError.insufficientScope) {
      try checkGoogleResponse(refused, body: Data("ACCESS_TOKEN_SCOPE_INSUFFICIENT".utf8))
    }
    let other = #"{"message": "insufficient storage"}"#
    #expect(throws: GoogleAPIError.http(status: 403, body: other)) {
      try checkGoogleResponse(refused, body: Data(other.utf8))
    }
  }

  @Test func aServerErrorOnTheUploadsListIsStillAnError() async {
    let client = YouTubeClient(accessToken: "token", session: StatusStub.session(status: 500))
    await #expect(throws: GoogleAPIError.self) {
      _ = try await client.uploads(
        channelId: channelId, channelTitle: "Channel", maxResults: 50, probe: nil)
    }
    #expect(StatusStub.count(uploadsPlaylistId(channelId)) == 1)
  }
}

/// Answers an uploads list of some video ids, and `videos.list` for the ids
/// asked, which it records.
private final class UploadsStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) private static var listed: [String] = []
  nonisolated(unsafe) private static var asked: [[String]] = []
  private static let lock = NSLock()

  /// A session whose uploads list holds `videoIds`.
  static func session(listing videoIds: [String]) -> URLSession {
    lock.withLock {
      listed = videoIds
      asked = []
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UploadsStub.self]
    return URLSession(configuration: configuration)
  }

  /// The ids of each `videos.list` request, in the order made.
  static var requests: [[String]] { lock.withLock { asked } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let url = request.url!
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let body: String
    if url.lastPathComponent == "videos" {
      let ids = (query.first { $0.name == "id" }?.value ?? "").split(separator: ",").map(String.init)
      Self.lock.withLock { Self.asked.append(ids) }
      let items = ids.map {
        #"{"id": "\#($0)", "snippet": {"liveBroadcastContent": "none", "categoryId": "27"},"#
          + #" "contentDetails": {"duration": "PT5M"}}"#
      }
      body = #"{"items": [\#(items.joined(separator: ","))]}"#
    } else {
      let items = Self.lock.withLock { Self.listed }.map {
        #"{"snippet": {"title": "Title", "description": "", "publishedAt": "2026-01-01T00:00:00Z","#
          + #" "thumbnails": {}}, "contentDetails": {"videoId": "\#($0)"}}"#
      }
      body = #"{"items": [\#(items.joined(separator: ","))]}"#
    }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}

@Suite(.serialized) struct KnownDetailsTests {
  private let channelId = "UC7-E5xhZBZdW-8d7V80mzfg"

  @Test func onlyAVideoThatCanNoLongerChangeIsSettled() {
    #expect(
      settledDetails(makeVideo("plain") { $0.categoryId = "10" })
        == VideoDetails(durationSeconds: 600, liveStatus: .normal, categoryId: "10"))
    #expect(settledDetails(makeVideo("ended") { $0.liveStatus = .vod })?.liveStatus == .vod)
    #expect(settledDetails(makeVideo("unsaid") { $0.liveStatus = nil })?.liveStatus == .normal)
    #expect(settledDetails(makeVideo("live") { $0.liveStatus = .live }) == nil)
    #expect(settledDetails(makeVideo("upcoming") { $0.liveStatus = .upcoming }) == nil)
    #expect(settledDetails(makeVideo("empty", durationSeconds: 0)) == nil)
    #expect(settledDetails(makeVideo("none", durationSeconds: nil)) == nil)
  }

  @Test func aKnownVideoIsNotAskedForAndReadsAsKnown() async throws {
    let client = YouTubeClient(
      accessToken: "token", session: UploadsStub.session(listing: ["held", "new"]))
    let known = [
      "held": VideoDetails(durationSeconds: 1200, liveStatus: .vod, categoryId: "10")
    ]
    let videos = try await client.uploads(
      channelId: channelId, channelTitle: "Channel", judgeShorts: false, known: known)
    #expect(UploadsStub.requests == [["new"]])
    #expect(videos.map(\.videoId) == ["held", "new"])
    #expect(videos.map(\.durationSeconds) == [1200, 300])
    #expect(videos.map(\.liveStatus) == [.vod, .normal])
    #expect(videos.map(\.categoryId) == ["10", "27"])
    #expect(videos.map(\.isShort) == [false, false])
  }

  @Test func withEveryVideoKnownNothingIsAsked() async throws {
    let client = YouTubeClient(
      accessToken: "token", session: UploadsStub.session(listing: ["held"]))
    let known = [
      "held": VideoDetails(durationSeconds: 1200, liveStatus: .normal, categoryId: nil)
    ]
    let videos = try await client.uploads(
      channelId: channelId, channelTitle: "Channel", judgeShorts: false, known: known)
    #expect(UploadsStub.requests.isEmpty)
    #expect(videos.map(\.durationSeconds) == [1200])
  }

  @Test func withNothingKnownEveryVideoIsAskedFor() async throws {
    let client = YouTubeClient(
      accessToken: "token", session: UploadsStub.session(listing: ["first", "second"]))
    let videos = try await client.uploads(
      channelId: channelId, channelTitle: "Channel", judgeShorts: false)
    #expect(UploadsStub.requests == [["first", "second"]])
    #expect(videos.map(\.durationSeconds) == [300, 300])
  }
}

@Suite struct SignInTests {
  @Test func theChallengeIsTheVerifiersHash() {
    // RFC 7636, appendix B
    #expect(
      pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  }

  @Test func signInAlwaysAsksWhichAccount() throws {
    let request = GoogleAuth().authorizationRequest()
    let items = try #require(
      URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    #expect(value("prompt") == "select_account")
    #expect(value("code_challenge_method") == "S256")
    #expect(value("response_type") == "code")
    #expect(value("redirect_uri") == GoogleClient.redirectURI)
    #expect(request.url.scheme == "https")
    #expect(request.callbackScheme == GoogleClient.redirectScheme)
  }

  @Test func decliningThePermissionsIsNotAFailure() async throws {
    let auth = GoogleAuth()
    let request = auth.authorizationRequest()
    let declined = try #require(URL(string: "\(GoogleClient.redirectURI)?error=access_denied"))
    await #expect(throws: AuthError.declined) {
      try await auth.completeSignIn(callback: declined, request: request)
    }
    let other = try #require(URL(string: "\(GoogleClient.redirectURI)?state=wrong&code=1"))
    await #expect(throws: AuthError.invalidCallback("state mismatch")) {
      try await auth.completeSignIn(callback: other, request: request)
    }
  }
}
