/* Filter patterns as the phrases a user types (shared/fixtures/phrases.json):
 * the saved filter holds a pattern, built from phrases and read back into
 * them. */

// the pattern language's `\s` set (shared/patterns/README.md), not the engine's
private func isPatternWhitespace(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
    0x3000:
    true
  default: false
  }
}

private func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar {
  case "A"..."Z", "a"..."z", "0"..."9", "_": true
  default: false
  }
}

private let specialCharacters = Set(#"\^$.|?*+()[]{}"#.unicodeScalars)

/// One phrase's part of a pattern; empty for a phrase that is only whitespace.
private func phrasePattern(_ phrase: String) -> String {
  var trimmed = Array(phrase.unicodeScalars)
  while let first = trimmed.first, isPatternWhitespace(first) {
    trimmed.removeFirst()
  }
  while let last = trimmed.last, isPatternWhitespace(last) {
    trimmed.removeLast()
  }
  guard let first = trimmed.first, let last = trimmed.last else { return "" }
  var body = String.UnicodeScalarView()
  for (index, scalar) in trimmed.enumerated() {
    if isPatternWhitespace(scalar) {
      if !isPatternWhitespace(trimmed[index - 1]) {
        body.append(contentsOf: #"\s+"#.unicodeScalars)
      }
    } else {
      if specialCharacters.contains(scalar) {
        body.append("\\")
      }
      body.append(scalar)
    }
  }
  let boundary = #"\b"#
  return (isWordCharacter(first) ? boundary : "") + String(body)
    + (isWordCharacter(last) ? boundary : "")
}

/// The filter pattern that finds any of `phrases`, each as whole words.
///
/// Empty phrases and repeats are dropped; no phrases give the empty pattern.
public func phrasesToPattern(_ phrases: [String]) -> String {
  var parts: [String] = []
  for part in phrases.map(phrasePattern)
  where !part.isEmpty && !parts.contains(where: { sameScalars($0, part) }) {
    parts.append(part)
  }
  return parts.joined(separator: "|")
}

/// The phrase one alternative of a pattern may stand for; nil when it uses
/// anything a phrase can't produce.
private func readPhrase(_ alternative: [Unicode.Scalar]) -> String? {
  var phrase = String.UnicodeScalarView()
  var index = 0
  while index < alternative.count {
    let scalar = alternative[index]
    let next = index + 1 < alternative.count ? alternative[index + 1] : nil
    if scalar != "\\" {
      phrase.append(scalar)
      index += 1
    } else if next == "b" && (index == 0 || index == alternative.count - 2) {
      index += 2
    } else if next == "s" && index + 2 < alternative.count && alternative[index + 2] == "+" {
      phrase.append(" ")
      index += 3
    } else if let next, specialCharacters.contains(next) {
      phrase.append(next)
      index += 2
    } else {
      return nil
    }
  }
  return String(phrase)
}

/// The phrases a pattern was built from, or nil when ``phrasesToPattern(_:)``
/// could not have produced it.
public func patternToPhrases(_ pattern: String) -> [String]? {
  if pattern.isEmpty {
    return []
  }
  var alternatives: [[Unicode.Scalar]] = [[]]
  let scalars = Array(pattern.unicodeScalars)
  var index = 0
  while index < scalars.count {
    let scalar = scalars[index]
    if scalar == "|" {
      alternatives.append([])
    } else {
      alternatives[alternatives.count - 1].append(scalar)
      if scalar == "\\" && index + 1 < scalars.count {
        index += 1
        alternatives[alternatives.count - 1].append(scalars[index])
      }
    }
    index += 1
  }
  let phrases = alternatives.compactMap(readPhrase)
  if phrases.count == alternatives.count && sameScalars(phrasesToPattern(phrases), pattern) {
    return phrases
  } else {
    return nil
  }
}

/// A saved pattern as the app uses it: unchanged when it is phrases,
/// otherwise no pattern.
public func phrasePatternOnly(_ pattern: String) -> String {
  patternToPhrases(pattern) == nil ? "" : pattern
}
