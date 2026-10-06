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
