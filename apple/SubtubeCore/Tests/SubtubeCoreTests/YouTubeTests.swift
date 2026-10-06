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

  @Test func saysExactlyWhatTheOtherClientsSay() {
    #expect(
      GoogleAPIError.dailyLimit.localizedDescription
        == "SubTube has reached YouTube's daily limit. Try again after midnight Pacific time.")
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

/// Answers every request with one status and counts them per playlist id.
private final class StatusStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status = 500
  nonisolated(unsafe) static var counts: [String: Int] = [:]
  private static let lock = NSLock()

  static func session(status: Int) -> URLSession {
    lock.withLock {
      Self.status = status
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
    let status = Self.lock.withLock {
      Self.counts[playlistId, default: 0] += 1
      return Self.status
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(
      self, didLoad: Data(#"{"error": {"status": "INTERNAL", "message": "Internal error encountered."}}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized) struct ShortsListFailureTests {
  private let channelId = "UC7-E5xhZBZdW-8d7V80mzfg"

  @Test func aServerErrorOnTheShortsListMeansNoList() async throws {
    let client = YouTubeClient(accessToken: "token", session: StatusStub.session(status: 500))
    #expect(try await client.shortIds(channelId: channelId) == nil)
    #expect(StatusStub.count(shortsPlaylistId(channelId)) == 2)
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
