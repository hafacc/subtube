import SubtubeCore
import SwiftUI

/// One feed entry: thumbnail with its badges and progress bar, title,
/// channel and date. While it plays, the player takes the thumbnail's place.
///
/// On a Mac the channel's avatar stands left of the title, with the channel
/// and the date on one line under it; a watched card is dimmed, and under
/// the pointer the card lies on a rounded plate with a Sunflower play button
/// on its thumbnail.
///
/// The progress bar is also the control that marks the item watched or
/// unwatched: on a Mac a strip along the thumbnail's bottom edge that shows
/// a track and a thicker bar under the pointer, on a phone a 44 pt target
/// centred on the bar, which shows no track; there `watchedSwipe()` adds
/// the same toggle to the card's list row. A press there never plays the
/// item, and the card of the item the player has, in any place, has no such
/// control: the player's own saves would undo the mark.
struct ItemCard: View {
  let item: FeedItem
  /// Plays and marks the item, says how far it was watched, and has the
  /// player.
  let feed: FeedModel
  let onOpenChannel: () -> Void
  /// Phones draw bigger cards.
  var large = false
  #if os(macOS)
    /// Whether the channel's avatar is drawn; a channel's own page leaves it off.
    var showsAvatar = true
    /// Draws the card as under the pointer, for pictures.
    var asHovered = false
    /// Whether the pointer is over the card.
    @State private var cardHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #endif
  /// Whether the pointer is over the progress bar's strip.
  @State private var barHovered = false

  #if os(macOS) && DEBUG
    private static let barAsHovered = CommandLine.arguments.contains("-barHover")
  #else
    private static let barAsHovered = false
  #endif

  // read here, not handed in by the list, so a mark or a saved position redraws cards and not the list
  private var watched: Bool {
    feed.watched.contains(item.id)
  }

  /// How full the progress bar is, from 0 to 1; nil for no bar.
  private var progress: Double? {
    feed.bars[item.id]
  }

  /// The session playing this item, in any place.
  private var session: PlayerSession? {
    feed.player.flatMap { $0.item.id == item.id ? $0 : nil }
  }

  /// Whether the bar is drawn as under the pointer: taller, over its track.
  private var barRaised: Bool {
    barHovered || Self.barAsHovered
  }

  /// Whether the bar's grey track shows: under the pointer, so never on a
  /// phone, and never on the card of the item the player has, which has no
  /// control.
  private var showsTrack: Bool {
    session == nil && barRaised
  }

  /// The control over the progress bar; it draws nothing itself.
  private var watchedControl: some View {
    Button {
      feed.toggleWatched(item.id)
    } label: {
      Color.clear.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(watched ? Strings.markUnwatched : Strings.markWatched)
    .help(watched ? Strings.markUnwatched : Strings.markWatched)
    #if os(macOS)
      .frame(height: 18)
      .onHover { barHovered = $0 }
      .pointerStyle(.link)
    #else
      // half over the thumbnail's bottom edge, half over the text below
      .frame(height: 44)
      .alignmentGuide(.bottom) { $0[VerticalAlignment.center] + ProgressBar.height / 2 }
    #endif
  }

  private var isShort: Bool {
    if case .video(let video) = item {
      return video.isShort == true
    } else {
      return false
    }
  }

  #if os(macOS)
    private var cornerRadius: CGFloat { 12 }
    private var spacing: CGFloat { 10 }
  #else
    private var cornerRadius: CGFloat { large ? 14 : 8 }
    private var spacing: CGFloat { large ? 10 : 6 }
  #endif

  private var corners: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  #if os(macOS)
    /// How far the plate under the pointer reaches past the card.
    private static let plateOutset: CGFloat = 8

    private var isHovered: Bool {
      cardHovered || asHovered
    }

    /// Whether the card is drawn as watched; never the card of the item the
    /// player has.
    private var isDimmed: Bool {
      watched && session == nil
    }

    /// The Sunflower disk with an ink triangle, on the thumbnail under the pointer.
    private var playMark: some View {
      Image(systemName: "play.fill")
        .font(.system(size: 17))
        .foregroundStyle(Color.ink)
        .offset(x: 1)
        .frame(width: 44, height: 44)
        .background(Color.sunflower, in: Circle())
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The avatar, then the title over the channel and the date.
    private var caption: some View {
      HStack(alignment: .top, spacing: 10) {
        if showsAvatar {
          Button(action: onOpenChannel) {
            Avatar(
              url: feed.channel(item.channelId)?.thumbnail ?? "", title: item.channelTitle,
              size: 28)
          }
          .buttonStyle(.plain)
          .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.body.weight(isDimmed ? .medium : .semibold))
            .foregroundStyle(isDimmed ? .secondary : .primary)
            .lineLimit(2)
          HStack(spacing: 5) {
            Button(action: onOpenChannel) {
              Text(item.channelTitle).lineLimit(1).truncationMode(.tail)
            }
            .buttonStyle(.plain)
            if let date = feed.publishedDate(item) {
              Text(verbatim: "·").accessibilityHidden(true)
              Text(date.shortFeedDate).lineLimit(1).fixedSize()
            }
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      }
    }
  #else
    private var caption: some View {
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
          if let date = feed.publishedDate(item) {
            Text(date.shortFeedDate).lineLimit(1).fixedSize()
          }
        }
        .font(large ? .footnote : .caption)
        .foregroundStyle(.secondary)
      }
    }
  #endif

  var body: some View {
    #if os(macOS)
      card
        .background {
          RoundedRectangle(
            cornerRadius: cornerRadius + Self.plateOutset, style: .continuous
          )
          .fill(Color.hoverFill)
          .padding(-Self.plateOutset)
          .opacity(isHovered ? 1 : 0)
        }
        .onHover { cardHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
    #else
      card
    #endif
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: spacing) {
      if let session, session.place == .card {
        // never smaller than YouTube allows, so taller than the thumbnail on a narrow phone
        Color.clear
          .aspectRatio(16 / 9, contentMode: .fit)
          .frame(minHeight: minimumPlayerSide)
          .overlay {
            YouTubePlayerView(session: session, feed: feed, cornerRadius: cornerRadius)
          }
          .onScrollVisibilityChange(threshold: 0.5) { visible in
            session.cardShows = visible
            // just started or in YouTube's full screen: the session minimizes afterwards, if still out of view
            if !visible && !session.isFullScreen && !session.isSettling {
              feed.minimizeCard()
            }
          }
      } else {
        Button {
          feed.open(item)
        } label: {
          Thumbnail(url: item.thumbnail, cornerRadius: cornerRadius)
            .overlay(alignment: .topLeading) {
              if isShort {
                ThumbnailBadge { Text(Strings.shortBadge) }.padding(6)
              }
            }
            .overlay(alignment: .bottomLeading) {
              if watched {
                ThumbnailBadge { Text(Strings.watched) }.padding(6)
              }
            }
            .overlay(alignment: .bottomTrailing) {
              ItemBadge(item: item).padding(6)
            }
            .overlay(alignment: .bottomLeading) {
              ProgressBar(fraction: progress ?? 0, showsTrack: showsTrack, thick: barRaised)
            }
            .clipShape(corners)
            #if os(macOS)
              .opacity(isDimmed ? 0.5 : 1)
              .overlay { playMark }
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.play(item.title))
        .accessibilityValue(watched ? Strings.watched : "")
        .overlay(alignment: .bottom) {
          if session == nil {
            watchedControl
          }
        }
      }
      caption
    }
  }
}

/// The Sunflower bar along a thumbnail's bottom edge: how far it was played.
/// With `showsTrack` a grey track lies under it across the full width, and
/// `thick` draws both taller. A change of the fill animates, unless motion
/// is reduced.
private struct ProgressBar: View {
  let fraction: Double
  var showsTrack = false
  var thick = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The bar's height at rest.
  static let height: CGFloat = 4
  /// How strong the grey track is.
  private static let trackOpacity = 0.6

  var body: some View {
    let shown = max(0, min(1, fraction))
    Color.gray.opacity(showsTrack ? Self.trackOpacity : 0)
      .frame(height: thick ? 7 : Self.height)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          Color.sunflower.frame(width: proxy.size.width * shown)
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shown)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: thick)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showsTrack)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

#if os(iOS)
  extension View {
    /// Swiping a card's list row to either side marks the item watched or
    /// unwatched, as a press on its progress bar does.
    ///
    /// The row slides back and stays in the list. VoiceOver gets the same
    /// toggle as an action of the row. Nothing is offered when `offered` is
    /// false.
    func watchedSwipe(watched: Bool, offered: Bool, toggle: @escaping () -> Void) -> some View {
      let button = WatchedSwipeButton(watched: watched, offered: offered, toggle: toggle)
      return swipeActions(edge: .leading, allowsFullSwipe: true) { button }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) { button }
    }
  }

  /// The button a swiped card uncovers: an icon over "Mark watched" or
  /// "Mark unwatched".
  private struct WatchedSwipeButton: View {
    let watched: Bool
    let offered: Bool
    let toggle: () -> Void

    var body: some View {
      if offered {
        Button(action: toggle) {
          Label(
            watched ? Strings.markUnwatched : Strings.markWatched,
            systemImage: watched ? "eye.slash" : "eye")
        }
        .tint(Color.gray)
      }
    }
  }
#endif

/// The thin Sunflower bar along the top of the feed while a full load runs.
///
/// It moves on with the feed's `loadProgress`, and when that goes back to
/// nil it runs to the end and fades out. Under reduced motion it jumps
/// instead of moving.
struct LoadProgressBar: View {
  let feed: FeedModel
  /// Whether the bar stays away while a card holds the player.
  var hiddenOverPlayingCard = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = 0.0
  @State private var visible = false

  /// How far the load is, from 0 to 1; nil when none runs or the bar stays away.
  private var progress: Double? {
    hiddenOverPlayingCard && feed.player?.place == .card ? nil : feed.loadProgress
  }

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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { shown = now }
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
      withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
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
    opacity(loading ? 0.4 : 1)
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
            SignInButton(app: app) { Text(Strings.signInShort) }
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
/// the channel and the date on one line; on a Mac the avatar's disk left of
/// the lines, as on a card.
struct SkeletonCard: View {
  var large = false
  #if os(macOS)
    /// Whether the avatar's disk is drawn; a channel's own page leaves it off.
    var showsAvatar = true

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        Thumbnail(url: "", cornerRadius: 12)
        HStack(alignment: .top, spacing: 10) {
          if showsAvatar {
            Circle().fill(Color.secondary.opacity(0.15)).frame(width: 28, height: 28)
          }
          VStack(alignment: .leading, spacing: 6) {
            SkeletonLine(height: 12)
            SkeletonLine(width: 160, height: 12)
            SkeletonLine(width: 120, height: 9)
          }
        }
      }
    }
  #else
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
  #endif
}

#if os(macOS)
  /// The Mac grid's columns: cards at least 300 pt wide.
  let feedGridColumns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]
#endif

/// What the grid shows when it has nothing: skeleton cards while loading,
/// otherwise that there is nothing new, or nothing for what is selected.
/// The Mac draws only the skeletons here; its page shows `MacEmptyState`.
struct FeedEmptyState: View {
  let feed: FeedModel

  var body: some View {
    if feed.shown.isEmpty {
      if feed.showsSkeletons {
        #if os(macOS)
          LazyVGrid(columns: feedGridColumns, alignment: .leading, spacing: 18) {
            ForEach(0..<24, id: \.self) { _ in
              SkeletonCard(showsAvatar: feed.selectedChannel == nil)
            }
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
        #if os(iOS)
          Text(feed.emptyText)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        #endif
      }
    }
  }
}

/// A channel as the iOS lists show it: avatar, name, what its filter does;
/// dimmed for a channel that is off.
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
    .opacity(channel.enabled ? 1 : offChannelOpacity)
  }
}

/// How many of a channel's unwatched items pass its filter; nothing for
/// none, or for a channel that is off.
struct UnwatchedCount: View {
  let channel: ChannelFilter
  let feed: FeedModel

  var body: some View {
    UnwatchedBadge(
      count: channel.enabled ? feed.unwatchedByChannel[channel.channelId] ?? 0 : 0)
  }
}

/// A count of unwatched items beside a row; nothing for none.
struct UnwatchedBadge: View {
  let count: Int

  var body: some View {
    if count > 0 {
      Text("\(count)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .accessibilityLabel(Strings.unwatchedCount(count))
    }
  }
}

/// How strongly the picture and text of a channel that is off show in a
/// list; the row's switch is never dimmed.
let offChannelOpacity = 0.45

/// The channels whose name has the text typed in a "Search channels"
/// field, ignoring case and nothing else; all of them when it is blank.
func channelsMatching(_ channels: [ChannelFilter], search: String) -> [ChannelFilter] {
  let query = foldCase(search.trimmingCharacters(in: .whitespaces))
  if query.isEmpty {
    return channels
  } else {
    return channels.filter { !foldCase($0.title).ranges(of: query).isEmpty }
  }
}

/// Channels by name, as every list sorted by name has them: ignoring case,
/// then by id.
func channelsByName(_ channels: [ChannelFilter]) -> [ChannelFilter] {
  let order = channelOrder(
    channels.map { ChannelOrderEntry(id: $0.channelId, title: $0.title, enabled: true, newest: nil) },
    sort: .name)
  let byId = Dictionary(channels.map { ($0.channelId, $0) }) { first, _ in first }
  return order.compactMap { byId[$0] }
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
  if channel.enabled {
    let parts = filterSummaryParts(channel).map(Strings.summary)
    return ((followedOnly ? [Strings.summaryFollowed] : []) + parts)
      .joined(separator: " · ")
  } else {
    return Strings.summaryOff
  }
}
