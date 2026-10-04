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
            proxy.scrollTo(Self.markAllID, anchor: .bottom)
          }
        }
      }
    #else
      form
    #endif
  }

  private static let markAllID = "markAll"

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
      }
      Section {
        switch feed.markAllChoice(channel.channelId) {
        case .watched(let ids):
          Button(Strings.markAllAsWatched) { feed.applyMarkAll(channel.channelId) }
            .disabled(ids.isEmpty)
        case .unwatched:
          Button(Strings.markAllAsUnwatched) { feed.applyMarkAll(channel.channelId) }
        }
      }
      .id(Self.markAllID)
    }
    .formStyle(.grouped)
  }
}

/// The title pattern, whether it hides or keeps matches, where it matches,
/// and case.
struct TitlePatternFields: View {
  @Binding var filter: ChannelFilter
  /// Told whether what is typed is a pattern that can be saved.
  var onValidity: (Bool) -> Void = { _ in }

  var body: some View {
    PatternField(
      label: Strings.patternHeading(filter.searchScope), pattern: $filter.regex,
      onValidity: onValidity)
    SegmentedRow(
      label: Strings.matches, selection: $filter.mode,
      options: [(.exclude, Strings.choiceHide), (.include, Strings.choiceShow)],
      showsHeading: true)
    SegmentedRow(
      label: Strings.matchIn, selection: $filter.searchScope,
      options: FilterScope.allCases.map { ($0, Strings.scopeOption($0)) },
      showsHeading: true)
    #if os(macOS)
      Toggle(Strings.matchCase, isOn: $filter.caseSensitive)
        .toggleStyle(.checkbox)
        .tint(Color.gold)
    #else
      Toggle(Strings.matchCase, isOn: $filter.caseSensitive)
        .tint(Color.sunflower)
    #endif
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

  var body: some View {
    #if os(macOS)
      ViewThatFits(in: .horizontal) {
        HStack {
          Text(label)
          Spacer(minLength: 12)
          segments.fixedSize()
        }
        VStack(alignment: .leading, spacing: 6) {
          Text(label)
          segments.fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
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

/// The first run's preview section: the channel's newest items under a
/// filter not saved yet, what it drops dimmed and tagged, the pattern's
/// match highlighted, and how many it keeps.
struct FilterPreview: View {
  let feed: FeedModel
  let channel: ChannelFilter

  var body: some View {
    let compiled = compileFilter(channel)
    let items = feed.previewItems(channel.channelId)
    let kept = items?.count { itemPassesFilter($0, compiled) } ?? 0
    Section(Strings.previewCount(kept, of: items?.count ?? 0)) {
      if let items {
        if items.isEmpty {
          Text(Strings.noRecentVideos).foregroundStyle(.secondary)
        } else {
          ForEach(items) { item in
            PreviewRow(
              title: highlighted(item.title, compiled),
              meta: meta(item),
              thumbnail: item.thumbnail,
              kept: itemPassesFilter(item, compiled))
          }
        }
      } else if feed.previewFailed.contains(channel.channelId) {
        Text(Strings.previewFailed).foregroundStyle(.secondary)
      } else {
        ForEach(0..<4, id: \.self) { _ in
          HStack(spacing: 10) {
            Thumbnail(url: "", cornerRadius: 4).frame(width: 56)
            VStack(alignment: .leading, spacing: 5) {
              SkeletonLine(width: 200)
              SkeletonLine(width: 60, height: 9)
            }
            Spacer(minLength: 0)
          }
          .skeleton()
        }
      }
    }
  }

  private func meta(_ item: FeedItem) -> String {
    switch item {
    case .video(let video):
      let duration = formatDuration(video.durationSeconds ?? 0)
      return video.isShort == true ? "\(duration) · \(Strings.shortBadge)" : duration
    case .playlist(let playlist):
      return Strings.videoCount(playlist.itemCount)
    }
  }

  private func highlighted(_ title: String, _ compiled: CompiledFilter) -> AttributedString {
    var text = AttributedString(title)
    if let range = titleMatchRange(title, compiled),
      let lower = AttributedString.Index(range.lowerBound, within: text),
      let upper = AttributedString.Index(range.upperBound, within: text)
    {
      text[lower..<upper].backgroundColor = .tintFill
      text[lower..<upper].foregroundColor = .tintText
    }
    return text
  }
}

/// One preview row: thumbnail, title, length; dimmed and tagged when dropped.
struct PreviewRow: View {
  let title: AttributedString
  let meta: String
  let thumbnail: String
  let kept: Bool

  var body: some View {
    HStack(spacing: 10) {
      Thumbnail(url: thumbnail, cornerRadius: 4).frame(width: 56)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).lineLimit(2)
        Text(meta).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if !kept {
        Text(Strings.hidden)
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.tintText)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.tintFill, in: Capsule())
      }
    }
    .opacity(kept ? 1 : 0.4)
  }
}

/// A pattern text field that saves only valid patterns and says why one
/// isn't.
struct PatternField: View {
  let label: String
  @Binding var pattern: String
  /// Told whether what is typed is a pattern that can be saved.
  var onValidity: (Bool) -> Void = { _ in }
  @State private var draft = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(label, text: $draft, prompt: Text(verbatim: ""))
        .labelsHidden()
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .font(.body.monospaced())
        .onAppear {
          draft = pattern
          onValidity(isValidPattern(pattern))
        }
        .onChange(of: pattern) { _, saved in
          if isValidPattern(draft) {
            draft = saved
          }
        }
        .onChange(of: draft) { _, typed in
          let valid = isValidPattern(typed)
          onValidity(valid)
          if valid && typed != pattern {
            pattern = typed
          }
        }
      if let error = patternError(draft) {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }
}
