import SubtubeCore
import SwiftUI

/// Edits one channel's filter; the channel's page behind it is the preview.
struct FilterForm: View {
  let feed: FeedModel
  let channelId: String

  private var channel: ChannelFilter? { feed.channel(channelId) }

  var body: some View {
    if let channel {
      FilterFields(channel: channel, feed: feed)
    }
  }
}

extension FeedModel {
  /// One field of a channel's filter, saved as it's edited.
  func binding<Value>(_ channel: ChannelFilter, _ keyPath: WritableKeyPath<ChannelFilter, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { channel[keyPath: keyPath] },
      set: { value in
        var edited = channel
        edited[keyPath: keyPath] = value
        self.updateFilter(edited)
      })
  }
}

private struct FilterFields: View {
  let channel: ChannelFilter
  let feed: FeedModel

  private func binding<Value>(_ keyPath: WritableKeyPath<ChannelFilter, Value>) -> Binding<Value> {
    feed.binding(channel, keyPath)
  }

  private var minimumDuration: Binding<Int?> {
    Binding(
      get: { channel.minDurationSeconds > 0 ? channel.minDurationSeconds : nil },
      set: { value in
        var edited = channel
        edited.minDurationSeconds = max(0, value ?? 0)
        feed.updateFilter(edited)
      })
  }

  private var isVideos: Bool { channel.contentMode == .videos }

  var body: some View {
    #if DEBUG
      ScrollViewReader { proxy in
        form.task {
          // `-bottom` opens the form at its end, for screenshots
          if CommandLine.arguments.contains("-bottom") {
            try? await Task.sleep(for: .milliseconds(600))
            proxy.scrollTo(Self.endID, anchor: .bottom)
          }
        }
      }
    #else
      form
    #endif
  }

  private static let endID = "end"

  /// The fifteen topics as toggles for the filter's `topics`, the channel's
  /// most common first.
  private var topics: some View {
    Section {
      FlowLayout(spacing: 8) {
        ForEach(editorTopics(feed.channelFetched(channel.channelId)), id: \.self) { categoryId in
          Chip(
            label: topicLabel(categoryId) ?? "", selected: channel.topics.contains(categoryId)
          ) {
            var edited = channel
            if edited.topics.contains(categoryId) {
              edited.topics.removeAll { $0 == categoryId }
            } else {
              edited.topics.append(categoryId)
            }
            feed.updateFilter(edited)
          }
        }
      }
    } header: {
      Text(Strings.topics)
    } footer: {
      Text(Strings.topicsDetail)
    }
  }

  private var form: some View {
    Form {
      Section {
        Toggle(Strings.showInFeed, isOn: binding(\.enabled))
          .tint(Color.sunflower)
          .accessibilityLabel(Strings.showChannelInFeed(channel.title))
        SegmentedRow(
          label: Strings.show, selection: binding(\.contentMode),
          options: [(.videos, Strings.uploads), (.playlists, Strings.playlists)])
      }
      Section(Strings.patternHeading(channel.searchScope)) {
        TitlePatternFields(
          filter: Binding(get: { channel }, set: { feed.updateFilter($0) }))
      }
      .id(isVideos ? "pattern" : Self.endID)
      if isVideos {
        Section {
          ShortsPicker(selection: binding(\.shortsFilter))
          SegmentedRow(
            label: Strings.live, selection: binding(\.liveFilter),
            options: [LiveFilter.all, .normal, .vod].map { ($0, Strings.liveOption($0)) },
            showsHeading: true)
          LabeledContent(Strings.hideVideosUnder) {
            HStack {
              TextField(Strings.hideVideosUnder, value: minimumDuration, format: .number, prompt: Text("0"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 70)
                #if os(iOS)
                  .keyboardType(.numberPad)
                #endif
              Text(Strings.seconds).foregroundStyle(.secondary)
            }
          }
        }
        topics.id(Self.endID)
      }
    }
    .formStyle(.grouped)
  }
}

/// The phrases the filter looks for, whether it hides or keeps what has
/// one, where it looks, and case.
struct TitlePatternFields: View {
  @Binding var filter: ChannelFilter

  var body: some View {
    PhraseFields(
      phrases: patternToPhrases(filter.regex) ?? [],
      onChange: { filter.regex = phrasesToPattern($0) })
    SegmentedRow(
      label: Strings.matches, selection: $filter.mode,
      options: [(.exclude, Strings.choiceHide), (.include, Strings.show)],
      showsHeading: true)
    SegmentedRow(
      label: Strings.matchIn, selection: $filter.searchScope,
      options: FilterScope.allCases.map { ($0, Strings.scopeOption($0)) },
      showsHeading: true)
    SegmentedRow(
      label: Strings.caseHeading, selection: $filter.caseSensitive,
      options: [(false, Strings.caseIgnore), (true, Strings.caseMatch)],
      showsHeading: true)
  }
}

/// The filter's phrases as chips over the field that adds one: Return or a
/// comma turns what is typed into a chip, pressing a chip removes it, and
/// Delete in the empty field removes the last.
struct PhraseFields: View {
  let phrases: [String]
  /// Called with the whole new list when a phrase is added or removed.
  let onChange: ([String]) -> Void
  /// The phrase being typed, not yet a chip.
  @State private var draft = ""

  /// A comma ends a phrase: everything before the last one becomes chips,
  /// the rest stays in the field.
  private func typed(_ value: String) {
    let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    if parts.count > 1 {
      draft = parts[parts.count - 1]
      onChange(phrases + parts.dropLast())
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !phrases.isEmpty {
        FlowLayout {
          ForEach(phrases, id: \.self) { phrase in
            Chip(label: phrase, removes: true) {
              onChange(phrases.filter { $0 != phrase })
            }
          }
        }
      }
      PhraseInput(
        text: $draft, prompt: Strings.addPhrase,
        onSubmit: {
          onChange(phrases + [draft])
          draft = ""
        },
        onDeleteWhenEmpty: { onChange(phrases.dropLast()) }
      )
      .onChange(of: draft) { _, value in typed(value) }
      Text(Strings.phrasesDetail)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}

/// One choice as segments. On macOS a form row: the label, then the
/// segments at their natural width on the right, or under the label when
/// they don't fit beside it. On iOS the segments fill the row, under the
/// label when `showsHeading` is set.
struct SegmentedRow<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let options: [(value: Value, title: String)]
  /// Whether iOS shows the label above the segments.
  var showsHeading = false

  #if os(macOS)
    /// How far past each side of their frame segments at their natural
    /// width are drawn (macOS 26); without this room they run out over the
    /// row's edge.
    private static var bezelOutset: CGFloat { 7 }
  #endif

  var body: some View {
    #if os(macOS)
      ViewThatFits(in: .horizontal) {
        HStack {
          Text(label)
          Spacer(minLength: 12)
          segments.fixedSize().padding(.horizontal, Self.bezelOutset)
        }
        VStack(alignment: .leading, spacing: 6) {
          Text(label)
          segments
        }
      }
    #else
      if showsHeading {
        VStack(alignment: .leading, spacing: 6) {
          Text(label)
          segments
        }
      } else {
        segments
      }
    #endif
  }

  private var segments: some View {
    Picker(label, selection: $selection) {
      ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }
}

/// The Shorts choice as segments with its label.
struct ShortsPicker: View {
  @Binding var selection: ShortsFilter

  var body: some View {
    SegmentedRow(
      label: Strings.shorts, selection: $selection,
      options: ShortsFilter.allCases.map { ($0, Strings.shortsOption($0)) },
      showsHeading: true)
  }
}
