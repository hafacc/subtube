#if DEBUG
  import AppKit

  /// With `-snapshot:<name>`, write every visible window as PNG to
  /// `snapshots/<name>` in the app's temporary directory (inside its sandbox
  /// container) a few seconds after launch, and again as `later-…` half a
  /// second on to show what moves, then quit; for comparing screens with the
  /// mockups without screen-recording permission.
  enum DebugSnapshot {
    static func scheduleIfAsked() {
      let arguments = CommandLine.arguments
      guard let name = debugArgument("snapshot") else { return }
      let directory = URL.temporaryDirectory.appending(path: "snapshots/\(name)")
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if arguments.contains("-settings") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
      }
      @MainActor func capture(_ prefix: String) {
        var report: [String] = []
        for (index, window) in NSApp.windows.enumerated() {
          report.append("\(index) \(window.title) visible=\(window.isVisible) \(window.frame)")
          guard window.isVisible, let view = window.contentView?.superview ?? window.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
          else { continue }
          view.cacheDisplay(in: view.bounds, to: bitmap)
          let url = directory.appending(path: "\(prefix)window-\(index).png")
          try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
          if let layer = view.layer, let layered = view.bitmapImageRepForCachingDisplay(in: view.bounds),
            let context = NSGraphicsContext(bitmapImageRep: layered)
          {
            layer.render(in: context.cgContext)
            try? layered.representation(using: .png, properties: [:])?.write(
              to: directory.appending(path: "\(prefix)layer-\(index).png"))
          }
        }
        try? report.joined(separator: "\n").write(
          to: directory.appending(path: "windows.txt"), atomically: true, encoding: .utf8)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 8) { capture("") }
      DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) {
        capture("later-")
        NSApp.terminate(nil)
      }
    }
  }
#endif
