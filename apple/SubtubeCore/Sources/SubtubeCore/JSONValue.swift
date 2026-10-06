import Foundation

/// Any JSON value, kept whole so fields this version doesn't know survive a
/// read and a write.
public enum JSONValue: Sendable, Hashable, Codable {
  /// `null`.
  case null
  /// `true` or `false`.
  case bool(Bool)
  /// A whole number; a decoded number lands here whenever it is whole and
  /// fits.
  case integer(Int64)
  /// Any other number.
  case double(Double)
  /// Text.
  case string(String)
  /// A list of values.
  case array([JSONValue])
  /// Values by name.
  case object(JSONObject)

  /// Decode whatever JSON value is there.
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

  /// Encode the value as the JSON it stands for.
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

  /// The object, when the value is one.
  public var objectValue: JSONObject? {
    if case .object(let value) = self { value } else { nil }
  }

  /// The text, when the value is text.
  public var stringValue: String? {
    if case .string(let value) = self { value } else { nil }
  }

  /// The truth value, when the value is one.
  public var boolValue: Bool? {
    if case .bool(let value) = self { value } else { nil }
  }

  /// The whole number, when the value is one.
  public var integerValue: Int64? {
    if case .integer(let value) = self { value } else { nil }
  }
}

/// A JSON object.
public typealias JSONObject = [String: JSONValue]
