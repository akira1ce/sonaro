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

    private var unikey: String?
    private var pollTask: Task<Void, Never>?

    // MARK: - Launch

    /// Validates a cached cookie. Shows cached profile immediately for a snappy
    /// launch, then confirms with the backend.
    func bootstrap() async {
        guard SessionStore.shared.isLoggedIn else {
            state = .loggedOut
            return
        }
        // Optimistic: trust the cached session so the UI doesn't flash the login screen.
        profile = SessionStore.shared.cachedProfile
        state = .loggedIn

        // A transient network / decoding hiccup must not sign the user out, but a
        // backend that answers with no profile means the cached cookie is dead —
        // clear it so the login screen shows instead of silently failing requests.
        switch await refreshProfile() {
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

    /// `/login/status` wraps the profile inside `data`.
    private struct StatusResponse: Decodable {
        struct DataBlock: Decodable { let profile: Profile? }
        let data: DataBlock?
    }

    private enum ProfileResult {
        case success(Profile)
        /// The backend answered normally but reported no signed-in user.
        case unauthenticated
        /// Transport or decoding failure — the session may still be valid.
        case unavailable
    }

    /// Fetches the user's profile, trying `/user/account` first (full object) and
    /// falling back to `/login/status`.
    private func refreshProfile() async -> ProfileResult {
        var sawResponse = false

        do {
            let data = try await APIClient.shared.data("/user/account", authenticated: true, freshness: true)
            #if DEBUG
            print("🔍 /user/account raw:", String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")
            #endif
            if let resp = try? JSONDecoder().decode(AccountResponse.self, from: data) {
                if let p = resp.profile, p.userId != 0 { return .success(p) }
                sawResponse = true
            }
        } catch APIError.sessionExpired {
            return .unauthenticated
        } catch {
            // Transient — fall through to the status endpoint.
        }

        do {
            let data = try await APIClient.shared.data("/login/status", authenticated: true, freshness: true)
            #if DEBUG
            print("🔍 /login/status raw:", String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")
            #endif
            if let resp = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                if let p = resp.data?.profile, p.userId != 0 { return .success(p) }
                sawResponse = true
            }
        } catch APIError.sessionExpired {
            return .unauthenticated
        } catch {
            // Transient — keep the cached session.
        }

        return sawResponse ? .unauthenticated : .unavailable
    }

    // MARK: - QR login

    private struct QRKeyResponse: Decodable {
        struct DataBlock: Decodable { let unikey: String? }
        let data: DataBlock?
    }
    private struct QRCreateResponse: Decodable {
        struct DataBlock: Decodable { let qrurl: String? }
        let data: DataBlock?
    }
    private struct QRCheckResponse: Decodable {
        let code: Int
        let cookie: String?
        let message: String?
    }

    /// Generates a fresh QR code and begins polling for scan status.
    func startQRLogin() async {
        stopPolling()
        qrImage = nil
        qrPhase = .loading

        do {
            let key: QRKeyResponse = try await APIClient.shared.get(
                "/login/qr/key", authenticated: false, freshness: true)
            guard let unikey = key.data?.unikey else {
                qrPhase = .failed("获取二维码失败"); return
            }
            self.unikey = unikey

            let create: QRCreateResponse = try await APIClient.shared.get(
                "/login/qr/create", query: ["key": unikey], authenticated: false, freshness: true)
            guard let qrurl = create.data?.qrurl,
                  let image = QRCodeRenderer.image(from: qrurl) else {
                qrPhase = .failed("生成二维码失败"); return
            }
            qrImage = image
            qrPhase = .waiting
            beginPolling(unikey: unikey)
        } catch {
            qrPhase = .failed((error as? APIError)?.errorDescription ?? "网络错误")
        }
    }

    private func beginPolling(unikey: String) {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                await self.checkOnce(unikey: unikey)
                let phase = self.qrPhase
                if phase == .succeeded || phase == .expired { return }
            }
        }
    }

    private func checkOnce(unikey: String) async {
        do {
            let resp: QRCheckResponse = try await APIClient.shared.get(
                "/login/qr/check", query: ["key": unikey], authenticated: false, freshness: true)
            switch resp.code {
            case 801: qrPhase = .waiting
            case 802: qrPhase = .scanned
            case 803:
                if let cookie = resp.cookie, !cookie.isEmpty {
                    SessionStore.shared.cookie = cookie
                }
                qrPhase = .succeeded
                await finishLogin()
            case 800:
                qrPhase = .expired
            default:
                break
            }
        } catch {
            // Transient error — keep polling.
        }
    }

    private func finishLogin() async {
        if case .success(let p) = await refreshProfile() {
            profile = p
            SessionStore.shared.cachedProfile = p
        }
        state = .loggedIn
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Logout

    func logout() async {
        _ = try? await APIClient.shared.data("/logout", authenticated: true, freshness: true)
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
