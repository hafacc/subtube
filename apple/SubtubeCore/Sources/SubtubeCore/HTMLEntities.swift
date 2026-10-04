private let namedEntities: [String: String] = [
  "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
  "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "lsquo": "\u{2018}",
  "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}",
  "reg": "\u{00AE}", "trade": "\u{2122}",
]

/// Decode the HTML entities the Data API leaves in titles (`Tom &amp; Jerry`,
/// `don&#39;t`), so they display as typed and per-channel regexes match the
/// text the user sees. Unknown entities are left as written.
public func decodeHTMLEntities(_ text: String) -> String {
  guard text.contains("&") else { return text }
  var decoded = ""
  var rest = Substring(text)
  while let ampersand = rest.firstIndex(of: "&") {
    decoded += rest[..<ampersand]
    let afterAmpersand = rest.index(after: ampersand)
    guard let semicolon = rest[afterAmpersand...].prefix(12).firstIndex(of: ";") else {
      decoded += "&"
      rest = rest[afterAmpersand...]
      continue
    }
    let name = rest[afterAmpersand..<semicolon]
    if let replacement = entityValue(name) {
      decoded += replacement
      rest = rest[rest.index(after: semicolon)...]
    } else {
      decoded += "&"
      rest = rest[afterAmpersand...]
    }
  }
  decoded += rest
  return decoded
}

private func entityValue(_ name: Substring) -> String? {
  if name.hasPrefix("#") {
    let digits = name.dropFirst()
    let codePoint: UInt32?
    if digits.hasPrefix("x") || digits.hasPrefix("X") {
      codePoint = UInt32(digits.dropFirst(), radix: 16)
    } else {
      codePoint = UInt32(digits, radix: 10)
    }
    return codePoint.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
  } else {
    return namedEntities[String(name)]
  }
}
