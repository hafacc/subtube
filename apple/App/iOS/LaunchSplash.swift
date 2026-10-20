import SubtubeCore
import SwiftUI

/// The first screen after launch until the first feed has loaded: the
/// launch screen's logo, at its size and in its place, playing, with the
/// load bar under it.
///
/// iOS draws `LaunchLogo` at its size in points, centered on the whole
/// screen whatever the safe areas, so the logo here is a box of that size
/// at the screen's center, and the bar lies over the space below it
/// without moving it.
struct LaunchSplash: View {
  /// The feed whose load the bar shows; nil while the sign-in is looked for.
  let feed: FeedModel?

  // launch-logo.svg's width and height
  private static let side: CGFloat = 192
  // the bar's width, and its gap under the logo's box
  private static let barWidth: CGFloat = 188
  private static let barGap: CGFloat = 38
  private static let barHeight: CGFloat = 3

  var body: some View {
    GeometryReader { proxy in
      MovingLogo(framing: Logo.alone, loading: true)
        .frame(width: Self.side, height: Self.side)
        .overlay(alignment: .bottom) {
          if let feed {
            LoadProgressBar(feed: feed)
              .frame(width: Self.barWidth)
              .background(Color.secondary.opacity(0.15))
              .clipShape(Capsule())
              .offset(y: Self.barGap + Self.barHeight)
          }
        }
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .ignoresSafeArea()
    .background(Color("LaunchPage").ignoresSafeArea())
  }
}
