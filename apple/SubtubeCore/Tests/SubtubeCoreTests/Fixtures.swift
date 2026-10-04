@testable import SubtubeCore

func makeChannel(_ configure: (inout ChannelFilter) -> Void = { _ in }) -> ChannelFilter {
  var channel = ChannelFilter(channelId: "UC1", title: "Chan", thumbnail: "")
  configure(&channel)
  return channel
}

func makeVideo(
  _ videoId: String = "v1",
  day: Int = 1,
  durationSeconds: Int? = 600,
  _ configure: (inout Video) -> Void = { _ in }
) -> Video {
  let paddedDay = day < 10 ? "0\(day)" : "\(day)"
  var video = Video(
    videoId: videoId, channelId: "UC1", channelTitle: "Chan", title: "Hello World",
    description: "", publishedAt: "2026-01-\(paddedDay)T00:00:00Z", thumbnail: "",
    durationSeconds: durationSeconds, liveStatus: .normal)
  configure(&video)
  return video
}

func makePlaylist(_ playlistId: String = "PL1", title: String = "Episode 1") -> Playlist {
  Playlist(
    playlistId: playlistId, channelId: "UC1", channelTitle: "Chan", title: title,
    description: "", publishedAt: "2026-01-01T00:00:00Z", thumbnail: "", itemCount: 5)
}
