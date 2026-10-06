import Foundation

/// Shorts are capped at 3 minutes, so a longer video can't be one.
public let shortsMaxSeconds = 180

private let probeConcurrency = 6

/// Asks `/shorts/{id}` directly: true for a Short, false for not, nil when the
/// answer was inconclusive.
public typealias ShortsProbeFunction = @Sendable (String) async -> Bool?

/// Whether a video could be a Short at all, and so is worth classifying.
public func isShortsCandidate(_ video: Video) -> Bool {
  video.durationSeconds.map { $0 > 0 && $0 <= shortsMaxSeconds } ?? false
}

/// One channel's uploads when its Shorts list isn't read, because nothing
/// filters on Shorts: a video that can't be a Short is marked not one, and a
/// candidate is left unjudged.
public func withoutShortsList(_ videos: [Video]) -> [Video] {
  videos.map { video in
    var unjudged = video
    unjudged.isShort = isShortsCandidate(video) ? nil : false
    return unjudged
  }
}

/// Set `isShort` on one channel's uploads. The verdict comes from the
/// channel's Shorts list (`loadShortIds`: empty for a channel without
/// Shorts, nil when the list couldn't be read). Only when it couldn't be
/// read are the candidates asked about directly, with a `probe`; an
/// inconclusive answer leaves the verdict unknown.
public func classifyShorts(
  _ videos: [Video],
  loadShortIds: () async throws -> Set<String>?,
  probe: ShortsProbeFunction? = nil
) async throws -> [Video] {
  let candidates = videos.filter(isShortsCandidate)
  if candidates.isEmpty {
    return videos.map { video in
      var classified = video
      classified.isShort = false
      return classified
    }
  }
  let shortIds = try await loadShortIds()
  guard shortIds == nil, let probe else {
    return videos.map { video in
      var classified = video
      classified.isShort = isShortsCandidate(video) && (shortIds?.contains(video.videoId) ?? false)
      return classified
    }
  }
  var verdicts: [String: Bool] = [:]
  for start in stride(from: 0, to: candidates.count, by: probeConcurrency) {
    let batch = candidates[start..<min(start + probeConcurrency, candidates.count)]
    await withTaskGroup(of: (String, Bool?).self) { group in
      for video in batch {
        group.addTask { (video.videoId, await probe(video.videoId)) }
      }
      for await (videoId, verdict) in group {
        if let verdict {
          verdicts[videoId] = verdict
        }
      }
    }
  }
  return videos.map { video in
    var classified = video
    if isShortsCandidate(video) {
      classified.isShort = verdicts[video.videoId]
    } else {
      classified.isShort = false
    }
    return classified
  }
}
