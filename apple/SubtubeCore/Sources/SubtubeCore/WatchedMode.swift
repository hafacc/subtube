/// Which of watched and unwatched items a page lists.
public enum WatchedMode: String, Sendable, CaseIterable {
  case unwatched
  case watched
  case all
}

/// The items a watched mode lists. An item in `staying`, one that changed
/// sides while it was on screen, is listed in every mode.
public func modeFiltered(
  _ items: [FeedItem], mode: WatchedMode, watched: Set<String>, staying: Set<String>
) -> [FeedItem] {
  items.filter { item in
    mode == .all || watched.contains(item.id) == (mode == .watched) || staying.contains(item.id)
  }
}

/// Whether auto-play moves on in a mode: not among watched items only.
public func autoplayAdvances(_ mode: WatchedMode) -> Bool {
  mode != .watched
}

/// Whether an empty list is empty because of what is selected, rather than
/// because nothing is left to watch: any mode but unwatched, a time chip, or
/// a topic chip.
public func emptiedBySelection(mode: WatchedMode, timeChip: TimeChip, topicChips: [String])
  -> Bool
{
  mode != .unwatched || timeChip != .anyTime || !knownTopics(topicChips).isEmpty
}
