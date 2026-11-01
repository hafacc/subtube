import SubtubeCore
import SwiftUI

/// The pages bundled from `shared/pages`: the privacy policy and the terms.
enum InfoPageKind: String, Identifiable, CaseIterable {
  case privacy
  case terms

  var id: String { rawValue }

  /// The page as bundled; nil only if the build left the file out.
  var page: InfoPage? { Self.loaded[self] ?? nil }

  /// The page a link to its website address stands for, if any.
  init?(web url: URL) {
    switch url {
    case Links.privacyPolicy: self = .privacy
    case Links.terms: self = .terms
    default: return nil
    }
  }

  private static let loaded: [InfoPageKind: InfoPage?] = Dictionary(
    uniqueKeysWithValues: allCases.map { kind in
      let page = Bundle.main.url(forResource: kind.rawValue, withExtension: "json", subdirectory: "pages")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? InfoPage.decode($0) }
      return (kind, page)
    })
}

/// A privacy policy or terms page: the heading, a link to it on the web, the
/// day it last changed, its paragraphs and its headed lists.
struct InfoPageView: View {
  let kind: InfoPageKind

  var body: some View {
    ScrollView {
      if let page = kind.page {
        content(page)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
    }
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  private func content(_ page: InfoPage) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(page.title)
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)
        Link(destination: page.web) {
          Label(Strings.openOnWeb, systemImage: "arrow.up.right.square")
        }
        #if os(macOS)
          .buttonStyle(.plain)
          .foregroundStyle(Color.gold)
        #endif
        if let day = Self.longDate(page) {
          Text(Strings.lastUpdated(day))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      ForEach(Array(page.intro.enumerated()), id: \.offset) { _, paragraph in
        Text(Self.linked(paragraph))
      }
      ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
        VStack(alignment: .leading, spacing: 8) {
          Text(section.heading)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
          ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(verbatim: "•").accessibilityHidden(true)
              Text(Self.linked(item))
            }
          }
        }
      }
    }
    .textSelection(.enabled)
    .tint(Color.gold)
  }

  /// The `updated` day as the user's locale writes a long date.
  private static func longDate(_ page: InfoPage) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return page.updatedDay
      .flatMap { calendar.date(from: $0) }?
      .formatted(date: .long, time: .omitted)
  }

  private static func linked(_ paragraph: String) -> AttributedString {
    spans(of: paragraph).reduce(into: AttributedString()) { line, span in
      var run = AttributedString(span.text)
      run.link = span.link
      line += run
    }
  }
}

/// A page shown over what's there, with "Done" to close it.
struct InfoPageSheet: View {
  let kind: InfoPageKind
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    #if os(macOS)
      page.frame(minWidth: 480, idealWidth: 560, minHeight: 400, idealHeight: 640)
    #else
      NavigationStack { page }
    #endif
  }

  private var page: some View {
    InfoPageView(kind: kind)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(Strings.done) { dismiss() }
        }
      }
  }
}
