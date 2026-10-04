import Foundation

/// Any JSON value, kept whole so fields this version doesn't know survive a
/// read and a write.
public enum JSONValue: Sendable, Hashable, Codable {
  case null
  case bool(Bool)
  /// A whole number; a decoded number lands here whenever it is whole and
  /// fits.
  case integer(Int64)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object(JSONObject)

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      if value.rounded() == value, let whole = Int64(exactly: value) {
        self = .integer(whole)
      } else {
        self = .double(value)
      }
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode(JSONObject.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// Parse raw JSON; nil when it isn't JSON at all.
  public static func parse(_ data: Data) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  /// Compact JSON with sorted keys.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return try encoder.encode(self)
  }

  public var objectValue: JSONObject? {
    if case .object(let value) = self { value } else { nil }
  }

  public var stringValue: String? {
    if case .string(let value) = self { value } else { nil }
  }

  public var boolValue: Bool? {
    if case .bool(let value) = self { value } else { nil }
  }

  public var integerValue: Int64? {
    if case .integer(let value) = self { value } else { nil }
  }
}

/// A JSON object.
public typealias JSONObject = [String: JSONValue]
