/// Text with every Unicode scalar lowercased on its own, by Unicode's
/// locale-independent mapping, so every client folds alike.
public func foldCase(_ text: String) -> [Unicode.Scalar] {
  text.unicodeScalars.flatMap { $0.properties.lowercaseMapping.unicodeScalars }
}

/// Order two strings by Unicode scalar value, with no normalization.
public func precedesByScalar(_ left: String, _ right: String) -> Bool {
  left.unicodeScalars.lexicographicallyPrecedes(right.unicodeScalars)
}

/// Order two strings ignoring case: ``foldCase(_:)`` both, then by scalar value.
public func precedesIgnoringCase(_ left: String, _ right: String) -> Bool {
  foldCase(left).lexicographicallyPrecedes(foldCase(right))
}

/// Whether two strings hold the same scalars; `==` would also call
/// canonically equivalent spellings equal.
public func sameScalars(_ left: String, _ right: String) -> Bool {
  left.unicodeScalars.elementsEqual(right.unicodeScalars)
}
