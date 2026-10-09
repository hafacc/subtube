import Foundation
import Testing

@testable import SubtubeCore

/// Hands out "old" until asked to renew, then "new".
private actor RenewableToken: AccessTokenSource {
  private var renewed = false
  private(set) var renewals = 0

  func validToken() -> String { renewed ? "new" : "old" }

  func refreshedToken() -> String {
    renewed = true
    renewals += 1
    return "new"
  }
}

/// A Drive app folder kept in memory, answering the calls `DriveClient` makes.
private final class FakeDrive: URLProtocol, @unchecked Sendable {
  struct State {
    var files: [String: (name: String, content: Data)] = [:]
    /// How often each file was written; its `modifiedTime` says so.
    var versions: [String: Int] = [:]
    /// The ids of the files whose content was downloaded, in order.
    var downloads: [String] = []
    var created = 0
    /// How long an upload takes to answer.
    var uploadDelay: TimeInterval = 0
    /// File names left out of listings although they exist.
    var unlisted = Set<String>()
    /// The only token accepted; nil accepts any.
    var acceptedToken: String?
    var uploads = 0
    var listings = 0
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var state = State()

  static func reset(_ change: (inout State) -> Void = { _ in }) -> URLSession {
    lock.withLock {
      state = State()
      change(&state)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FakeDrive.self]
    return URLSession(configuration: configuration)
  }

  static func change(_ change: (inout State) -> Void) {
    lock.withLock { change(&state) }
  }

  static var current: State { lock.withLock { state } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  private func body() -> Data {
    guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 {
        break
      }
      data.append(buffer, count: count)
    }
    return data
  }

  private func answer(_ status: Int, _ json: String, after delay: TimeInterval = 0) {
    let send = { [self] in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(json.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    if delay > 0 {
      DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: send)
    } else {
      send()
    }
  }

  /// Only called with the lock held.
  private static func described(_ id: String, _ name: String) -> String {
    let version = state.versions[id] ?? 0
    return
      #"{"id": "\#(id)", "name": "\#(name)", "modifiedTime": "2026-10-05T00:00:0\#(version % 10)Z"}"#
  }

  override func startLoading() {
    let url = request.url!
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let fileId = url.lastPathComponent == "files" ? nil : url.lastPathComponent
    let token = request.value(forHTTPHeaderField: "Authorization")?.dropFirst("Bearer ".count)
    let content = body()
    let isUpload = url.path.contains("/upload/")
    let (status, json, delay): (Int, String, TimeInterval) = Self.lock.withLock {
      if let accepted = Self.state.acceptedToken, token.map(String.init) != accepted {
        return (401, "{}", 0)
      } else if isUpload, let fileId {
        Self.state.uploads += 1
        if let file = Self.state.files[fileId] {
          Self.state.files[fileId] = (file.name, content)
          Self.state.versions[fileId, default: 0] += 1
          return (200, Self.described(fileId, file.name), Self.state.uploadDelay)
        } else {
          return (404, "{}", 0)
        }
      } else if isUpload {
        Self.state.uploads += 1
        Self.state.created += 1
        let id = "file\(Self.state.created)"
        // the multipart body's JSON content is its last part
        let text = String(decoding: content, as: UTF8.self)
        let name = text.firstMatch(of: #/"name":"([^"]+)"/#).map { String($0.output.1) } ?? ""
        let parts = text.components(separatedBy: "\r\n\r\n")
        let saved = parts.last?.components(separatedBy: "\r\n--").first ?? ""
        Self.state.files[id] = (name, Data(saved.utf8))
        return (200, Self.described(id, name), Self.state.uploadDelay)
      } else if let fileId, request.httpMethod == "DELETE" {
        Self.state.files[fileId] = nil
        return (204, "", 0)
      } else if let fileId {
        if let file = Self.state.files[fileId] {
          let wantsContent = query.contains { $0.name == "alt" }
          if wantsContent {
            Self.state.downloads.append(fileId)
          }
          return (200, wantsContent ? String(decoding: file.content, as: UTF8.self) : #"{"id": "\#(fileId)"}"#, 0)
        } else {
          return (404, "{}", 0)
        }
      } else {
        Self.state.listings += 1
        let listed = Self.state.files
          .filter { !Self.state.unlisted.contains($0.value.name) }
          .map { Self.described($0.key, $0.value.name) }
        return (200, #"{"files": [\#(listed.joined(separator: ","))]}"#, 0)
      }
    }
    answer(status, json, after: delay)
  }
}

/// Fails the test instead of hanging it when `work` doesn't end in time.
private func finishes(
  within seconds: Double = 5, _ work: @escaping @Sendable () async throws -> Void
) async -> Bool {
  await withTaskGroup(of: Bool.self) { group in
    group.addTask {
      _ = try? await work()
      return true
    }
    group.addTask {
      try? await Task.sleep(for: .seconds(seconds))
      return false
    }
    let first = await group.next() ?? false
    group.cancelAll()
    return first
  }
}

@Suite(.serialized) struct SyncStoreTests {
  private func newDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("subtube-store-\(UUID().uuidString)")
  }

  private func store(
    _ session: URLSession, tokens: any AccessTokenSource = RenewableToken(),
    directory: URL? = nil
  ) -> SyncStore {
    let directory = directory ?? newDirectory()
    return SyncStore(
      accountId: "UCme", tokens: tokens, directory: directory, deviceId: "here", session: session)
  }

  @Test func anEditAndAFlushDuringAnUploadBothEnd() async throws {
    let store = store(FakeDrive.reset { $0.uploadDelay = 0.4 })
    try await store.load()
    await store.setWatched(["first"], watched: true)
    let upload = Task { try await store.save() }
    try await Task.sleep(for: .milliseconds(150))
    await store.setWatched(["second"], watched: true)
    #expect(await finishes { try await store.flush() })
    try await upload.value
    let saved = try #require(FakeDrive.current.files["file1"])
    let file = try #require(parseDeviceFile(saved.content))
    #expect(Set(file.watched.keys) == ["first", "second"])
    #expect(FakeDrive.current.created == 1)
  }

  @Test func severalSavesAtOnceAllEnd() async throws {
    let store = store(FakeDrive.reset { $0.uploadDelay = 0.1 })
    try await store.load()
    await store.setWatched(["first"], watched: true)
    #expect(
      await finishes {
        await withTaskGroup(of: Void.self) { group in
          for _ in 0..<4 {
            group.addTask { try? await store.save() }
          }
        }
      })
    #expect(FakeDrive.current.created == 1)
  }

  @Test func deletingTheProfileDuringAnUploadEnds() async throws {
    let store = store(FakeDrive.reset { $0.uploadDelay = 0.4 })
    try await store.load()
    await store.setWatched(["first"], watched: true)
    let upload = Task { try await store.save() }
    try await Task.sleep(for: .milliseconds(150))
    #expect(await finishes { try await store.deleteProfile() })
    _ = try? await upload.value
    #expect(FakeDrive.current.files.isEmpty)
    await #expect(throws: SyncError.self) { try await store.load() }
  }

  @Test func aListingWithoutThisDevicesFileDoesNotWipeWhileTheFileExists() async throws {
    let store = store(FakeDrive.reset())
    try await store.load()
    await store.setWatched(["first"], watched: true)
    try await store.save()
    FakeDrive.change { $0.unlisted = ["device-here.json"] }
    try await store.load()
    #expect(await store.watchedEntries(["first"])["first"]?.watched == true)
    await store.setWatched(["second"], watched: true)
    try await store.save()
    #expect(FakeDrive.current.created == 1)
  }

  @Test func aFileGoneFromDriveWipesTheProfile() async throws {
    let store = store(FakeDrive.reset())
    try await store.load()
    await store.setWatched(["first"], watched: true)
    try await store.save()
    FakeDrive.change { $0.files = [:] }
    await #expect(throws: SyncError.self) { try await store.load() }
    #expect(await store.watchedEntries(["first"]).isEmpty)
  }

  @Test func aListingAskedForDuringTheFirstUploadDecidesNothing() async throws {
    let store = store(FakeDrive.reset { $0.uploadDelay = 0.3 })
    try await store.load()
    await store.setWatched(["first"], watched: true)
    let upload = Task { try await store.save() }
    try await Task.sleep(for: .milliseconds(100))
    try await store.load()
    try await upload.value
    FakeDrive.change { $0.uploadDelay = 0 }
    await store.setWatched(["second"], watched: true)
    try await store.save()
    #expect(FakeDrive.current.created == 1)
  }

  @Test func aRefusedSaveRenewsTheTokenOnceAndGoesUp() async throws {
    let tokens = RenewableToken()
    let store = store(FakeDrive.reset(), tokens: tokens)
    try await store.load()
    FakeDrive.change { $0.acceptedToken = "new" }
    await store.setWatched(["first"], watched: true)
    try await store.save()
    #expect(await tokens.renewals == 1)
    #expect(FakeDrive.current.created == 1)
  }

  @Test func aPositionSavedWhilePlayingShowsAtOnceAndIsOnDiskWhenAsked() async throws {
    let session = FakeDrive.reset()
    let directory = newDirectory()
    let store = store(session, directory: directory)
    try await store.load()
    await store.setWatched(["marked"], watched: true)
    await store.setProgress("video", position: 40, ended: false, upload: false)
    #expect(await store.watchedEntries(["video"])["video"]?.position == 40)
    #expect(await store.watchedEntries(["marked"])["marked"]?.watched == true)
    let before = self.store(session, directory: directory)
    #expect(await before.watchedEntries(["video"]).isEmpty)
    await store.persist()
    let after = self.store(session, directory: directory)
    #expect(await after.watchedEntries(["video"])["video"]?.position == 40)
  }

  @Test func aPositionSavedForDriveIsOnDiskAtOnce() async throws {
    let session = FakeDrive.reset()
    let directory = newDirectory()
    let store = store(session, directory: directory)
    try await store.load()
    await store.setProgress("video", position: 40, ended: false, upload: true)
    let reopened = self.store(session, directory: directory)
    #expect(await reopened.watchedEntries(["video"])["video"]?.position == 40)
  }

  @Test func aPositionSavedHereDoesNotBeatANewerEntryFromAnotherDevice() async throws {
    let later = epochMilliseconds() + 3_600_000
    let other = DeviceFile(watched: ["video": WatchedEntry(at: later, watched: true)])
    let content = try encodeDeviceFile(other)
    let store = store(FakeDrive.reset { $0.files["other"] = ("device-there.json", content) })
    try await store.load()
    await store.setProgress("video", position: 40, ended: false, upload: false)
    #expect(await store.watchedEntries(["video"])["video"] == other.watched["video"])
  }

  @Test func aLoadDoesNotDownloadThisDevicesFileAgainWhileItIsUnchanged() async throws {
    let store = store(FakeDrive.reset())
    try await store.load()
    await store.setWatched(["first"], watched: true)
    try await store.save()
    try await store.load()
    #expect(FakeDrive.current.downloads.isEmpty)
    await store.setWatched(["second"], watched: true)
    try await store.save()
    try await store.load()
    #expect(FakeDrive.current.downloads.isEmpty)
    #expect(Set(await store.watchedEntries(["first", "second"]).keys) == ["first", "second"])
  }

  @Test func aLoadDownloadsThisDevicesFileOnceWhenItWasNotUploadedFromHere() async throws {
    let earlier = DeviceFile(watched: ["first": WatchedEntry(at: 1, watched: true)])
    let content = try encodeDeviceFile(earlier)
    let store = store(FakeDrive.reset { $0.files["mine"] = ("device-here.json", content) })
    try await store.load()
    #expect(FakeDrive.current.downloads == ["mine"])
    #expect(await store.watchedEntries(["first"])["first"]?.watched == true)
    try await store.load()
    #expect(FakeDrive.current.downloads == ["mine"])
  }

  @Test func aLoadDownloadsThisDevicesFileWhenDriveHasANewerOne() async throws {
    let store = store(FakeDrive.reset())
    try await store.load()
    await store.setWatched(["first"], watched: true)
    try await store.save()
    let changed = DeviceFile(watched: [
      "elsewhere": WatchedEntry(at: epochMilliseconds(), watched: true)
    ])
    let content = try encodeDeviceFile(changed)
    FakeDrive.change {
      $0.files["file1"] = ("device-here.json", content)
      $0.versions["file1", default: 0] += 1
    }
    try await store.load()
    #expect(FakeDrive.current.downloads == ["file1"])
    #expect(await store.watchedEntries(["elsewhere"])["elsewhere"]?.watched == true)
  }

  @Test func aFlushThatIsStartedIsNotWaitedForAndStillGoesUp() async throws {
    let store = store(FakeDrive.reset { $0.uploadDelay = 0.3 })
    try await store.load()
    #expect(await store.startFlush() == nil)
    await store.setProgress("video", position: 40, ended: false, upload: true)
    let upload = try #require(await store.startFlush())
    #expect(FakeDrive.current.files.isEmpty)
    try await upload.value
    let saved = try #require(FakeDrive.current.files["file1"])
    #expect(parseDeviceFile(saved.content)?.watched["video"]?.position == 40)
  }
}
