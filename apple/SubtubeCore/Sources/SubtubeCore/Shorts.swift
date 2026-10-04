import Foundation

/// Shorts are capped at 3 minutes, so a longer video can't be one.
public let shortsMaxSeconds = 180

private let probeConcurrency = 6

/// Asks `/shorts/{id}` directly: true for a Short, false for not, nil when the
/// answer was inconclusive.
public typealias ShortsProbeFunction = @Sendable (String) async -> Bool?

/// Whether a video could be a Short at all, and so is worth classifying.
public func isShortsCandidate(_ video: Video) -> Bool {
  guard let duration = video.durationSeconds else { return false }
  return duration > 0 && duration <= shortsMaxSeconds
}

/// Set `isShort` on one channel's uploads. The verdict comes from the
/// channel's Shorts list (`loadShortIds`, nil when the channel has none).
/// Should that list ever stop being served, every channel would look
/// Short-free, so with a `probe` the candidates are asked about directly
/// instead; an inconclusive answer leaves the verdict unknown.
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
