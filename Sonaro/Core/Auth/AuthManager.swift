import Foundation
import SwiftUI

/// Owns authentication: cold-launch session validation (so users don't re-login
/// every time), the QR-code login flow, and logout.
@MainActor
final class AuthManager: ObservableObject {

    enum SessionState: Equatable {
        case unknown        // still validating the cached cookie on launch
        case loggedOut
        case loggedIn
    }

    enum QRPhase: Equatable {
        case idle
        case loading            // fetching key / creating QR
        case waiting            // QR shown, waiting for scan
        case scanned            // scanned, waiting for confirmation on phone
        case expired
        case succeeded
        case failed(String)
    }

    @Published private(set) var state: SessionState = .unknown
    @Published private(set) var profile: Profile?

    // QR login UI state
    @Published private(set) var qrImage: PlatformImage?
    @Published private(set) var qrPhase: QRPhase = .idle

    private var loginToken = UUID()
    private var pollTask: Task<Void, Never>?

    // MARK: - Launch

    /// Validates a cached cookie. Shows cached profile immediately for a snappy
    /// launch, then confirms with NetEase.
    func bootstrap() async {
        guard SessionStore.shared.isLoggedIn else {
            state = .loggedOut
            return
        }
        // Optimistic: trust the cached session so the UI doesn't flash the login screen.
        profile = SessionStore.shared.cachedProfile
        state = .loggedIn

        // A transient network / decoding hiccup must not sign the user out, but a
        // response that contains no profile means the cached cookie is dead —
        // clear it so the login screen shows instead of silently failing requests.
        let token = loginToken
        let result = await refreshProfile()
        guard token == loginToken else { return }
        switch result {
        case .success(let p):
            profile = p
            SessionStore.shared.cachedProfile = p
        case .unauthenticated:
            await performLogout()
        case .unavailable:
            break
        }
    }

    // MARK: - Profile

    /// Canonical account endpoint — returns the full profile.
    private struct AccountResponse: Decodable { let profile: Profile? }

    private enum ProfileResult {
        case success(Profile)
        /// NetEase answered normally but reported no signed-in user.
        case unauthenticated
        /// Transport or decoding failure — the session may still be valid.
        case unavailable
    }

    private func refreshProfile() async -> ProfileResult {
        do {
            let resp: AccountResponse = try await APIClient.shared.get("/api/w/nuser/account/get")
            if let p = resp.profile, p.userId != 0 { return .success(p) }
            return .unauthenticated
        } catch APIError.sessionExpired {
            return .unauthenticated
        } catch {
            return .unavailable
        }
    }

    // MARK: - QR login

    private struct QRKeyResponse: Decodable { let unikey: String? }
    private struct QRCheckResponse: Decodable { let code: Int }

    /// Generates a fresh QR code and begins polling for scan status.
    func startQRLogin() async {
        stopPolling()
        let token = loginToken
        qrImage = nil
        qrPhase = .loading

        do {
            let key: QRKeyResponse = try await APIClient.shared.get(
                "/api/login/qrcode/unikey", query: ["type": 3], authenticated: false)
            guard token == loginToken, !Task.isCancelled else { return }
            guard let unikey = key.unikey else {
                qrPhase = .failed("获取二维码失败"); return
            }
            guard let encoded = unikey.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let image = QRCodeRenderer.image(from: "https://music.163.com/login?codekey=\(encoded)") else {
                qrPhase = .failed("生成二维码失败"); return
            }
            qrImage = image
            qrPhase = .waiting
            beginPolling(unikey: unikey)
        } catch {
            guard token == loginToken, !Task.isCancelled else { return }
            qrPhase = .failed((error as? APIError)?.errorDescription ?? "网络错误")
        }
    }

    private func beginPolling(unikey: String) {
        let token = loginToken
        let deadline = Date().addingTimeInterval(120)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                guard token == self.loginToken else { return }
                if Date() >= deadline {
                    self.qrPhase = .expired
                    return
                }
                await self.checkOnce(unikey: unikey, token: token)
                let phase = self.qrPhase
                if phase == .succeeded || phase == .expired { return }
                if case .failed = phase { return }
            }
        }
    }

    private func checkOnce(unikey: String, token: UUID) async {
        do {
            let response = try await APIClient.shared.response(
                "/api/login/qrcode/client/login", query: ["key": unikey, "type": 3], authenticated: false, raw: true)
            guard token == loginToken, !Task.isCancelled else { return }
            let resp = try JSONDecoder().decode(QRCheckResponse.self, from: response.data)
            switch resp.code {
            case 801: qrPhase = .waiting
            case 802: qrPhase = .scanned
            case 803:
                let cookie = response.cookie
                guard SessionCookie.hasLoginCredential(cookie) else {
                    qrPhase = .failed("登录未返回有效凭证，请重新扫码")
                    return
                }
                SessionStore.shared.cookie = cookie
                qrPhase = .succeeded
                await finishLogin(token: token)
            case 800:
                qrPhase = .expired
            default:
                qrPhase = .failed("网易云无法完成扫码登录，请在官方客户端完成安全验证后重试")
            }
        } catch {
            // Transient error — keep polling.
        }
    }

    private func finishLogin(token: UUID) async {
        let result = await refreshProfile()
        guard token == loginToken, !Task.isCancelled else { return }
        if case .unauthenticated = result {
            await performLogout()
            qrPhase = .failed("登录凭证未通过验证，请重新扫码")
            return
        }
        if case .success(let p) = result {
            profile = p
            SessionStore.shared.cachedProfile = p
        }
        state = .loggedIn
    }

    func stopPolling() {
        loginToken = UUID()
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Logout

    func logout() async {
        await performLogout()
    }

    private func performLogout() async {
        stopPolling()
        SessionStore.shared.clear()
        profile = nil
        qrImage = nil
        qrPhase = .idle
        state = .loggedOut
    }

    #if DEBUG
    /// Bypasses login for UI screenshots.
    func enterDemoMode() {
        profile = Profile(userId: 1, nickname: "Demo User", avatarUrl: nil)
        state = .loggedIn
    }
    #endif
}
