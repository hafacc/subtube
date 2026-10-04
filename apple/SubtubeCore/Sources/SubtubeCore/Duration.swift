/// Format a length in seconds as M:SS or H:MM:SS.
public func formatDuration(_ totalSeconds: Int) -> String {
  let hours = totalSeconds / 3600
  let minutes = (totalSeconds % 3600) / 60
  let seconds = totalSeconds % 60
  let paddedSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"
  if hours > 0 {
    let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
    return "\(hours):\(paddedMinutes):\(paddedSeconds)"
  } else {
    return "\(minutes):\(paddedSeconds)"
  }
}
