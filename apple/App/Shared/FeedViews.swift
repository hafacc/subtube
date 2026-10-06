import SubtubeCore
import SwiftUI

/// One feed entry: thumbnail with its badges and progress bar, title,
/// channel and date. While it plays, the player takes the thumbnail's place.
struct ItemCard: View {
  let item: FeedItem
  let watched: Bool
  /// How full its progress bar is, from 0 to 1; nil for no bar.
  let progress: Double?
  /// The session playing this card in place, if it is.
  var player: PlayerSession?
  let onOpen: () -> Void
  let onOpenChannel: () -> Void
  /// Phones draw bigger cards.
  var large = false

  private var isShort: Bool {
    if case .video(let video) = item {
      return video.isShort == true
    } else {
      return false
    }
  }

  private var corners: RoundedRectangle {
    RoundedRectangle(cornerRadius: large ? 14 : 8, style: .continuous)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 10 : 6) {
      if let player {
        YouTubePlayerView(session: player).clipShape(corners)
      } else {
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
            .overlay(alignment: .bottomLeading) {
              if let progress, progress > 0 {
                ProgressBar(fraction: progress)
              }
            }
            .clipShape(corners)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.play(item.title))
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(large ? .body.weight(.semibold) : .callout.weight(.medium))
          .lineLimit(2)
        HStack(spacing: 8) {
          Button(action: onOpenChannel) {
            Text(item.channelTitle).lineLimit(1).truncationMode(.tail)
          }
          .buttonStyle(.plain)
          Spacer(minLength: 0)
          if let date = item.publishedDate {
            Text(date.shortFeedDate).lineLimit(1).fixedSize()
          }
        }
        .font(large ? .footnote : .caption)
        .foregroundStyle(.secondary)
      }
    }
  }
}

/// The Sunflower bar along a thumbnail's bottom edge: how far it was played.
private struct ProgressBar: View {
  let fraction: Double

  var body: some View {
    Color.clear
      .frame(height: 4)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          Color.sunflower.frame(width: proxy.size.width * min(1, fraction))
        }
      }
      .accessibilityHidden(true)
  }
}

/// The thin Sunflower bar along the top of the feed while a full load runs.
///
/// It moves on with `progress`, and when that goes back to nil it runs to
/// the end and fades out. Under reduced motion it jumps instead of moving.
struct LoadProgressBar: View {
  /// How far the load is, from 0 to 1; nil when none runs.
  let progress: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = 0.0
  @State private var visible = false

  var body: some View {
    GeometryReader { proxy in
      Color.sunflower.frame(width: proxy.size.width * shown)
    }
    .frame(height: 3)
    .opacity(visible ? 1 : 0)
    .allowsHitTesting(false)
    .accessibilityElement()
    .accessibilityRepresentation { ProgressView(value: shown) }
    .accessibilityHidden(!visible)
    .onChange(of: progress, initial: true) { _, now in
      if let now {
        visible = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { shown = now }
      } else if visible {
        finish()
      }
    }
  }

  private func finish() {
    if reduceMotion {
      visible = false
      shown = 0
    } else {
      withAnimation(.easeOut(duration: 0.2)) { shown = 1 }
      withAnimation(.easeOut(duration: 0.3).delay(0.25)) {
        visible = false
      } completion: {
        // back to the start unseen, unless the next load already moved it
        if progress == nil {
          shown = 0
        }
      }
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

/// A card's shape while its feed loads: thumbnail, two title lines, then
/// the channel and the date on one line.
struct SkeletonCard: View {
  var large = false

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 10 : 6) {
      Thumbnail(url: "", cornerRadius: large ? 14 : 8)
      SkeletonLine(height: large ? 15 : 12)
      SkeletonLine(width: large ? 220 : 140, height: large ? 15 : 12)
      HStack {
        SkeletonLine(width: large ? 150 : 100, height: large ? 11 : 9)
        Spacer(minLength: 8)
        SkeletonLine(width: large ? 48 : 36, height: large ? 11 : 9)
      }
    }
  }
}

/// What the grid shows when it has nothing: skeleton cards while loading,
/// otherwise that there is nothing new, or nothing for what is selected.
struct FeedEmptyState: View {
  let feed: FeedModel

  var body: some View {
    if feed.shown.isEmpty {
      if feed.showsSkeletons {
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
        Text(feed.emptyText)
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

/// How many of a channel's unwatched items pass its filter; nothing for
/// none, or for a channel that is off.
struct UnwatchedCount: View {
  let channel: ChannelFilter
  let feed: FeedModel

  var body: some View {
    let count = channel.enabled ? feed.unwatchedByChannel[channel.channelId] ?? 0 : 0
    if count > 0 {
      Text("\(count)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .accessibilityLabel(Strings.unwatchedCount(count))
    }
  }
}

/// The "Search channels" field over a channel list.
struct ChannelSearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField(Strings.searchChannels, text: $text)
        .textFieldStyle(.plain)
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 32)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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
  let phrases = (patternToPhrases(channel.regex) ?? []).joined(separator: ", ")
  if !phrases.isEmpty {
    let scope = channel.searchScope
    parts.append(
      channel.mode == .exclude
        ? Strings.summaryHidesMatching(phrases, scope: scope)
        : Strings.summaryOnlyMatching(phrases, scope: scope))
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
