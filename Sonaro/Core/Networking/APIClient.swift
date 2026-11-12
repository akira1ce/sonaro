import Foundation

/// Thin async wrapper over URLSession that knows how to talk to the
/// MusicApiEnhanced backend: base URL, cookie injection, and cache
/// busting.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        // Identity and account cookies are explicitly composed as query items.
        // Do not let an ambient URLSession cookie leak into anonymous QR calls.
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpCookieStorage = nil
        session = URLSession(configuration: cfg)
    }

    // MARK: Requests

    /// Fetches raw data for an endpoint.
    /// - Parameters:
    ///   - path: leading-slash path, e.g. `/recommend/songs`.
    ///   - query: extra query items.
    ///   - authenticated: attach the account cookie; device identity is always included.
    ///   - freshness: append a timestamp so the backend's 2-minute cache is bypassed
    ///                (required for login polling and status checks).
    func data(_ path: String,
              query: [String: String] = [:],
              authenticated: Bool = true,
              freshness: Bool = false) async throws -> Data {
        guard var components = URLComponents(string: APIConfig.baseURL + path) else {
            throw APIError.invalidURL
        }
        var items = components.queryItems ?? []
        for (k, v) in query.sorted(by: { $0.key < $1.key }) where k != "cookie" {
            items.append(URLQueryItem(name: k, value: v))
        }
        let accountCookie = authenticated ? (query["cookie"] ?? SessionStore.shared.cookie) : nil
        do {
            let cookie = try DeviceIdentityStore.shared.cookie(accountCookie: accountCookie)
            items.removeAll { $0.name == "cookie" }
            items.append(URLQueryItem(name: "cookie", value: cookie))
        } catch {
            throw APIError.deviceIdentity(error)
        }
        if freshness {
            items.append(URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                if http.statusCode == 301 { throw APIError.sessionExpired }
                throw APIError.http(http.statusCode, message: Self.errorMessage(from: data))
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Fetches and decodes a JSON response.
    func get<T: Decodable>(_ path: String,
                           query: [String: String] = [:],
                           authenticated: Bool = true,
                           freshness: Bool = false,
                           as type: T.Type = T.self) async throws -> T {
        let data = try await self.data(path, query: query, authenticated: authenticated, freshness: freshness)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Non-2xx bodies still carry a human-readable reason (e.g. the upstream
    /// risk-control 400), which is worth surfacing instead of a bare status.
    private struct ErrorBody: Decodable {
        let message: String?
        let msg: String?
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return body.message ?? body.msg
    }
}
