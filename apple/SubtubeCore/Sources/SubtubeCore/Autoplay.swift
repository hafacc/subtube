/// What auto-play plays after the item with id `endedId`: the first unwatched
/// item after it in the list shown. Nil at the end of the list, or when the
/// ended item isn't in it.
public func nextUnwatched(_ shown: [FeedItem], after endedId: String, watched: Set<String>)
  -> FeedItem?
{
  if let position = shown.firstIndex(where: { $0.id == endedId }) {
    return shown[(position + 1)...].first { !watched.contains($0.id) }
  } else {
    return nil
  }
}

/// Where the one player is drawn: over the dimmed app, in place of its
/// card's thumbnail, or in the window's bottom trailing corner.
public enum PlayerPlace: String, Sendable, CaseIterable {
  /// Over the dimmed app.
  case large
  /// In place of its card's thumbnail.
  case card
  /// In the window's bottom trailing corner.
  case minimized
}

/// The list an item was started from, as it was then.
public struct PlayQueue: Sendable, Hashable {
  /// The page's items, in the order shown.
  public var items: [FeedItem]
  /// The watched chip's choice.
  public var mode: WatchedMode

  /// A page's list and watched chip.
  public init(items: [FeedItem], mode: WatchedMode) {
    self.items = items
    self.mode = mode
  }
}

/// What auto-play plays after `endedId` (shared/fixtures/player.json): the
/// next unwatched item after it in the list the item was started from,
/// whatever page shows now. Nil with auto-play off, when that list was the
/// watched items only, at its end, or when the ended item isn't in it.
public func nextInQueue(
  _ queue: PlayQueue, after endedId: String, watched: Set<String>, autoplay: Bool
) -> FeedItem? {
  if autoplay && autoplayAdvances(queue.mode) {
    return nextUnwatched(queue.items, after: endedId, watched: watched)
  } else {
    return nil
  }
}

/// What the end of an item does to the player.
public enum EndOutcome: Sendable, Hashable {
  /// The next item plays, in this place.
  case next(PlayerPlace)
  /// The player stays on the ended item.
  case stay
  /// The player is removed.
  case close
}

/// What the end of an item does to a player in `place`. The next item plays
/// where the player is, except that a card not on the page showing can't
/// hold it. With nothing next, a card's player closes and the large and the
/// minimized one stay.
public func endOutcome(place: PlayerPlace, hasNext: Bool, nextCardShowing: Bool) -> EndOutcome {
  if hasNext {
    return .next(place == .card && !nextCardShowing ? .minimized : place)
  } else if place == .card {
    return .close
  } else {
    return .stay
  }
}

/// The smallest player YouTube allows, each way.
public let minimumPlayerSide = 200.0
/// The minimized player's width where the window has room for it.
public let minimizedPlayerWidth = 356.0
/// The gap between the minimized player and the window's edges.
public let minimizedPlayerMargin = 16.0

/// The minimized player's video, as width and height: 356 by 200, or as
/// wide as a narrower window leaves inside the margins, never under 200
/// either way.
public func minimizedPlayerSize(viewWidth: Double) -> (width: Double, height: Double) {
  let width = min(
    minimizedPlayerWidth, max(minimumPlayerSide, viewWidth - 2 * minimizedPlayerMargin))
  return (width, max(minimumPlayerSide, (width * 9 / 16).rounded()))
}

/// The large player's video, as width and height: the widest 16:9 box that
/// fits inside the view's margins with `barHeight` kept above it, never
/// smaller than YouTube allows.
public func largePlayerSize(viewWidth: Double, viewHeight: Double, barHeight: Double)
  -> (width: Double, height: Double)
{
  let margin = min(48, max(16, viewWidth * 0.04))
  let width = max(
    minimumPlayerSide * 16 / 9,
    min(viewWidth - 2 * margin, (viewHeight - 2 * margin - barHeight) * 16 / 9))
  return (width.rounded(), (width * 9 / 16).rounded())
}
