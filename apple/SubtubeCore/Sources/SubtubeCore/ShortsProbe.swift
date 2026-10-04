import Foundation

/// Asks youtube.com/shorts/{id}, which serves 200 for a Short and redirects
/// anything else to /watch. The fallback for when a channel's Shorts list
/// isn't served.
public final class ShortsProbe: NSObject, URLSessionTaskDelegate, Sendable {
  private static let base = "https://www.youtube.com/shorts/"
  private static let userAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"
  private static let timeout: TimeInterval = 5

  private let session: URLSession

  public override init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = Self.timeout
    configuration.timeoutIntervalForResource = Self.timeout
    session = URLSession(configuration: configuration)
    super.init()
  }

  /// True for a Short, false for a redirect (not a Short), nil for anything
  /// else, including an invalid id or a timeout.
  public func probe(_ videoId: String) async -> Bool? {
    guard videoId.wholeMatch(of: #/[A-Za-z0-9_-]{11}/#) != nil,
      let url = URL(string: Self.base + videoId)
    else {
      return nil
    }
    var request = URLRequest(url: url, timeoutInterval: Self.timeout)
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    // pre-consent, so the probe isn't bounced to a consent page
    request.setValue("SOCS=CAI; CONSENT=YES+", forHTTPHeaderField: "Cookie")
    guard let (_, response) = try? await session.data(for: request, delegate: self),
      let status = (response as? HTTPURLResponse)?.statusCode
    else {
      return nil
    }
    return Self.verdict(status: status)
  }

  /// A probe's answer from its status code.
  static func verdict(status: Int) -> Bool? {
    if status == 200 {
      return true
    } else if (300..<400).contains(status) {
      return false
    } else {
      return nil
    }
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }

  /// The probe as `classifyShorts` takes it.
  public var function: ShortsProbeFunction {
    { [self] videoId in await probe(videoId) }
  }
}
