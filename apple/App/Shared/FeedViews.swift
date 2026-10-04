import SubtubeCore
import SwiftUI

/// One feed entry: thumbnail with its badges, title, channel and date.
struct ItemCard: View {
  let item: FeedItem
  let watched: Bool
  let onOpen: () -> Void
  let onOpenChannel: () -> Void
  let onToggleWatched: () -> Void
  /// Phones draw bigger cards and mark watched by swiping instead of a button.
  var large = false

  private var isShort: Bool {
    if case .video(let video) = item {
      return video.isShort == true
    } else {
      return false
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 10 : 6) {
      Button(action: onOpen) {
        Thumbnail(url: item.thumbnail, cornerRadius: large ? 14 : 8)
          .overlay(alignment: .topLeading) {
            if isShort {
              ThumbnailBadge { Text(Strings.shortBadge) }.padding(6)
            }
          }
          .overlay(alignment: .bottomLeading) {
            if watched {
              ThumbnailBadge { Text(Strings.watchedBadge) }.padding(6)
            }
          }
          .overlay(alignment: .bottomTrailing) {
            ItemBadge(item: item).padding(6)
          }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Strings.play(item.title))
      HStack(alignment: .top, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(large ? .body.weight(.semibold) : .callout.weight(.medium))
            .lineLimit(2)
          HStack(spacing: 4) {
            Button(item.channelTitle, action: onOpenChannel)
              .buttonStyle(.plain)
            if let date = item.publishedDate {
              Text("·")
              Text(date.shortFeedDate)
            }
          }
          .font(large ? .footnote : .caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
        Spacer(minLength: 0)
        if !large {
          Button(action: onToggleWatched) {
            Image(systemName: "eye")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .accessibilityLabel(watched ? Strings.markAsUnwatched : Strings.markAsWatched)
          .help(watched ? Strings.markAsUnwatched : Strings.markAsWatched)
        }
      }
    }
    .opacity(watched ? 0.4 : 1)
    .contextMenu {
      Button(watched ? Strings.markAsUnwatched : Strings.markAsWatched, action: onToggleWatched)
    }
  }
}

extension View {
  /// Grey out the previous feed, shimmering, and keep it from being used
  /// while a load runs.
  func loadingDimmed(_ loading: Bool) -> some View {
    opacity(loading ? 0.45 : 1)
      .shimmering(loading, overCards: true)
      .disabled(loading)
      .animation(.default, value: loading)
  }
}

/// The feed's error, reconnect prompt and notice.
struct FeedBanners: View {
  let feed: FeedModel
  let app: AppModel

  var body: some View {
    VStack(spacing: 8) {
      if let error = feed.error {
        HStack {
          Image(systemName: "exclamationmark.triangle")
          Text(error)
          Spacer()
          if feed.needsReconnect {
            SignInButton(model: app) { Text(Strings.signInShort) }
              .buttonStyle(.borderless)
              .foregroundStyle(Color.gold)
          }
        }
        .padding(10)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      }
      if let notice = feed.notice {
        HStack {
          Text(notice)
          Spacer()
          Button(Strings.dismiss) { feed.notice = nil }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.gold)
        }
        .padding(10)
        .foregroundStyle(Color.tintText)
        .background(Color.tintFill, in: RoundedRectangle(cornerRadius: 8))
      }
    }
    .font(.callout)
  }
}

/// A card's shape while its feed loads: thumbnail, two title lines, the
/// channel line.
struct SkeletonCard: View {
  var large = false

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 10 : 6) {
      Thumbnail(url: "", cornerRadius: large ? 14 : 8)
      SkeletonLine(height: large ? 15 : 12)
      SkeletonLine(width: large ? 220 : 140, height: large ? 15 : 12)
      SkeletonLine(width: large ? 150 : 100, height: large ? 11 : 9)
    }
  }
}

/// What the grid shows when it has nothing: skeleton cards while loading,
/// otherwise that there is nothing new.
struct FeedEmptyState: View {
  let feed: FeedModel

  var body: some View {
    if feed.shown.isEmpty {
      if feed.loading || feed.channelLoading {
        #if os(macOS)
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)],
            alignment: .leading, spacing: 18
          ) {
            ForEach(0..<16, id: \.self) { _ in SkeletonCard() }
          }
          .skeleton()
        #else
          ForEach(0..<4, id: \.self) { _ in
            SkeletonCard(large: true)
              .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
          }
          .skeleton()
        #endif
      } else if feed.error == nil {
        Text(Strings.noMatches)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          #if os(macOS)
            .padding(.top, 40)
          #endif
      }
    }
  }
}

/// A channel as the iOS lists show it: avatar, name, what its filter does.
struct ChannelRowLabel: View {
  let channel: ChannelFilter
  let feed: FeedModel

  var body: some View {
    HStack(spacing: 12) {
      Avatar(url: channel.thumbnail, title: channel.title, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(channel.title).font(.body.weight(.medium)).foregroundStyle(.primary)
        Text(filterSummary(channel, followedOnly: feed.isFollowedOnly(channel.channelId)))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
  }
}

/// The switch that shows a channel in the feed or leaves it out.
struct ChannelSwitch: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(Strings.showChannelInFeed(title), isOn: $isOn)
    .labelsHidden()
    .toggleStyle(.switch)
    .tint(Color.sunflower)
  }
}

/// A one-line description of a channel's filter, as the channels list shows it.
func filterSummary(_ channel: ChannelFilter, followedOnly: Bool) -> String {
  var parts: [String] = []
  if !channel.enabled {
    return Strings.summaryOff
  }
  if channel.contentMode == .playlists {
    parts.append(Strings.summaryPlaylists)
  }
  if !channel.regex.isEmpty {
    let scope = channel.searchScope
    parts.append(
      channel.mode == .exclude
        ? Strings.summaryHidesMatching(channel.regex, scope: scope)
        : Strings.summaryOnlyMatching(channel.regex, scope: scope))
  }
  if channel.contentMode != .playlists {
    switch channel.shortsFilter {
    case .all: break
    case .normal: parts.append(Strings.summaryNoShorts)
    case .shorts: parts.append(Strings.summaryShortsOnly)
    }
    switch channel.liveFilter {
    case .all: break
    case .normal: parts.append(Strings.summaryRegularOnly)
    case .vod: parts.append(Strings.summaryLiveOnly)
    }
    if channel.minDurationSeconds > 0 {
      parts.append(Strings.summaryHidesUnder(channel.minDurationSeconds))
    }
  }
  if parts.isEmpty {
    parts.append(Strings.summaryAllVideos)
  }
  if followedOnly {
    parts.insert(Strings.summaryFollowed, at: 0)
  }
  return parts.joined(separator: " · ")
}
