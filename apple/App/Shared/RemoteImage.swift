import SwiftUI

#if os(macOS)
  import AppKit

  private typealias PlatformImage = NSImage
#else
  import UIKit

  private typealias PlatformImage = UIImage
#endif

/// The pictures fetched so far, decoded, and the requests still running.
@MainActor
private final class ImageStore {
  static let shared = ImageStore()

  private let cache = NSCache<NSURL, PlatformImage>()
  private var running: [URL: Task<PlatformImage?, Never>] = [:]

  private init() {
    cache.totalCostLimit = 64 << 20
  }

  /// The picture at `url` if it is held, without waiting.
  func held(_ url: URL) -> PlatformImage? {
    cache.object(forKey: url as NSURL)
  }

  /// The picture at `url`, fetched unless it is held; nil when it can't be
  /// had. Everyone asking for one address while it is fetched shares the
  /// request.
  func image(_ url: URL) async -> PlatformImage? {
    if let held = held(url) {
      return held
    } else if let request = running[url] {
      return await request.value
    } else {
      // not the asking view's task: others may be waiting for it when that view goes
      let request = Task.detached { await Self.fetch(url) }
      running[url] = request
      let image = await request.value
      running[url] = nil
      if let image {
        cache.setObject(image, forKey: url as NSURL, cost: Self.bytes(of: image))
      }
      return image
    }
  }

  nonisolated private static func fetch(_ url: URL) async -> PlatformImage? {
    if let (data, response) = try? await URLSession.shared.data(from: url),
      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
    {
      #if os(macOS)
        return NSImage(data: data)
      #else
        return await UIImage(data: data)?.byPreparingForDisplay()
      #endif
    } else {
      return nil
    }
  }

  /// Roughly what a decoded picture takes in memory.
  private static func bytes(of image: PlatformImage) -> Int {
    #if os(macOS)
      image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 0
    #else
      image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
    #endif
  }
}

/// A picture from the network filling the room it is given, with
/// `placeholder` in its place until it is there.
///
/// A picture fetched before shows at once, with no placeholder first, and
/// views asking for the same address share one request.
struct RemoteImage<Placeholder: View>: View {
  let url: URL?
  @ViewBuilder let placeholder: Placeholder
  /// What this view fetched; it outlives the cache dropping it.
  @State private var fetched: Fetched?

  private struct Fetched {
    let url: URL
    let image: PlatformImage
  }

  private var image: PlatformImage? {
    url.flatMap { url in
      fetched?.url == url ? fetched?.image : ImageStore.shared.held(url)
    }
  }

  var body: some View {
    Color.clear
      .overlay {
        if let image {
          #if os(macOS)
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
          #else
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
          #endif
        } else {
          placeholder
        }
      }
      .task(id: url) {
        if let url, let image = await ImageStore.shared.image(url) {
          fetched = Fetched(url: url, image: image)
        }
      }
  }
}
