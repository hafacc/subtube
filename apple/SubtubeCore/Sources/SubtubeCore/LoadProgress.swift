/// How far a full load's bar stands while the subscription list is read.
public let loadProgressStart = 0.05

/// How far along a full load is, from 0 to 1, for its progress bar.
///
/// `total` is how many channels the load fetches, nil until the subscription
/// list is read; `finished` is how many of them are fetched, failed or
/// skipped. The bar stands at ``loadProgressStart`` until `total` is known,
/// then covers the rest in equal steps, one per channel; a load with no
/// channel to fetch is done once the list is read.
public func loadFraction(finished: Int, total: Int?) -> Double {
  if let total {
    let share = total > 0 ? Double(min(max(finished, 0), total)) / Double(total) : 1
    return loadProgressStart + (1 - loadProgressStart) * share
  } else {
    return loadProgressStart
  }
}
