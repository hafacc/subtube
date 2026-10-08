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
  private var topicChips: some View {
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
  }

  private var contentMode: some View {
    SegmentedRow(
      label: Strings.show, selection: binding(\.contentMode),
      options: [(.videos, Strings.uploads), (.playlists, Strings.playlists)])
  }

  private var liveFilter: some View {
    SegmentedRow(
      label: Strings.live, selection: binding(\.liveFilter),
      options: [LiveFilter.all, .normal, .vod].map { ($0, Strings.liveOption($0)) },
      showsHeading: true)
  }

  private var patternFields: some View {
    TitlePatternFields(filter: Binding(get: { channel }, set: { feed.updateFilter($0) }))
  }

  private var minimumDurationField: some View {
    TextField(Strings.hideVideosUnder, value: minimumDuration, format: .number, prompt: Text("0"))
      .labelsHidden()
      .multilineTextAlignment(.trailing)
  }

  #if os(macOS)
    @FocusState private var durationFocused: Bool

    /// "Show in Feed" in a card alone, then "Videos", the phrases and
    /// "Topics" as titled cards.
    private var form: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HStack {
            Text(Strings.showInFeed).fontWeight(.semibold)
            Spacer(minLength: 12)
            ChannelSwitch(title: channel.title, isOn: binding(\.enabled))
          }
          .frame(minHeight: 36)
          .panelCard()
          PanelSection(Strings.videos) {
            PanelRows {
              contentMode
              if isVideos {
                ShortsPicker(selection: binding(\.shortsFilter))
                liveFilter
                HStack(spacing: 6) {
                  Text(Strings.hideVideosUnder)
                  Spacer(minLength: 12)
                  minimumDurationField
                    .textFieldStyle(.plain)
                    .focused($durationFocused)
                    .frame(width: 36)
                    .fieldBox(focused: durationFocused)
                  Text(Strings.seconds).foregroundStyle(Color.secondary)
                }
              }
            }
          }
          PanelSection(Strings.patternHeading(channel.searchScope)) {
            patternFields
          }
          .id(isVideos ? "pattern" : Self.endID)
          if isVideos {
            PanelSection(Strings.topics) {
              topicChips.padding(.top, 8)
              Text(Strings.topicsDetail)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .padding(.vertical, 8)
            }
            .id(Self.endID)
          }
        }
        .padding(.horizontal, panelInset)
        .padding(.bottom, 16)
      }
    }
  #else
    private var form: some View {
      Form {
        Section {
          Toggle(Strings.showInFeed, isOn: binding(\.enabled))
            .tint(Color.sunflower)
            .accessibilityLabel(Strings.showChannelInFeed(channel.title))
          contentMode
        }
        Section(Strings.patternHeading(channel.searchScope)) {
          patternFields
        }
        .id(isVideos ? "pattern" : Self.endID)
        if isVideos {
          Section {
            ShortsPicker(selection: binding(\.shortsFilter))
            liveFilter
            LabeledContent(Strings.hideVideosUnder) {
              HStack {
                minimumDurationField
                  .frame(maxWidth: 70)
                  .keyboardType(.numberPad)
                Text(Strings.seconds).foregroundStyle(.secondary)
              }
            }
          }
          Section {
            topicChips
          } header: {
            Text(Strings.topics)
          } footer: {
            Text(Strings.topicsDetail)
          }
          .id(Self.endID)
        }
      }
      .formStyle(.grouped)
    }
  #endif
}

/// The phrases the filter looks for, whether it hides or keeps what has
/// one, where it looks, and case.
struct TitlePatternFields: View {
  @Binding var filter: ChannelFilter

  private var phrases: some View {
    PhraseFields(
      phrases: patternToPhrases(filter.regex) ?? [],
      onChange: { filter.regex = phrasesToPattern($0) })
  }

  @ViewBuilder private var choices: some View {
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

  var body: some View {
    #if os(macOS)
      phrases.padding(.top, 8).padding(.bottom, 4)
      PanelRows { choices }
    #else
      phrases
      choices
    #endif
  }
}

/// The filter's phrases as chips with the field that adds one: Return or a
/// comma turns what is typed into a chip, pressing a chip removes it, and
/// Delete in the empty field removes the last. On iOS the chips are over the
/// field; on macOS they are inside the field's box, before what is typed.
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

  private var input: some View {
    PhraseInput(
      text: $draft, prompt: Strings.addPhrase,
      onSubmit: {
        onChange(phrases + [draft])
        draft = ""
      },
      onDeleteWhenEmpty: { onChange(phrases.dropLast()) },
      onFocusChange: { inputFocused = $0 }
    )
    .onChange(of: draft) { _, value in typed(value) }
  }

  /// Whether the field has the keyboard; only macOS draws by it.
  @State private var inputFocused = false

  #if os(macOS)
    /// A phrase inside the field's box; pressing it removes it.
    private func token(_ phrase: String) -> some View {
      Button {
        onChange(phrases.filter { $0 != phrase })
      } label: {
        HStack(spacing: 5) {
          Text(phrase).lineLimit(1)
          Text(verbatim: "×").foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
          Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Strings.removePhrase(phrase))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        FlowLayout(spacing: 4, trailingFill: 90) {
          ForEach(phrases, id: \.self) { token($0) }
          input
            .padding(.leading, 4)
            .frame(height: 22)
        }
        .padding(.vertical, 3)
        .fieldBox(focused: inputFocused, inset: 3)
        Text(Strings.phrasesDetail)
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
      }
    }
  #else
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
        input
        Text(Strings.phrasesDetail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  #endif
}

/// One choice as segments. On macOS a row: the label, then
/// ``BrandSegments`` at their natural width on the right, or under the label
/// when they don't fit beside it. On iOS the system's segments fill the row,
/// under the label when `showsHeading` is set.
struct SegmentedRow<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let options: [(value: Value, title: String)]
  /// Whether iOS shows the label above the segments.
  var showsHeading = false

  var body: some View {
    #if os(macOS)
      let segments = BrandSegments(label: label, selection: $selection, options: options)
      ViewThatFits(in: .horizontal) {
        HStack {
          Text(label)
          Spacer(minLength: 12)
          segments.fixedSize()
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

  #if os(iOS)
    private var segments: some View {
      Picker(label, selection: $selection) {
        ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  #endif
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
