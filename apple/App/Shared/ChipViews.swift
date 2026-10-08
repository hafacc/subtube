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
/// when pressed. It is as wide as its widest label and never drawn selected.
struct CycleChip<Value: Hashable>: View {
  /// What the chip sets, read out before the current choice.
  let setting: String
  let options: [(value: Value, label: String)]
  let value: Value
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
      onChange(next)
    } label: {
      ZStack {
        ForEach(options, id: \.value) { option in
          Text(option.label)
            .opacity(option.value == value ? 1 : 0)
            .accessibilityHidden(option.value != value)
        }
      }
    }
    .buttonStyle(ChipButtonStyle())
    .accessibilityLabel(Strings.chipSetting(setting, value: current))
  }
}

/// Whether auto-play is on, as a chip that switches it when pressed.
struct AutoplayChip: View {
  let feed: FeedModel

  var body: some View {
    CycleChip(
      setting: Strings.chipPlayback,
      options: [false, true].map { ($0, Strings.autoplayOption($0)) },
      value: feed.settings.autoplay, onChange: feed.setAutoplay)
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

/// A round chip, as tall as the others, holding only a +: opens the editor
/// for a new group.
struct NewGroupChip: View {
  let action: () -> Void

  private struct Style: ButtonStyle {
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
      .foregroundStyle(Color.primary)
      .overlay {
        Circle().strokeBorder(Color.secondary.opacity(0.35))
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
        Image(systemName: "plus")
          .imageScale(.small)
      }
    }
    .buttonStyle(Style())
    .accessibilityLabel(Strings.newGroup)
    .help(Strings.newGroup)
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
      .padding(.horizontal, inset)
      .padding(.vertical, 8)
    }
    .modifier(ScrollEdgeFade())
  }
}

/// The chips over the feed and over a channel's page: auto-play, the order,
/// how far back, watched or not, then, on the feed, the groups, then the
/// topics.
struct FeedChipRow: View {
  let feed: FeedModel
  /// The space left of the first chip and right of the last.
  var inset: CGFloat = 16
  /// Opens the editor for a new group.
  let onNewGroup: () -> Void

  private var showsGroups: Bool {
    feed.selectedChannel == nil && feed.fullLoadShown
  }

  var body: some View {
    ChipRow(
      groups: showsGroups ? feed.groups : [], selectedGroups: feed.settings.groupChips,
      onGroup: feed.toggleGroupChip, onNewGroup: showsGroups ? onNewGroup : nil,
      topics: feed.topicChips, selected: feed.settings.topicChips, inset: inset,
      onTopic: feed.toggleTopicChip
    ) {
      AutoplayChip(feed: feed)
      CycleChip(
        setting: Strings.chipSort,
        options: FeedSort.allCases.map { ($0, Strings.feedSortOption($0)) },
        value: feed.settings.feedSort, onChange: feed.setFeedSort)
      CycleChip(
        setting: Strings.chipTime,
        options: TimeChip.allCases.map { ($0, Strings.timeChipOption($0)) },
        value: feed.settings.timeChip, onChange: feed.setTimeChip)
      CycleChip(
        setting: Strings.chipShow,
        options: WatchedMode.allCases.map { ($0, Strings.watchedModeOption($0)) },
        value: feed.watchedMode, onChange: feed.setWatchedMode)
    }
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

  private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
    var rows: [[(index: Int, size: CGSize)]] = [[]]
    var used: CGFloat = 0
    for (index, subview) in subviews.enumerated() {
      let ideal = subview.sizeThatFits(.unspecified)
      let size = CGSize(width: min(ideal.width, width), height: ideal.height)
      if let last = rows.last, !last.isEmpty, used + spacing + size.width > width {
        rows.append([])
        used = 0
      }
      used += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
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
