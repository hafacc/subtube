import SwiftUI

extension Color {
  /// The brand yellow; fills only, always under ink.
  static let sunflower = Color("Sunflower")
  /// Text and marks on a Sunflower fill.
  static let ink = Color("Ink")
  /// Links, text buttons, outlines and icons: dark gold on light, Sunflower on dark.
  static let gold = Color("Gold")
  /// Pale Sunflower background for selected or highlighted bits.
  static let tintFill = Color("TintFill")
  /// Text on `tintFill`.
  static let tintText = Color("TintText")
  /// Switch tracks and step dots that are off.
  static let inactive = Color("Inactive")
}

/// The colour scheme the user picked in Settings.
enum Theme: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: Self { self }

  /// The scheme to force, or nil to follow the system.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// A Sunflower button with ink text, for the one main action on a screen.
struct ProminentButtonStyle: ButtonStyle {
  /// Stretch to the available width, as phone screens' bottom buttons do.
  var fullWidth = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(fullWidth ? .headline : .body.weight(.medium))
      .foregroundStyle(Color.ink)
      .padding(.horizontal, fullWidth ? 22 : 14)
      .frame(maxWidth: fullWidth ? .infinity : nil)
      .frame(minHeight: fullWidth ? 50 : 28)
      .background(
        Color.sunflower.opacity(configuration.isPressed ? 0.8 : 1),
        in: RoundedRectangle(cornerRadius: fullWidth ? 25 : 6, style: .continuous)
      )
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(Rectangle())
  }
}

extension ButtonStyle where Self == ProminentButtonStyle {
  /// The Sunflower main-action button.
  static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
  /// The Sunflower main-action button, full width.
  static var prominentWide: ProminentButtonStyle { ProminentButtonStyle(fullWidth: true) }
}

/// A channel's avatar, or its initial while that loads or when it has none.
struct Avatar: View {
  let url: String
  let title: String
  var size: CGFloat = 18

  private var initial: String {
    // "Channel One" reads as O, as the mockups draw it
    let words = title.split(separator: " ")
    let word = words.count > 1 && words[0] == "Channel" ? words[1] : words.first
    return word.map { String($0.prefix(1)).uppercased() } ?? "?"
  }

  var body: some View {
    AsyncImage(url: URL(string: url)) { image in
      image.resizable().aspectRatio(contentMode: .fill)
    } placeholder: {
      Text(initial)
        .font(.system(size: size * 0.55, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.15))
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }
}

/// A 16:9 thumbnail with the neutral placeholder behind it.
struct Thumbnail: View {
  let url: String
  var cornerRadius: CGFloat = 8

  var body: some View {
    Color.secondary.opacity(0.15)
      .aspectRatio(16 / 9, contentMode: .fit)
      .overlay {
        if !url.isEmpty {
          AsyncImage(url: URL(string: url)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
          } placeholder: {
            Color.clear
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

/// A band sweeping across a view, to say it is loading: lighter and cut to
/// the shapes of stand-ins, or over real cards a darker band on light and a
/// lighter one on dark, across the whole view. Still when the system asks
/// for reduced motion.
private struct Shimmer: ViewModifier {
  let active: Bool
  let overCards: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  /// Seconds per sweep.
  private static let period = 1.4
  /// The band's width as a share of the view's.
  private static let band = 0.4

  private var bandColor: Color {
    if !overCards {
      .white.opacity(0.4)
    } else if colorScheme == .dark {
      .white.opacity(0.22)
    } else {
      .black.opacity(0.16)
    }
  }

  func body(content: Content) -> some View {
    if active && !reduceMotion {
      content.overlay {
        // the phase comes from the clock, so every shimmering view sweeps together
        TimelineView(.animation) { context in
          GeometryReader { proxy in
            let phase =
              context.date.timeIntervalSinceReferenceDate
              .truncatingRemainder(dividingBy: Self.period) / Self.period
            let width = proxy.size.width
            LinearGradient(
              colors: [.clear, bandColor, .clear], startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: width * Self.band)
            .offset(x: width * (phase * (1 + Self.band) - Self.band))
          }
        }
        .mask {
          if overCards {
            Rectangle()
          } else {
            content
          }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    } else {
      content
    }
  }
}

extension View {
  /// Sweep a shimmer across the view while `active`; `overCards` when the
  /// view is real content greyed out rather than stand-ins.
  func shimmering(_ active: Bool = true, overCards: Bool = false) -> some View {
    modifier(Shimmer(active: active, overCards: overCards))
  }

  /// Stand in for content that is loading: hidden from accessibility but
  /// for one progress indicator, and shimmering.
  func skeleton() -> some View {
    shimmering()
      .accessibilityElement(children: .ignore)
      .accessibilityRepresentation { ProgressView() }
  }
}

/// A grey bar standing in for a line of text.
struct SkeletonLine: View {
  var width: CGFloat?
  var height: CGFloat = 12

  var body: some View {
    RoundedRectangle(cornerRadius: height / 2.5)
      .fill(Color.secondary.opacity(0.15))
      .frame(maxWidth: width ?? .infinity)
      .frame(height: height)
  }
}

/// White text on a dark chip, laid over a thumbnail.
struct ThumbnailBadge<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 3) { content }
      .font(.caption2.weight(.medium))
      .foregroundStyle(.white)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
  }
}

/// The logo.
struct LogoMark: View {
  var size: CGFloat

  var body: some View {
    Image("Logo")
      .resizable()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

/// Progress through the first-run steps: dark-gold dots, the current one a bar.
struct StepDots: View {
  let index: Int
  let count: Int

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<count, id: \.self) { position in
        Capsule()
          .fill(position <= index ? Color.gold : Color.inactive)
          .frame(width: position == index ? 20 : 6, height: 6)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(Strings.step(index + 1, of: count))
  }
}

/// The Google "G" as a letter in a white circle, beside "Sign In with Google".
struct GoogleMark: View {
  var body: some View {
    Text("G")
      .font(.system(size: 11, weight: .heavy))
      .foregroundStyle(Color(red: 0x8A / 255, green: 0x61 / 255, blue: 0))
      .frame(width: 18, height: 18)
      .background(.white, in: Circle())
      .accessibilityHidden(true)
  }
}

extension Date {
  /// "Sep 24", with the year only when it isn't this year.
  var shortFeedDate: String {
    if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) {
      formatted(.dateTime.month(.abbreviated).day())
    } else {
      formatted(.dateTime.month(.abbreviated).day().year())
    }
  }
}
