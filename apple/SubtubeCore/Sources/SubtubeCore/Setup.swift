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

/// The channels as the first run would save them: each with its switch as
/// left on "Choose channels", and all with the Shorts setting picked on
/// "Shorts" when one was picked that differs from the common one.
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

/// The filters a first-run screen saves on Next: only the ones it changed.
public func setupChannelEdits(
  _ channels: [ChannelFilter], enabled: [String: Bool], shorts: ShortsFilter?
) -> [ChannelFilter] {
  zip(channels, setupDraft(channels, enabled: enabled, shorts: shorts))
    .filter { $0 != $1 }
    .map { $1 }
}
