/// The Shorts setting most channels share; `.all` on a tie or with none.
public func commonShorts(_ channels: [ChannelFilter]) -> ShortsFilter {
  var counts: [ShortsFilter: Int] = [:]
  for channel in channels {
    counts[channel.shortsFilter, default: 0] += 1
  }
  guard let top = counts.values.max() else { return .all }
  let leaders = counts.filter { $0.value == top }
  if leaders.count == 1, let leader = leaders.first {
    return leader.key
  } else {
    return .all
  }
}

/// The channels as the first run's "Choose channels" screen would save them:
/// each with its switch as left, and all with the picked Shorts setting when
/// one was picked that differs from the common one.
public func setupDraft(
  _ channels: [ChannelFilter], enabled: [String: Bool], shorts: ShortsFilter?
) -> [ChannelFilter] {
  let picked = shorts.flatMap { $0 == commonShorts(channels) ? nil : $0 }
  return channels.map { channel in
    var draft = channel
    draft.enabled = enabled[channel.channelId] ?? channel.enabled
    draft.shortsFilter = picked ?? channel.shortsFilter
    return draft
  }
}

/// The filters "Choose channels" saves on Next: only the ones it changed.
public func setupChannelEdits(
  _ channels: [ChannelFilter], enabled: [String: Bool], shorts: ShortsFilter?
) -> [ChannelFilter] {
  zip(channels, setupDraft(channels, enabled: enabled, shorts: shorts))
    .filter { $0 != $1 }
    .map { $1 }
}

/// What the first run's filter screens save for the example channel when
/// they're left, or nil when nothing changed. An empty pattern keeps the
/// stored hide-or-show choice: the screens show "hide" before anything is
/// typed, which alone is not an edit.
public func setupFilterEdit(stored: ChannelFilter, draft: ChannelFilter) -> ChannelFilter? {
  var edited = draft
  if edited.regex.isEmpty {
    edited.mode = stored.mode
  }
  if edited == stored {
    return nil
  } else {
    return edited
  }
}
