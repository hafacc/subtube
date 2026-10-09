import Foundation

/// Whether a channel's regex keeps or drops what it matches.
public enum FilterMode: String, Codable, Sendable, CaseIterable {
  /// Keep items that match.
  case include
  /// Keep items that do not match.
  case exclude
}

/// What a channel's regex matches against.
public enum FilterScope: String, Codable, Sendable, CaseIterable {
  /// The title only.
  case title
  /// The title and the description, each on its own.
  case both
  /// The description only.
  case description
}

/// Whether a channel contributes its uploads or its playlists to the feed.
public enum ContentMode: String, Codable, Sendable, CaseIterable {
  /// Its uploads.
  case videos
  /// Its playlists, each one feed entry.
  case playlists
}

/// A video's broadcast kind.
public enum LiveStatus: String, Codable, Sendable, CaseIterable {
  /// Scheduled, not started.
  case upcoming
  /// Live now.
  case live
  /// A finished live stream or premiere.
  case vod
  /// A plain upload that was never broadcast.
  case normal
}

/// Per-channel broadcast filter.
public enum LiveFilter: String, Codable, Sendable, CaseIterable {
  /// Everything but upcoming.
  case all
  /// Only live streams and their replays.
  case vod
  /// Only plain uploads.
  case normal
}

/// Per-channel Shorts filter.
public enum ShortsFilter: String, Codable, Sendable, CaseIterable {
  /// Everything.
  case all
  /// Hide Shorts.
  case normal
  /// Only Shorts.
  case shorts
}

/// A YouTube subscription.
public struct Subscription: Codable, Sendable, Hashable {
  /// The channel's `UC…` id.
  public var channelId: String
  /// The channel's name.
  public var title: String
  /// The channel's avatar URL, or empty.
  public var thumbnail: String

  /// A subscription to a channel.
  public init(channelId: String, title: String, thumbnail: String) {
    self.channelId = channelId
    self.title = title
    self.thumbnail = thumbnail
  }
}

/// A channel with its filter. The identity (id, title, thumbnail) belongs to
/// YouTube and is never stored; the filter fields are what a device file
/// keeps, and `stored` is the filter object as read, so fields this version
/// doesn't know (or values it doesn't recognize) are written back unchanged.
public struct ChannelFilter: Sendable, Hashable {
  /// The channel's `UC…` id.
  public var channelId: String
  /// The channel's name.
  public var title: String
  /// The channel's avatar URL, or empty.
  public var thumbnail: String
  /// Whether the main feed loads the channel.
  public var enabled = true
  /// The pattern built from the filter's phrases (``phrasesToPattern(_:)``);
  /// empty is no pattern. A stored pattern that isn't phrases reads as empty.
  public var regex = ""
  /// Whether the pattern keeps or drops what it finds.
  public var mode = FilterMode.include
  /// Whether ASCII letters match case-sensitively.
  public var caseSensitive = false
  /// What the pattern searches.
  public var searchScope = FilterScope.title
  /// Drop videos shorter than this many seconds; 0 keeps every length.
  public var minDurationSeconds = 0
  /// Which broadcast kinds to keep.
  public var liveFilter = LiveFilter.all
  /// Which of Shorts and other videos to keep.
  public var shortsFilter = ShortsFilter.all
  /// Uploads or playlists.
  public var contentMode = ContentMode.videos
  /// The category ids videos are kept in; empty keeps every category.
  public var topics: [String] = []
  /// The names of the groups the channel is in (``filterGroups(_:)``).
  public var groups: [String] = []
  /// The filter object as read from Drive.
  public var stored: JSONObject = [:]

  /// A channel with the default filter.
  public init(channelId: String, title: String, thumbnail: String) {
    self.channelId = channelId
    self.title = title
    self.thumbnail = thumbnail
  }

  /// A channel with a filter read from a device file. A missing field, or one
  /// holding a value this version doesn't recognize, reads as its default.
  public init(channelId: String, title: String, thumbnail: String, stored: JSONObject) {
    self.init(channelId: channelId, title: title, thumbnail: thumbnail)
    self.stored = stored
    let parsed = Self.parse(stored)
    enabled = parsed.enabled
    regex = parsed.regex
    mode = parsed.mode
    caseSensitive = parsed.caseSensitive
    searchScope = parsed.searchScope
    minDurationSeconds = parsed.minDurationSeconds
    liveFilter = parsed.liveFilter
    shortsFilter = parsed.shortsFilter
    contentMode = parsed.contentMode
    topics = parsed.topics
    groups = parsed.groups
  }

  private struct Fields: Equatable {
    var enabled = true
    var regex = ""
    var mode = FilterMode.include
    var caseSensitive = false
    var searchScope = FilterScope.title
    var minDurationSeconds = 0
    var liveFilter = LiveFilter.all
    var shortsFilter = ShortsFilter.all
    var contentMode = ContentMode.videos
    var topics: [String] = []
    var groups: [String] = []
  }

  private static func parse(_ object: JSONObject) -> Fields {
    func choice<Value: RawRepresentable>(_ key: String, _ fallback: Value) -> Value
    where Value.RawValue == String {
      object[key]?.stringValue.flatMap(Value.init(rawValue:)) ?? fallback
    }
    var fields = Fields()
    fields.enabled = object["enabled"]?.boolValue ?? true
    fields.regex = phrasePatternOnly(object["regex"]?.stringValue ?? "")
    fields.mode = choice("mode", FilterMode.include)
    fields.caseSensitive = object["caseSensitive"]?.boolValue ?? false
    fields.searchScope = choice("searchScope", FilterScope.title)
    fields.minDurationSeconds = object["minDurationSeconds"]?.integerValue
      .flatMap { Int(exactly: $0) }.map { max(0, $0) } ?? 0
    fields.liveFilter = choice("liveFilter", LiveFilter.all)
    fields.shortsFilter = choice("shortsFilter", ShortsFilter.all)
    fields.contentMode = choice("contentMode", ContentMode.videos)
    if case .array(let listed) = object["topics"] {
      let ids = listed.compactMap(\.stringValue)
      fields.topics = ids.count == listed.count ? knownTopics(ids) : []
    }
    fields.groups = filterGroups(object)
    return fields
  }

  /// The filter object to save: `stored` with every field the user changed
  /// written over it. Required fields are always present; an optional field
  /// set back to its default is left out. A stored pattern that isn't
  /// phrases is written as empty.
  public var storedFilter: JSONObject {
    var object = stored
    let read = Self.parse(stored)
    for identity in ["channelId", "title", "thumbnail"] {
      object[identity] = nil
    }
    func required(_ key: String, _ value: JSONValue, changed: Bool) {
      if changed || object[key] == nil {
        object[key] = value
      }
    }
    func optional(_ key: String, _ value: JSONValue, isDefault: Bool, changed: Bool) {
      if changed {
        object[key] = isDefault ? nil : value
      }
    }
    required("enabled", .bool(enabled), changed: enabled != read.enabled)
    object["regex"] = .string(phrasePatternOnly(regex))
    required("mode", .string(mode.rawValue), changed: mode != read.mode)
    optional(
      "caseSensitive", .bool(caseSensitive), isDefault: !caseSensitive,
      changed: caseSensitive != read.caseSensitive)
    optional(
      "searchScope", .string(searchScope.rawValue), isDefault: searchScope == .title,
      changed: searchScope != read.searchScope)
    optional(
      "minDurationSeconds", .integer(Int64(minDurationSeconds)), isDefault: minDurationSeconds == 0,
      changed: minDurationSeconds != read.minDurationSeconds)
    optional(
      "liveFilter", .string(liveFilter.rawValue), isDefault: liveFilter == .all,
      changed: liveFilter != read.liveFilter)
    optional(
      "shortsFilter", .string(shortsFilter.rawValue), isDefault: shortsFilter == .all,
      changed: shortsFilter != read.shortsFilter)
    optional(
      "contentMode", .string(contentMode.rawValue), isDefault: contentMode == .videos,
      changed: contentMode != read.contentMode)
    optional(
      "topics", .array(topics.map(JSONValue.string)), isDefault: topics.isEmpty,
      changed: topics != read.topics)
    // an emptied `groups` is written as [], and a malformed one stays until the groups change
    if !groups.elementsEqual(read.groups, by: sameScalars) {
      object["groups"] = .array(groups.map(JSONValue.string))
    }
    return object
  }
}

/// A single upload.
public struct Video: Codable, Sendable, Hashable {
  /// YouTube's id of the video.
  public var videoId: String
  /// The id of the channel that owns it.
  public var channelId: String
  /// That channel's name.
  public var channelTitle: String
  /// The video's title, HTML entities decoded.
  public var title: String
  /// The video's description, as sent.
  public var description: String
  /// ISO 8601, compared as a string for ordering, as the web app does.
  public var publishedAt: String
  /// Thumbnail URL, or empty.
  public var thumbnail: String
  /// Length in seconds; nil or 0 for live or upcoming.
  public var durationSeconds: Int?
  /// Broadcast kind; nil is treated as `normal`.
  public var liveStatus: LiveStatus?
  /// Whether this is a Short; nil means not yet classified.
  public var isShort: Bool?
  /// YouTube's category id, as written; nil when it has none.
  public var categoryId: String?

  /// A video as fetched.
  public init(
    videoId: String,
    channelId: String,
    channelTitle: String,
    title: String,
    description: String,
    publishedAt: String,
    thumbnail: String,
    durationSeconds: Int? = nil,
    liveStatus: LiveStatus? = nil,
    isShort: Bool? = nil,
    categoryId: String? = nil
  ) {
    self.videoId = videoId
    self.channelId = channelId
    self.channelTitle = channelTitle
    self.title = title
    self.description = description
    self.publishedAt = publishedAt
    self.thumbnail = thumbnail
    self.durationSeconds = durationSeconds
    self.liveStatus = liveStatus
    self.isShort = isShort
    self.categoryId = categoryId
  }
}

/// A channel's playlist, shown as one feed entry.
public struct Playlist: Codable, Sendable, Hashable {
  /// YouTube's id of the playlist.
  public var playlistId: String
  /// The id of the channel that owns it.
  public var channelId: String
  /// That channel's name.
  public var channelTitle: String
  /// The playlist's title, HTML entities decoded.
  public var title: String
  /// The playlist's description, as sent.
  public var description: String
  /// Creation time, ISO 8601; used for feed ordering.
  public var publishedAt: String
  /// Thumbnail URL, or empty.
  public var thumbnail: String
  /// How many videos it holds.
  public var itemCount: Int

  /// A playlist as fetched.
  public init(
    playlistId: String,
    channelId: String,
    channelTitle: String,
    title: String,
    description: String,
    publishedAt: String,
    thumbnail: String,
    itemCount: Int
  ) {
    self.playlistId = playlistId
    self.channelId = channelId
    self.channelTitle = channelTitle
    self.title = title
    self.description = description
    self.publishedAt = publishedAt
    self.thumbnail = thumbnail
    self.itemCount = itemCount
  }
}

/// A feed entry: a single video or a whole playlist, depending on the channel's
/// content mode.
public enum FeedItem: Sendable, Hashable, Identifiable {
  /// One upload.
  case video(Video)
  /// A whole playlist.
  case playlist(Playlist)

  /// The video id or playlist id: the key for watched state and de-duplication.
  public var id: String {
    switch self {
    case .video(let video): video.videoId
    case .playlist(let playlist): playlist.playlistId
    }
  }

  /// The id of the channel that owns the item.
  public var channelId: String {
    switch self {
    case .video(let video): video.channelId
    case .playlist(let playlist): playlist.channelId
    }
  }

  /// That channel's name.
  public var channelTitle: String {
    switch self {
    case .video(let video): video.channelTitle
    case .playlist(let playlist): playlist.channelTitle
    }
  }

  /// The item's title.
  public var title: String {
    switch self {
    case .video(let video): video.title
    case .playlist(let playlist): playlist.title
    }
  }

  /// The item's description.
  public var description: String {
    switch self {
    case .video(let video): video.description
    case .playlist(let playlist): playlist.description
    }
  }

  /// When it was published or created, ISO 8601.
  public var publishedAt: String {
    switch self {
    case .video(let video): video.publishedAt
    case .playlist(let playlist): playlist.publishedAt
    }
  }

  /// Thumbnail URL, or empty.
  public var thumbnail: String {
    switch self {
    case .video(let video): video.thumbnail
    case .playlist(let playlist): playlist.thumbnail
    }
  }

  /// The item's topic: its category id when that is one of the fifteen; a
  /// playlist has none.
  public var topic: String? {
    switch self {
    case .video(let video): video.categoryId.flatMap { topicLabel($0) == nil ? nil : $0 }
    case .playlist: nil
    }
  }

  /// A video's length in seconds; 0 for a playlist or a video without one.
  public var durationSeconds: Int {
    switch self {
    case .video(let video): video.durationSeconds ?? 0
    case .playlist: 0
    }
  }

  /// Whether this is a broadcast that is live now.
  public var isLive: Bool {
    switch self {
    case .video(let video): video.liveStatus == .live
    case .playlist: false
    }
  }

  /// `publishedAt` parsed, or nil when YouTube sent something unexpected.
  public var publishedDate: Date? {
    parseTimestamp(publishedAt).map { Date(timeIntervalSince1970: Double($0) / 1000) }
  }
}
