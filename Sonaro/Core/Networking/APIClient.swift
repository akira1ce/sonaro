import Foundation

/// Native EAPI requests; account cookies are sent only to the NetEase API origin.
final class APIClient: NSObject, URLSessionTaskDelegate {
    static let shared = APIClient()
    private var session: URLSession!
    private let deviceID: () throws -> String

    init(session: URLSession? = nil,
         deviceID: @escaping () throws -> String = { try DeviceIdentityStore.shared.deviceID() }) {
        self.deviceID = deviceID
        super.init()
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            cfg.timeoutIntervalForRequest = 20
            cfg.timeoutIntervalForResource = 30
            cfg.httpShouldSetCookies = false
            cfg.httpCookieAcceptPolicy = .never
            cfg.httpCookieStorage = nil
            self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        }
    }

    // A redirect must never forward account credentials to another origin.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func response(_ path: String, query: [String: Any] = [:], authenticated: Bool = true,
                  raw: Bool = false) async throws -> (data: Data, cookie: String) {
        let accountCookie = authenticated ? SessionStore.shared.cookie : nil
        let jar = SessionCookie.fields(accountCookie)
        let identity: String
        do { identity = try deviceID() } catch { throw APIError.deviceIdentity(error) }
        let header = jar.merging([
            "os": "pc", "appver": "3.1.11", "deviceId": identity, "versioncode": "140",
            "osver": "Microsoft-Windows-10-Professional-build-19045-64bit",
            "channel": "netease", "resolution": "1920x1080", "__csrf": jar["__csrf"] ?? "",
            "requestId": "\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 0..<10000))"
        ]) { _, device in device }
        var payload = query
        payload["header"] = header
        let encoded: Data
        do { encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]) }
        catch { throw APIError.decoding(error) }
        let params = try EAPI.encrypt(path: path, json: String(decoding: encoded, as: UTF8.self))
        guard let url = URL(string: APIConfig.baseURL + "/eapi/" + String(path.dropFirst(5))) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(header.keys.sorted().map { "\($0)=\(header[$0]!)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.httpBody = Data("params=\(params)".utf8)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.transport(error) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidURL }
        let result: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.api(code: 0, message: "网易云返回了无法识别的响应")
            }
            result = object
        } catch {
            if !(200..<300).contains(http.statusCode) { throw APIError.http(http.statusCode, message: nil) }
            throw APIError.decoding(error)
        }
        let message = (result["message"] ?? result["msg"]) as? String
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.sessionExpired }
            throw APIError.http(http.statusCode, message: message)
        }
        let code = (result["code"] as? NSNumber)?.intValue ?? 200
        if !raw && code != 200 {
            if [301, 302, 401].contains(code) { throw APIError.sessionExpired }
            if [-462, 405].contains(code) {
                throw APIError.api(code: code, message: "网易云要求安全验证，请先在官方客户端完成验证后重试")
            }
            throw APIError.api(code: code, message: message)
        }
        var cookies = jar
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            cookies[cookie.name] = cookie.value
        }
        return (data, cookies.keys.sorted().map { "\($0)=\(cookies[$0]!)" }.joined(separator: "; "))
    }

    func data(_ path: String, query: [String: Any] = [:], authenticated: Bool = true) async throws -> Data {
        try await response(path, query: query, authenticated: authenticated).data
    }

    func get<T: Decodable>(_ path: String, query: [String: Any] = [:], authenticated: Bool = true,
                           as type: T.Type = T.self) async throws -> T {
        let data = try await self.data(path, query: query, authenticated: authenticated)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
