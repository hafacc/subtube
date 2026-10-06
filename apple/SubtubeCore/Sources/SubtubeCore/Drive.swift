import Foundation

/// A file in the Drive app folder.
public struct DriveFile: Codable, Sendable, Hashable {
  /// Drive's id of the file.
  public var id: String
  /// The file's name.
  public var name: String
  /// RFC 3339, as Drive sends it; compared only for equality.
  public var modifiedTime: String
}

/// The Google account behind a token, as Drive reports it.
public struct DriveUser: Codable, Sendable, Hashable {
  /// The account's name.
  public var displayName: String
  /// The account's address, when Drive gives it.
  public var emailAddress: String?
  /// Avatar URL, or nil.
  public var photoLink: String?
}

/// The Drive app folder (`appDataFolder`): files only this Google Cloud
/// project's OAuth clients can see.
public struct DriveClient: Sendable {
  private static let filesEndpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!
  private static let aboutEndpoint = URL(string: "https://www.googleapis.com/drive/v3/about")!
  private static let uploadEndpoint = URL(
    string: "https://www.googleapis.com/upload/drive/v3/files")!

  /// The token every call is made with.
  public let accessToken: String
  /// The session the calls go through.
  public let session: URLSession

  /// A client for one access token.
  public init(accessToken: String, session: URLSession = .shared) {
    self.accessToken = accessToken
    self.session = session
  }

  private func send(_ request: URLRequest) async throws -> Data {
    var authorized = request
    authorized.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (body, response) = try await session.data(for: authorized)
    try checkGoogleResponse(response, body: body)
    return body
  }

  private func url(_ base: URL, path: String? = nil, query: [String: String]) -> URL {
    var components = URLComponents(
      url: path.map { base.appendingPathComponent($0) } ?? base, resolvingAgainstBaseURL: false)!
    components.queryItems = query.sorted { $0.key < $1.key }.map {
      URLQueryItem(name: $0.key, value: $0.value)
    }
    return components.url!
  }

  /// The signed-in Google account's name and address; the app-folder scope
  /// is enough to ask.
  public func about() async throws -> DriveUser {
    struct About: Decodable { var user: DriveUser }
    let body = try await send(
      URLRequest(url: url(Self.aboutEndpoint, query: ["fields": "user"])))
    return try JSONDecoder().decode(About.self, from: body).user
  }

  /// Every file in the app folder.
  public func listAppFiles() async throws -> [DriveFile] {
    struct Page: Decodable {
      var files: [DriveFile]
      var nextPageToken: String?
    }
    var files: [DriveFile] = []
    var pageToken: String?
    repeat {
      var query = [
        "spaces": "appDataFolder", "fields": "nextPageToken,files(id,name,modifiedTime)",
        "pageSize": "100",
      ]
      query["pageToken"] = pageToken
      let body = try await send(URLRequest(url: url(Self.filesEndpoint, query: query)))
      let page = try JSONDecoder().decode(Page.self, from: body)
      files += page.files
      pageToken = page.nextPageToken
    } while pageToken != nil
    return files
  }

  /// A file's raw content.
  public func download(_ fileId: String) async throws -> Data {
    try await send(
      URLRequest(url: url(Self.filesEndpoint, path: fileId, query: ["alt": "media"])))
  }

  /// Whether a file is still in Drive, asked for by its id.
  public func exists(_ fileId: String) async throws -> Bool {
    do {
      _ = try await send(URLRequest(url: url(Self.filesEndpoint, path: fileId, query: ["fields": "id"])))
      return true
    } catch GoogleAPIError.http(status: 404, _) {
      return false
    }
  }

  /// Delete a file for good.
  public func delete(_ fileId: String) async throws {
    var request = URLRequest(url: url(Self.filesEndpoint, path: fileId, query: [:]))
    request.httpMethod = "DELETE"
    _ = try await send(request)
  }

  /// Create a JSON file in the app folder.
  public func createJSON(name: String, content: Data) async throws -> DriveFile {
    let boundary = "subtube-\(UUID().uuidString)"
    let metadata = try JSONSerialization.data(
      withJSONObject: ["name": name, "parents": ["appDataFolder"]])
    var body = Data()
    body += Data(
      "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
    body += metadata
    body += Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8)
    body += content
    body += Data("\r\n--\(boundary)--".utf8)
    var request = URLRequest(
      url: url(
        Self.uploadEndpoint,
        query: ["uploadType": "multipart", "fields": "id,name,modifiedTime"]))
    request.httpMethod = "POST"
    request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return try JSONDecoder().decode(DriveFile.self, from: try await send(request))
  }

  /// Replace a file's content.
  public func updateJSON(fileId: String, content: Data) async throws -> DriveFile {
    var request = URLRequest(
      url: url(
        Self.uploadEndpoint, path: fileId,
        query: ["uploadType": "media", "fields": "id,name,modifiedTime"]))
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = content
    return try JSONDecoder().decode(DriveFile.self, from: try await send(request))
  }
}
