import SwiftUI

extension Color {
  /// The window's page background, which the details panel shares.
  static let page = Color(nsColor: .windowBackgroundColor)
  /// The fill behind a card or a sidebar row under the pointer.
  static let hoverFill = Color.primary.opacity(0.06)
}

/// The details panel's edge to what is in it.
let panelInset: CGFloat = 16

/// One choice as segments in the app's colors, whatever the system's accent.
///
/// The selected segment is Sunflower under ink text and slides to the next
/// choice, unless motion is reduced. With the system's keyboard navigation
/// on it takes the focus, shown by a dark-gold outline, and the left and
/// right arrows move the choice. To VoiceOver it is the system's segmented
/// picker. See ``SegmentedRow`` for the row with its label.
struct BrandSegments<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let options: [(value: Value, title: String)]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  @FocusState private var isFocused: Bool
  @Namespace private var namespace

  /// The segments' height.
  private static var height: CGFloat { 24 }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
  }

  /// Move the choice by `offset` segments in reading order.
  private func step(_ offset: Int) -> KeyPress.Result {
    let forward = layoutDirection == .rightToLeft ? -offset : offset
    if let index = options.firstIndex(where: { $0.value == selection }),
      options.indices.contains(index + forward)
    {
      selection = options[index + forward].value
    }
    return .handled
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.value) { option in
        let isSelected = option.value == selection
        Text(option.title)
          .lineLimit(1)
          .foregroundStyle(isSelected ? Color.ink : Color.primary)
          .padding(.horizontal, 11)
          .frame(height: Self.height)
          .background {
            if isSelected {
              shape.fill(Color.sunflower)
                .matchedGeometryEffect(id: "selected", in: namespace)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture { selection = option.value }
      }
    }
    .background(Color.primary.opacity(0.08), in: shape)
    .overlay {
      if isFocused {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(Color.gold, lineWidth: 2)
          .padding(-3)
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selection)
    .focusable(interactions: .activate)
    .focused($isFocused)
    .focusEffectDisabled()
    .onKeyPress(.leftArrow) { step(-1) }
    .onKeyPress(.rightArrow) { step(1) }
    .accessibilityRepresentation {
      Picker(label, selection: $selection) {
        ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
      }
      .pickerStyle(.segmented)
    }
  }
}

extension View {
  /// Draw a text field's box in the app's colors: the page behind it and a
  /// hairline outline, which is dark gold and thicker while `focused`.
  func fieldBox(focused: Bool, inset: CGFloat = 8) -> some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    return padding(.horizontal, inset)
      .frame(minHeight: 26)
      .background(Color.page, in: shape)
      .overlay {
        shape.strokeBorder(
          focused ? Color.gold : Color.secondary.opacity(0.35), lineWidth: focused ? 2 : 1)
      }
  }
}

extension View {
  /// Put the view in a card of the details panel: a quiet rounded fill.
  func panelCard() -> some View {
    padding(.horizontal, 12)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

/// A titled card of the details panel.
struct PanelSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .padding(.leading, 12)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 0) { content }
        .panelCard()
    }
  }
}

/// Rows of the details panel, each at least 36 pt high.
struct PanelRows<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group(subviews: content) { subviews in
        ForEach(subviews) { subview in
          subview
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
      }
    }
  }
}
