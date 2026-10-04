import Foundation

/* The filter pattern language every client shares (shared/patterns/README.md):
 * one meta regex accepts exactly the valid patterns, and a fixed rewrite turns
 * a valid pattern into the engine pattern that ICU, Java and JavaScript all
 * match the same way. A port of shared/tools/pattern.ts. */

private let digits = Array("0123456789")
private let lower = Array("abcdefghijklmnopqrstuvwxyz")
private let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

private func orderedRanges(_ run: [Character]) -> [String] {
  let last = run[run.count - 1]
  return run.map { first in "\(first)-[\(first)-\(last)]" }
}

/// The meta regex: matches exactly the valid patterns. The same string as
/// shared/patterns/meta-regex.txt.
public let patternMetaRegex: String = {
  let literal = #"[^\\\^\$\.\|\?\*\+\(\)\[\]\{\}]"#
  let escaped = #"\\[\\\^\$\.\|\?\*\+\(\)\[\]\{\}\/tnrdDwWsS]"#
  let anchor = #"\^|\$|\\[bB]"#
  let classItem = (orderedRanges(digits) + orderedRanges(lower) + orderedRanges(upper) + [
    #"[^\\\]\[\^\-&]"#,
    "&(?!&)",
    #"\\[\\\^\$\.\|\?\*\+\(\)\[\]\{\}\/\-tnrdws]"#,
  ]).joined(separator: "|")
  let characterClass = #"\[\^?(?!:)(?:"# + classItem + #")+\]"#
  let bounds = digits.map { digit in "\(digit),[\(digit)-9]" }.joined(separator: "|")
  let quantifier = #"(?:[\*\+\?]|\{[0-9]\}|\{[0-9],\}|\{(?:"# + bounds + #")\})\??"#
  let atom = "(?:\(literal)|\(escaped)|\\.|\(characterClass))"
  let piece = "(?:\(anchor)|\(atom)(?:\(quantifier))?)"
  let group = #"\((?:\?:)?(?:"# + piece + #"|\|)*\)"#
  return "^(?:\(piece)|\(group)(?:\(quantifier))?|\\|)*$"
}()

// The pattern is a fixed string known to compile.
private let metaRegex = try! NSRegularExpression(pattern: patternMetaRegex)

/// Whether a pattern is in the shared pattern language. The empty pattern is
/// valid (it means no pattern).
public func isValidPattern(_ pattern: String) -> Bool {
  metaRegex.firstMatch(in: pattern, range: NSRange(pattern.startIndex..., in: pattern)) != nil
}

private let word = "A-Za-z0-9_"
private let space =
  #"\u0009-\u000D \u0085   -     　"#
private let boundary = "(?:(?<=[\(word)])(?![\(word)])|(?<![\(word)])(?=[\(word)]))"
private let notBoundary = "(?:(?<=[\(word)])(?=[\(word)])|(?<![\(word)])(?![\(word)]))"
private let anyCharacter = #"[\s\S]"#

private let shorthandOutside: [Character: String] = [
  "d": "[0-9]", "D": "[^0-9]",
  "w": "[\(word)]", "W": "[^\(word)]",
  "s": "[\(space)]", "S": "[^\(space)]",
  "b": boundary, "B": notBoundary,
]

private let shorthandInside: [Character: String] = ["d": "0-9", "w": word, "s": space]

private func isASCIILetter(_ character: Character) -> Bool {
  character.isASCII && character.isLetter
}

private func swapCase(_ character: Character) -> String {
  character.isLowercase ? character.uppercased() : character.lowercased()
}

/// The engine pattern for a valid pattern, compiled with no options. Case
/// folding is spelled out for ASCII letters only.
public func enginePattern(_ pattern: String, caseSensitive: Bool) -> String {
  // code points, as the language is defined over them
  let chars = pattern.unicodeScalars.map(Character.init)
  func at(_ index: Int) -> Character? { chars.indices.contains(index) ? chars[index] : nil }
  var out = ""
  var index = 0
  while index < chars.count {
    let char = chars[index]
    if char == "\\", let next = at(index + 1) {
      out += shorthandOutside[next] ?? "\\\(next)"
      index += 2
    } else if char == "." {
      out += anyCharacter
      index += 1
    } else if char == "$" {
      out += "(?!\(anyCharacter))"
      index += 1
    } else if char == "(" {
      out += "(?:"
      index += at(index + 1) == "?" ? 3 : 1
    } else if char == "[" {
      index += 1
      var body = "["
      if at(index) == "^" {
        body += "^"
        index += 1
      }
      var extra = ""
      while let item = at(index), item != "]" {
        if item == "\\", let next = at(index + 1) {
          body += shorthandInside[next] ?? "\\\(next)"
          index += 2
        } else if at(index + 1) == "-", let last = at(index + 2) {
          body += "\(item)-\(last)"
          if !caseSensitive && isASCIILetter(item) {
            extra += "\(swapCase(item))-\(swapCase(last))"
          }
          index += 3
        } else {
          body.append(item)
          if !caseSensitive && isASCIILetter(item) {
            extra += swapCase(item)
          }
          index += 1
        }
      }
      out += "\(body)\(extra)]"
      index += 1
    } else if !caseSensitive && isASCIILetter(char) {
      out += "[\(char)\(swapCase(char))]"
      index += 1
    } else {
      out.append(char)
      index += 1
    }
  }
  return out.isEmpty ? "(?:)" : out
}

/// Compile a pattern for searching; nil when it isn't valid.
public func compilePattern(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
  guard isValidPattern(pattern) else { return nil }
  return try? NSRegularExpression(
    pattern: enginePattern(pattern, caseSensitive: caseSensitive))
}
