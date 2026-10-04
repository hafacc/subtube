import Testing

@testable import SubtubeCore

private func video(_ videoId: String, _ durationSeconds: Int) -> Video {
  makeVideo(videoId, durationSeconds: durationSeconds) { $0.liveStatus = nil }
}

private func verdicts(_ videos: [Video]) -> [String: Bool?] {
  Dictionary(uniqueKeysWithValues: videos.map { ($0.videoId, $0.isShort) })
}

@Suite struct ClassifyShortsTests {
  @Test func skipsTheShortsListWhenNothingIsShortEnough() async throws {
    var asked = false
    let result = try await classifyShorts([video("long", 600)]) {
      asked = true
      return []
    }
    #expect(!asked)
    #expect(verdicts(result) == ["long": false])
  }

  @Test func judgesCandidatesByTheShortsList() async throws {
    let result = try await classifyShorts(
      [video("short", 30), video("clip", 90), video("long", 600)]
    ) { ["short", "long"] }
    #expect(verdicts(result) == ["short": true, "clip": false, "long": false])
  }

  @Test func aChannelWithNoShortsListHasNoShorts() async throws {
    let result = try await classifyShorts([video("clip", 90)]) { nil }
    #expect(verdicts(result) == ["clip": false])
  }

  @Test func probesWhenThereIsNoListAndThePlatformCan() async throws {
    let result = try await classifyShorts(
      [video("short", 30), video("unsure", 40), video("long", 600)],
      loadShortIds: { nil },
      probe: { videoId in videoId == "short" ? true : nil }
    )
    let expected: [String: Bool?] = ["short": true, "unsure": Bool?.none, "long": false]
    #expect(verdicts(result) == expected)
  }

  @Test func probeVerdictFromStatus() {
    #expect(ShortsProbe.verdict(status: 200) == true)
    #expect(ShortsProbe.verdict(status: 303) == false)
    #expect(ShortsProbe.verdict(status: 404) == nil)
  }
}
