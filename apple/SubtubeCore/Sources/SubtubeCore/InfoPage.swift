import Foundation

/// A page the apps show and the website publishes, as `shared/pages/*.json`
/// holds it (`shared/schema/page.schema.json`): the privacy policy or the terms.
///
/// Its text is plain except for links written `[label](url)`; `spans(of:)`
/// splits a paragraph into plain runs and links.
public struct InfoPage: Codable, Sendable, Hashable {
  /// The page's heading.
  public var title: String
  /// One line on what the page covers.
  public var description: String
  /// The page's address on the website.
  public var web: URL
  /// The day it last changed, `YYYY-MM-DD`.
  public var updated: String
  /// The paragraphs before the sections.
  public var intro: [String]
  /// The headed lists that follow.
  public var sections: [Section]

  /// A heading over a bulleted list.
  public struct Section: Codable, Sendable, Hashable {
    /// The section's heading.
    public var heading: String
    /// The list's entries.
    public var items: [String]
  }

  /// A page from its JSON file.
  public static func decode(_ data: Data) throws -> InfoPage {
    try JSONDecoder().decode(InfoPage.self, from: data)
  }

  /// The `updated` day's year, month and day; nil when it isn't `YYYY-MM-DD`.
  public var updatedDay: DateComponents? {
    let parts = updated.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let (year, month, day) = (parts[0], parts[1], parts[2])
    return DateComponents(year: year, month: month, day: day)
  }
}

/// A run of a page's text: plain, or a link's label and address.
public struct InfoSpan: Sendable, Hashable {
  /// The words shown.
  public var text: String
  /// Where the words lead, for a link.
  public var link: URL?
}

/// A page paragraph split into plain runs and its `[label](url)` links
/// (https: or mailto: only; anything else stays plain text).
public func spans(of paragraph: String) -> [InfoSpan] {
  let linkPattern = /\[([^\[\]]+)\]\(((?:https|mailto):[^()\s]+)\)/
  var result: [InfoSpan] = []
  var rest = paragraph[...]
  while let match = rest.firstMatch(of: linkPattern) {
    if match.range.lowerBound > rest.startIndex {
      result.append(InfoSpan(text: String(rest[..<match.range.lowerBound])))
    }
    let (_, label, address) = match.output
    result.append(InfoSpan(text: String(label), link: URL(string: String(address))))
    rest = rest[match.range.upperBound...]
  }
  if !rest.isEmpty {
    result.append(InfoSpan(text: String(rest)))
  }
  return result
}
