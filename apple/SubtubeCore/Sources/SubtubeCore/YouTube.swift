import Foundation
import os

private let apiLog = Logger(subsystem: "cc.hafa.subtube", category: "google")

/// A failed Google API call, sorted into the cases callers act on.
public enum GoogleAPIError: Error, Sendable, Equatable {
  /// The access token expired or is missing; a fresh one may fix it.
  case tokenExpired
  /// The token lacks a scope subtube asked for: the user unticked YouTube or
  /// Drive access on Google's consent screen. Signing in again fixes it.
  case insufficientScope
  /// The playlist doesn't exist; a channel with no Shorts has no Shorts list.
  case playlistNotFound(String)
  /// The Google account has no YouTube channel to key its data by.
  case noChannel
  /// YouTube refused the request because the app's daily quota is used up;
  /// asking again today can't work.
  case dailyLimit
  /// Any other failure, with the status and response body.
  case http(status: Int, body: String)
}

/// A channel as subtube lists it outside the feed.
public struct ChannelSummary: Codable, Sendable, Hashable {
  /// The channel's `UC…` id.
  public var channelId: String
  /// The channel's name.
  public var title: String
  /// The channel's avatar URL, or empty.
  public var thumbnail: String

  /// A channel as YouTube names it.
  public init(channelId: String, title: String, thumbnail: String) {
    self.channelId = channelId
    self.title = title
    self.thumbnail = thumbnail
  }
}

/// A video's duration, broadcast kind and category, which `playlistItems`
/// doesn't carry.
public struct VideoDetails: Sendable, Hashable {
  /// Length in seconds; 0 for live or upcoming.
  public var durationSeconds: Int
  /// Broadcast kind.
  public var liveStatus: LiveStatus
  /// YouTube's category id; nil when it has none.
  public var categoryId: String?
}

/// A channel's uploads playlist: its id with `UU` in place of `UC`.
public func uploadsPlaylistId(_ channelId: String) -> String {
  "UU" + channelId.dropFirst(2)
}

/// A channel's Shorts, as their own undocumented playlist: `UUSH` in place of
/// `UC`.
public func shortsPlaylistId(_ channelId: String) -> String {
  "UUSH" + channelId.dropFirst(2)
}

/// Parse an ISO 8601 duration (`PT1H2M3S`, `P1DT4M`) to seconds. Live and
/// upcoming videos report `P0D`, which is 0; anything unparseable is 0 too.
public func parseIsoDuration(_ iso: String) -> Int {
  if let match = iso.wholeMatch(of: #/P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?/#) {
    let (_, days, hours, minutes, seconds) = match.output
    func number(_ part: Substring?) -> Int { part.flatMap { Int($0) } ?? 0 }
    return number(days) * 86400 + number(hours) * 3600 + number(minutes) * 60 + number(seconds)
  } else {
    return 0
  }
}

/// The `videos.list` parts ``YouTubeClient/videoDetails(_:)`` reads; the call
/// costs one unit whatever the parts.
let videoDetailParts = "snippet,contentDetails,liveStreamingDetails"

private let hiddenTitles: Set<String> = ["Private video", "Deleted video"]

struct Thumbnails: Decodable {
  struct Image: Decodable { var url: String }
  var `default`: Image?
  var medium: Image?

  var best: String { medium?.url ?? self.default?.url ?? "" }
}

private struct SubscriptionListResponse: Decodable {
  struct Item: Decodable {
    struct Snippet: Decodable {
      struct ResourceId: Decodable { var channelId: String }
      var title: String
      var resourceId: ResourceId
      var thumbnails: Thumbnails
    }
    var snippet: Snippet
  }
  var items: [Item]
  var nextPageToken: String?
}

struct PlaylistItemsResponse: Decodable {
  struct Item: Decodable {
    struct Snippet: Decodable {
      var title: String
      var description: String
      var publishedAt: String
      var videoOwnerChannelId: String?
      var videoOwnerChannelTitle: String?
      var thumbnails: Thumbnails
    }
    struct ContentDetails: Decodable {
      var videoId: String
      var videoPublishedAt: String?
    }
    var snippet: Snippet?
    var contentDetails: ContentDetails
  }
  var items: [Item]
  var nextPageToken: String?
}

struct VideoListResponse: Decodable {
  struct Item: Decodable {
    struct Snippet: Decodable {
      var liveBroadcastContent: String
      var categoryId: String?
    }
    /// `duration` is missing for an upcoming or scheduled video.
    struct ContentDetails: Decodable { var duration: String? }
    struct LiveStreamingDetails: Decodable { var actualEndTime: String? }
    var id: String
    var snippet: Snippet
    var contentDetails: ContentDetails
    /// Present only if the video was ever a live stream or premiere.
    var liveStreamingDetails: LiveStreamingDetails?
  }
  var items: [Item]
}

private struct PlaylistListResponse: Decodable {
  struct Item: Decodable {
    struct Snippet: Decodable {
      var title: String
      var description: String
      var publishedAt: String
      var channelId: String?
      var channelTitle: String?
      var thumbnails: Thumbnails
    }
    struct ContentDetails: Decodable { var itemCount: Int }
    var id: String
    var snippet: Snippet
    var contentDetails: ContentDetails
  }
  var items: [Item]
}

private struct ChannelListResponse: Decodable {
  struct Item: Decodable {
    struct Snippet: Decodable {
      var title: String
      var thumbnails: Thumbnails
    }
    var id: String
    var snippet: Snippet

    var summary: ChannelSummary {
      ChannelSummary(
        channelId: id,
        title: decodeHTMLEntities(snippet.title),
        thumbnail: snippet.thumbnails.best
      )
    }
  }
  var items: [Item]?
}

/// A finished broadcast reports `liveBroadcastContent` "none" but carries an
/// `actualEndTime`; a plain upload has neither.
func classifyLiveStatus(_ item: VideoListResponse.Item) -> LiveStatus {
  switch item.snippet.liveBroadcastContent {
  case "live": .live
  case "upcoming": .upcoming
  default: item.liveStreamingDetails?.actualEndTime == nil ? .normal : .vod
  }
}

private struct ErrorResponse: Decodable {
  struct Failure: Decodable {
    struct Entry: Decodable { var reason: String? }
    var errors: [Entry]?
  }
  var error: Failure?
}

/// Whether an answer says YouTube's daily quota is used up: status 403 with a
/// JSON body whose `error.errors` holds a `reason` of `quotaExceeded` or
/// `dailyLimitExceeded`. The per-minute `rateLimitExceeded` is not it.
public func isDailyLimit(status: Int, body: Data) -> Bool {
  if status == 403, let answer = try? JSONDecoder().decode(ErrorResponse.self, from: body) {
    return (answer.error?.errors ?? []).contains {
      $0.reason == "quotaExceeded" || $0.reason == "dailyLimitExceeded"
    }
  } else {
    return false
  }
}

/// Raise the error a failed Google API response stands for; `youTube` for an
/// answer of the YouTube Data API, the only one with a daily limit read here.
func checkGoogleResponse(
  _ response: URLResponse, body: Data, playlistId: String? = nil, youTube: Bool = false
) throws {
  guard let http = response as? HTTPURLResponse else {
    throw GoogleAPIError.http(status: 0, body: "")
  }
  if http.statusCode == 401 {
    throw GoogleAPIError.tokenExpired
  }
  guard (200..<300).contains(http.statusCode) else {
    let text = String(decoding: body, as: UTF8.self)
    if http.statusCode == 403
      && (text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT")
        || text.contains("insufficientPermissions"))
    {
      throw GoogleAPIError.insufficientScope
    }
    if youTube && isDailyLimit(status: http.statusCode, body: body) {
      throw GoogleAPIError.dailyLimit
    }
    if http.statusCode == 404 && text.contains("playlistNotFound") {
      throw GoogleAPIError.playlistNotFound(playlistId ?? "")
    }
    apiLog.error("request failed: \(http.statusCode) \(text, privacy: .public)")
    throw GoogleAPIError.http(status: http.statusCode, body: text)
  }
}

/// The YouTube Data API, called with one access token.
public struct YouTubeClient: Sendable {
  private static let apiBase = URL(string: "https://www.googleapis.com/youtube/v3")!

  /// The token every call is made with.
  public let accessToken: String
  /// The session the calls go through.
  public let session: URLSession

  /// A client for one access token.
  public init(accessToken: String, session: URLSession = .shared) {
    self.accessToken = accessToken
    self.session = session
  }

  private func get<Response: Decodable>(_ path: String, _ parameters: [String: String]) async throws
    -> Response
  {
    var components = URLComponents(
      url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    components.queryItems = parameters.sorted { $0.key < $1.key }.map {
      URLQueryItem(name: $0.key, value: $0.value)
    }
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (body, response) = try await session.data(for: request)
    try checkGoogleResponse(
      response, body: body, playlistId: parameters["playlistId"], youTube: true)
    return try JSONDecoder().decode(Response.self, from: body)
  }

  /// Every channel the account subscribes to, alphabetically.
  public func subscriptions() async throws -> [Subscription] {
    var subscriptions: [Subscription] = []
    var pageToken: String?
    repeat {
      var parameters = ["part": "snippet", "mine": "true", "maxResults": "50", "order": "alphabetical"]
      parameters["pageToken"] = pageToken
      let page: SubscriptionListResponse = try await get("subscriptions", parameters)
      subscriptions += page.items.map { item in
        Subscription(
          channelId: item.snippet.resourceId.channelId,
          title: decodeHTMLEntities(item.snippet.title),
          thumbnail: item.snippet.thumbnails.best
        )
      }
      pageToken = page.nextPageToken
    } while pageToken != nil
    return subscriptions
  }

  /// Duration, broadcast kind and category per video id, 50 ids per call.
  public func videoDetails(_ videoIds: [String]) async throws -> [String: VideoDetails] {
    var details: [String: VideoDetails] = [:]
    for start in stride(from: 0, to: videoIds.count, by: 50) {
      let batch = videoIds[start..<min(start + 50, videoIds.count)]
      let page: VideoListResponse = try await get(
        "videos",
        ["part": videoDetailParts, "id": batch.joined(separator: ",")]
      )
      for item in page.items {
        details[item.id] = VideoDetails(
          durationSeconds: parseIsoDuration(item.contentDetails.duration ?? ""),
          liveStatus: classifyLiveStatus(item),
          categoryId: item.snippet.categoryId
        )
      }
    }
    return details
  }

  /// A channel's newest uploads, each with its duration and broadcast kind,
  /// and with `judgeShorts` whether it is a Short; without, the Shorts list
  /// is not fetched and a video that could be a Short is left unjudged.
  /// `probe` asks `/shorts/{id}` directly. A channel YouTube keeps no
  /// uploads list for has no uploads.
  public func uploads(
    channelId: String,
    channelTitle: String,
    maxResults: Int = uploadsPerChannel,
    probe: ShortsProbeFunction? = nil,
    judgeShorts: Bool = true
  ) async throws -> [Video] {
    let page: PlaylistItemsResponse
    do {
      page = try await get(
        "playlistItems",
        [
          "part": "snippet,contentDetails", "playlistId": uploadsPlaylistId(channelId),
          "maxResults": String(maxResults),
        ]
      )
    } catch GoogleAPIError.playlistNotFound {
      return []
    }
    let videos = page.items.compactMap { item -> Video? in
      if let snippet = item.snippet, !hiddenTitles.contains(snippet.title) {
        return Video(
          videoId: item.contentDetails.videoId,
          channelId: snippet.videoOwnerChannelId ?? channelId,
          channelTitle: decodeHTMLEntities(snippet.videoOwnerChannelTitle ?? channelTitle),
          title: decodeHTMLEntities(snippet.title),
          description: snippet.description,
          publishedAt: item.contentDetails.videoPublishedAt ?? snippet.publishedAt,
          thumbnail: snippet.thumbnails.best
        )
      } else {
        return nil
      }
    }
    let details = try await videoDetails(videos.map(\.videoId))
    let detailed = videos.map { video in
      var detailedVideo = video
      detailedVideo.durationSeconds = details[video.videoId]?.durationSeconds ?? 0
      detailedVideo.liveStatus = details[video.videoId]?.liveStatus ?? .normal
      detailedVideo.categoryId = details[video.videoId]?.categoryId
      return detailedVideo
    }
    if judgeShorts {
      return try await markShorts(detailed, channelId: channelId, maxResults: maxResults, probe: probe)
    } else {
      return withoutShortsList(detailed)
    }
  }

  /// Say which of a channel's already fetched uploads are Shorts, from its
  /// Shorts list; `maxResults` is the size of the uploads page they came from.
  public func markShorts(
    _ videos: [Video], channelId: String, maxResults: Int, probe: ShortsProbeFunction? = nil
  ) async throws -> [Video] {
    try await classifyShorts(
      videos,
      loadShortIds: { try await shortIds(channelId: channelId, max: maxResults) },
      probe: probe
    )
  }

  /// A channel's public playlists, newest created first (one page of 50).
  public func playlists(channelId: String, channelTitle: String, maxResults: Int = 50)
    async throws -> [Playlist]
  {
    let page: PlaylistListResponse = try await get(
      "playlists",
      ["part": "snippet,contentDetails", "channelId": channelId, "maxResults": String(maxResults)]
    )
    return page.items
      .map { item in
        Playlist(
          playlistId: item.id,
          channelId: item.snippet.channelId ?? channelId,
          channelTitle: decodeHTMLEntities(item.snippet.channelTitle ?? channelTitle),
          title: decodeHTMLEntities(item.snippet.title),
          description: item.snippet.description,
          publishedAt: item.snippet.publishedAt,
          thumbnail: item.snippet.thumbnails.best,
          itemCount: item.contentDetails.itemCount
        )
      }
      .sorted { $0.publishedAt > $1.publishedAt }
  }

  /// The ids of a channel's newest Shorts: none for a channel YouTube keeps
  /// no Shorts list for, and nil when the list couldn't be read, which is
  /// when a probe is worth asking. Every Short among the newest `max` uploads
  /// is among the newest `max` Shorts, so one page judges an uploads page
  /// that size.
  ///
  /// The list couldn't be read when YouTube answers it with a 5xx twice in a
  /// row, or the request itself fails.
  public func shortIds(channelId: String, max: Int = uploadsPerChannel) async throws
    -> Set<String>?
  {
    let playlistId = shortsPlaylistId(channelId)
    func read() async throws -> Set<String> {
      let page: PlaylistItemsResponse = try await get(
        "playlistItems",
        ["part": "contentDetails", "playlistId": playlistId, "maxResults": String(max)]
      )
      return Set(page.items.map(\.contentDetails.videoId))
    }
    do {
      do {
        return try await read()
      } catch GoogleAPIError.http(let status, _) where (500..<600).contains(status) {
        return try await read()
      }
    } catch GoogleAPIError.playlistNotFound {
      return []
    } catch GoogleAPIError.http(let status, _) where (500..<600).contains(status) {
      apiLog.error("Shorts list \(playlistId, privacy: .public) answered \(status); not read")
      return nil
    } catch let error as URLError where error.code != .cancelled {
      apiLog.error(
        "Shorts list \(playlistId, privacy: .public) failed: \(error.code.rawValue); not read")
      return nil
    }
  }

  /// The signed-in account's own channel; its id keys everything stored for
  /// the account.
  public func myChannel() async throws -> ChannelSummary {
    let page: ChannelListResponse = try await get("channels", ["part": "snippet", "mine": "true"])
    if let mine = page.items?.first {
      return mine.summary
    } else {
      throw GoogleAPIError.noChannel
    }
  }

  /// Look up channels by id, 50 per call (1 quota unit each).
  public func channelSummaries(_ channelIds: [String]) async throws -> [ChannelSummary] {
    var summaries: [ChannelSummary] = []
    for start in stride(from: 0, to: channelIds.count, by: 50) {
      let batch = channelIds[start..<min(start + 50, channelIds.count)]
      let page: ChannelListResponse = try await get(
        "channels",
        ["part": "snippet", "id": batch.joined(separator: ","), "maxResults": "50"])
      summaries += (page.items ?? []).map(\.summary)
    }
    return summaries
  }
}
