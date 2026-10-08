import SubtubeCore
import SwiftUI

/// The box every chip is drawn in, the same size selected or not: Sunflower
/// with ink text when selected, outlined otherwise.
struct ChipButtonStyle: ButtonStyle {
  var selected = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      #if os(macOS)
        .font(.body)
      #else
        .font(.subheadline)
      #endif
      .lineLimit(1)
      .foregroundStyle(selected ? Color.ink : Color.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .background(selected ? Color.sunflower : Color.clear, in: Capsule())
      .overlay {
        Capsule().strokeBorder(selected ? Color.sunflower : Color.secondary.opacity(0.35))
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Capsule())
  }
}

/// A chip: a toggle when `selected` is given, and with `removes` one that
/// goes away when pressed, shown by a × after its text.
struct Chip: View {
  let label: String
  var selected: Bool?
  var removes = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text(label)
        if removes {
          Text(verbatim: "×").foregroundStyle(.secondary)
        }
      }
    }
    .buttonStyle(ChipButtonStyle(selected: selected == true))
    .accessibilityLabel(removes ? Strings.removePhrase(label) : label)
    .accessibilityAddTraits(selected == true ? .isSelected : [])
  }
}

/// A chip that shows the current one of a few choices and moves to the next
/// when pressed. It is as wide as its widest label.
struct CycleChip<Value: Hashable>: View {
  /// What the chip sets, read out before the current choice.
  let setting: String
  let options: [(value: Value, label: String)]
  let value: Value
  /// Whether the chip is drawn selected.
  var selected = false
  /// Whether a press moves on; a chip that doesn't reports the choice it shows.
  var advances = true
  let onChange: (Value) -> Void

  private var current: String {
    options.first { $0.value == value }?.label ?? ""
  }

  private var next: Value {
    let index = options.firstIndex { $0.value == value } ?? -1
    return options[(index + 1) % options.count].value
  }

  var body: some View {
    Button {
      onChange(advances ? next : value)
    } label: {
      ZStack {
        ForEach(options, id: \.value) { option in
          Text(option.label)
            .opacity(option.value == value ? 1 : 0)
            .accessibilityHidden(option.value != value)
        }
      }
    }
    .buttonStyle(ChipButtonStyle(selected: selected))
    .accessibilityLabel(Strings.chipSetting(setting, value: current))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Fades a sideways-scrolling row out at each edge with more beyond it.
private struct ScrollEdgeFade: ViewModifier {
  private struct Hidden: Equatable {
    var leading = false
    var trailing = false
  }

  @State private var hidden = Hidden()
  private static let width: CGFloat = 40

  private func fade(_ faded: Bool, from start: UnitPoint, to end: UnitPoint) -> some View {
    LinearGradient(
      colors: [.black.opacity(faded ? 0 : 1), .black], startPoint: start, endPoint: end
    )
    .frame(width: Self.width)
  }

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: Hidden.self) { geometry in
        let before = geometry.contentOffset.x + geometry.contentInsets.leading
        let after =
          geometry.contentSize.width + geometry.contentInsets.trailing
          - geometry.contentOffset.x - geometry.containerSize.width
        return Hidden(leading: before > 1, trailing: after > 1)
      } action: { _, now in
        hidden = now
      }
      .mask {
        HStack(spacing: 0) {
          fade(hidden.leading, from: .leading, to: .trailing)
          Color.black
          fade(hidden.trailing, from: .trailing, to: .leading)
        }
      }
      .animation(.easeOut(duration: 0.15), value: hidden)
  }
}

/// Makes its one subview as wide as it is tall.
private struct SquareLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let height = subviews.first?.sizeThatFits(.unspecified).height ?? 0
    return CGSize(width: height, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews.first?.place(
      at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
      proposal: ProposedViewSize(bounds.size))
  }
}

/// A round chip, as tall as the others, holding only a symbol.
struct RoundChip: View {
  /// The SF Symbol drawn.
  let symbol: String
  /// The chip's tooltip and accessibility name.
  let label: String
  var selected = false
  let action: () -> Void

  private struct Style: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
      SquareLayout {
        configuration.label
          #if os(macOS)
            .font(.body)
          #else
            .font(.subheadline)
          #endif
          .padding(.vertical, 5)
      }
      .foregroundStyle(selected ? Color.ink : Color.primary)
      .background(selected ? Color.sunflower : Color.clear, in: Circle())
      .overlay {
        Circle().strokeBorder(selected ? Color.sunflower : Color.secondary.opacity(0.35))
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Circle())
    }
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        // gives the chip a text chip's height
        Text(verbatim: " ")
        Image(systemName: symbol)
          .imageScale(.small)
      }
    }
    .buttonStyle(Style(selected: selected))
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .help(label)
  }
}

/// The round + chip that opens the editor for a new group.
struct NewGroupChip: View {
  let action: () -> Void

  var body: some View {
    RoundChip(symbol: "plus", label: Strings.newGroup, action: action)
  }
}

/// Makes its one subview no wider than `limit`, at the height it then needs.
private struct WidthLimit: Layout {
  let limit: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let subview = subviews.first else { return .zero }
    let ideal = subview.sizeThatFits(.unspecified)
    if ideal.width <= limit {
      return ideal
    } else {
      return subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
    }
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
  }
}

/// What the feed's menu holds: auto-play, how far back and unwatched or watched,
/// then, under a divider, a chip for each order.
private struct FeedMenu: View {
  let feed: FeedModel
  /// The order each sort chip showed when another took over, by its place in the row.
  @Binding var lastShown: [Int: FeedSort]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct Drawn: Hashable {
    let settings: SyncedSettings
    let watchedMode: WatchedMode
  }

  private var activeChip: Int? {
    feedSortChips.firstIndex { $0.contains(feed.settings.feedSort) }
  }

  private func shownSort(_ index: Int) -> FeedSort {
    if index == activeChip {
      return feed.settings.feedSort
    } else {
      return lastShown[index] ?? feedSortChips[index][0]
    }
  }

  private func press(_ shown: FeedSort) {
    switch sortChipPress(shown: shown, current: feed.settings.feedSort) {
    case .choose(let sort):
      if let activeChip {
        lastShown[activeChip] = feed.settings.feedSort
      }
      feed.setFeedSort(sort)
    case .reshuffle:
      feed.reshuffle()
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      FlowLayout {
        Chip(label: Strings.autoplay, selected: feed.settings.autoplay) {
          feed.setAutoplay(!feed.settings.autoplay)
        }
        CycleChip(
          setting: Strings.chipTime,
          options: TimeChip.allCases.map { ($0, Strings.timeChipOption($0)) },
          value: feed.settings.timeChip, selected: feed.settings.timeChip != .anyTime,
          onChange: feed.setTimeChip)
        CycleChip(
          setting: Strings.chipShow,
          options: [(.unwatched, Strings.unwatched), (.watched, Strings.watched)],
          value: feed.watchedMode, selected: feed.watchedMode != .visitStart,
          onChange: feed.setWatchedMode)
      }
      Divider()
      FlowLayout {
        ForEach(feedSortChips.indices, id: \.self) { index in
          CycleChip(
            setting: Strings.chipSort,
            options: feedSortChips[index].map { ($0, Strings.feedSortOption($0)) },
            value: shownSort(index), selected: index == activeChip, advances: false,
            onChange: press)
        }
      }
    }
    .padding(12)
    .animation(
      reduceMotion ? nil : .easeOut(duration: 0.15),
      value: Drawn(settings: feed.settings, watchedMode: feed.watchedMode))
  }
}

/// The round chip that opens the feed's menu in a popover under it; drawn
/// selected while the time or the watched chip narrows the page.
struct FeedMenuButton: View {
  let feed: FeedModel
  /// The widest the popover's content may be.
  let widthLimit: CGFloat
  @State private var isOpen = false
  @State private var lastShown: [Int: FeedSort] = [:]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var narrows: Bool {
    feed.settings.timeChip != .anyTime || feed.watchedMode != .visitStart
  }

  // AppKit names the button's edge the popover hangs from, UIKit the popover's edge the arrow is on
  #if os(macOS)
    private static let arrowEdge = Edge.bottom
  #else
    private static let arrowEdge = Edge.top
  #endif

  var body: some View {
    RoundChip(
      symbol: "slider.horizontal.3", label: Strings.sortAndFilter, selected: narrows
    ) {
      isOpen.toggle()
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: narrows)
    .popover(isPresented: $isOpen, arrowEdge: Self.arrowEdge) {
      WidthLimit(limit: widthLimit) {
        FeedMenu(feed: feed, lastShown: $lastShown)
      }
      .presentationCompactAdaptation(.popover)
    }
    #if DEBUG
      .task {
        if CommandLine.arguments.contains("-filterMenu") {
          // a popover asked for before its window is on screen never opens, and one
          // open on a Mac closes when the app stops being the active one
          try? await Task.sleep(for: .seconds(5))
          isOpen = true
        }
      }
    #endif
  }
}

extension String {
  /// A group name's identity in a list: two spellings `==` calls equal are two groups.
  fileprivate var nameIdentity: [UInt32] {
    codePoints(self)
  }
}

/// A row of chips: `leading`, a divider, the "New group" chip and a toggle
/// for each group, a divider, then a toggle for each topic. It scrolls
/// sideways, fading out at an edge that hides chips.
struct ChipRow<Leading: View>: View {
  /// The group chips' names, in order.
  var groups: [String] = []
  /// The selected groups' names.
  var selectedGroups: [String] = []
  var onGroup: (String) -> Void = { _ in }
  /// Opens the editor for a new group; the row has that chip only with this.
  var onNewGroup: (() -> Void)?
  /// The topic chips' category ids, in order.
  let topics: [String]
  /// The selected topics' category ids.
  let selected: [String]
  /// The space left of the first chip and right of the last.
  var inset: CGFloat = 16
  /// The space left of the first chip, where it isn't `inset`.
  var leadingInset: CGFloat?
  let onTopic: (String) -> Void
  @ViewBuilder let leading: Leading

  private var hasGroupChips: Bool {
    onNewGroup != nil || !groups.isEmpty
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.secondary.opacity(0.35))
      .frame(width: 1, height: 20)
      .accessibilityHidden(true)
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        leading
        if hasGroupChips {
          divider
          if let onNewGroup {
            NewGroupChip(action: onNewGroup)
          }
          ForEach(groups, id: \.nameIdentity) { group in
            Chip(label: group, selected: selectedGroups.contains { sameScalars($0, group) }) {
              onGroup(group)
            }
          }
        }
        if !topics.isEmpty {
          divider
        }
        ForEach(topics, id: \.self) { categoryId in
          Chip(label: topicLabel(categoryId) ?? "", selected: selected.contains(categoryId)) {
            onTopic(categoryId)
          }
        }
      }
      .padding(.leading, leadingInset ?? inset)
      .padding(.trailing, inset)
      .padding(.vertical, 8)
    }
    .modifier(ScrollEdgeFade())
  }
}

/// The row over the feed and over a channel's page: the menu's button, which
/// stays put, then, scrolling, the groups (on the feed) and the topics.
struct FeedChipRow: View {
  let feed: FeedModel
  /// The space left of the menu's button and right of the last chip.
  var inset: CGFloat = 16
  /// Opens the editor for a new group.
  let onNewGroup: () -> Void
  @State private var width: CGFloat = 0

  private var showsGroups: Bool {
    feed.selectedChannel == nil && feed.fullLoadShown
  }

  var body: some View {
    HStack(spacing: 0) {
      FeedMenuButton(feed: feed, widthLimit: width > 0 ? max(0, width - 2 * inset) : .infinity)
        .padding(.leading, inset)
        .padding(.vertical, 8)
      ChipRow(
        groups: showsGroups ? feed.groups : [], selectedGroups: feed.settings.groupChips,
        onGroup: feed.toggleGroupChip, onNewGroup: showsGroups ? onNewGroup : nil,
        topics: feed.topicChips, selected: feed.settings.topicChips, inset: inset,
        leadingInset: 8, onTopic: feed.toggleTopicChip
      ) {
      }
    }
    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
  }
}

/// The chips over a channel list: its order, how far back, the groups, then
/// the topics.
struct ChannelChipRow: View {
  let feed: FeedModel
  /// The space left of the first chip and right of the last.
  var inset: CGFloat = 16
  /// Opens the editor for a new group.
  let onNewGroup: () -> Void

  var body: some View {
    ChipRow(
      groups: feed.fullLoadShown ? feed.groups : [],
      selectedGroups: feed.settings.channelGroupChips, onGroup: feed.toggleChannelGroupChip,
      onNewGroup: feed.fullLoadShown ? onNewGroup : nil,
      topics: feed.channelTopicChips, selected: feed.settings.channelTopicChips, inset: inset,
      onTopic: feed.toggleChannelTopicChip
    ) {
      CycleChip(
        setting: Strings.chipSort,
        options: ChannelSort.allCases.map { ($0, Strings.channelSortOption($0)) },
        value: feed.settings.channelSort, onChange: feed.setChannelSort)
      CycleChip(
        setting: Strings.chipTime,
        options: TimeChip.allCases.map { ($0, Strings.timeChipOption($0)) },
        value: feed.settings.channelTimeChip, onChange: feed.setChannelTimeChip)
    }
  }
}

/// What a channel list says when its chips leave no channel.
struct NoChannelsForFilter: View {
  var body: some View {
    Text(Strings.noChannelsForFilter)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
  }
}

/// Lays its subviews out in rows, starting a new row when one is full.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6
  /// The least width of the last subview, which then takes the rest of its
  /// row; nil lays it out like the others.
  var trailingFill: CGFloat?

  private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
    var rows: [[(index: Int, size: CGSize)]] = [[]]
    var used: CGFloat = 0
    for (index, subview) in subviews.enumerated() {
      let fill = index == subviews.count - 1 ? trailingFill : nil
      let ideal = subview.sizeThatFits(.unspecified)
      var size = CGSize(width: min(fill ?? ideal.width, width), height: ideal.height)
      if let last = rows.last, !last.isEmpty, used + spacing + size.width > width {
        rows.append([])
        used = 0
      }
      let gap = rows[rows.count - 1].isEmpty ? 0 : spacing
      if fill != nil && width.isFinite {
        size.width = width - used - gap
      }
      used += gap + size.width
      rows[rows.count - 1].append((index, size))
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let laidOut = rows(subviews, width: width).filter { !$0.isEmpty }
    let heights = laidOut.map { row in row.map(\.size.height).max() ?? 0 }
    let widths = laidOut.map { row in
      row.map(\.size.width).reduce(0, +) + spacing * CGFloat(row.count - 1)
    }
    return CGSize(
      width: proposal.width ?? (widths.max() ?? 0),
      height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var top = bounds.minY
    for row in rows(subviews, width: bounds.width) where !row.isEmpty {
      var leading = bounds.minX
      for (index, size) in row {
        subviews[index].place(
          at: CGPoint(x: leading, y: top), proposal: ProposedViewSize(size))
        leading += size.width + spacing
      }
      top += (row.map(\.size.height).max() ?? 0) + spacing
    }
  }
}
