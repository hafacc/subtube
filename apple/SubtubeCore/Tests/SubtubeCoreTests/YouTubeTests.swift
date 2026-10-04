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

@Suite struct HTMLEntitiesTests {
  @Test func decodesNamedAndNumericEntities() {
    #expect(decodeHTMLEntities("Tom &amp; Jerry") == "Tom & Jerry")
    #expect(decodeHTMLEntities("don&#39;t &#x2014; &quot;x&quot;") == "don't \u{2014} \"x\"")
    #expect(decodeHTMLEntities("a & b &bogus; c") == "a & b &bogus; c")
  }
}
