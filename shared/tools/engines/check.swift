// Runs cross-engine cases through NSRegularExpression (ICU); see ../cross-engine.ts.
import Foundation

func decode(_ field: Substring) -> String {
  String(decoding: Data(base64Encoded: String(field))!, as: UTF8.self)
}

func search(_ regex: NSRegularExpression, _ text: String) -> String {
  regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil ? "1" : "0"
}

let input = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
var lines = input.split(separator: "\n", omittingEmptySubsequences: false)
if lines.last == "" { lines.removeLast() }
let meta = try! NSRegularExpression(pattern: decode(lines[0].split(separator: "\t")[1]))
var output = ""
for line in lines.dropFirst() {
  let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
  if fields[0] == "V" {
    output += search(meta, decode(fields[1])) + "\n"
  } else {
    do {
      let regex = try NSRegularExpression(
        pattern: decode(fields[1]), options: [])
      output += search(regex, decode(fields[2])) + "\n"
    } catch {
      output += "E\n"
    }
  }
}
FileHandle.standardOutput.write(output.data(using: .utf8)!)
