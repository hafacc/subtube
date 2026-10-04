/// Newest first, the order the feed reads in; equal times by id ascending.
/// Both compare as plain ASCII.
public func byNewest(_ left: FeedItem, _ right: FeedItem) -> Bool {
  if left.publishedAt != right.publishedAt {
    return right.publishedAt.utf8.lexicographicallyPrecedes(left.publishedAt.utf8)
  } else {
    return left.id.utf8.lexicographicallyPrecedes(right.id.utf8)
  }
}

/// The ids a feed or channel page shows, newest first: what passes, less the
/// watched when they're hidden, except the ones marked since the list was
/// last rebuilt for good.
public func feedOrder(
  _ passing: some Sequence<FeedItem>, watched: Set<String>, hideWatched: Bool,
  justWatched: Set<String>
) -> [String] {
  passing
    .filter { !hideWatched || !watched.contains($0.id) || justWatched.contains($0.id) }
    .sorted(by: byNewest)
    .map(\.id)
}
