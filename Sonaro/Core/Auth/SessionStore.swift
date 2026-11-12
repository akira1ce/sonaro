import Foundation
import os

/// Single source of truth for the persisted session, shared by the API client
/// (reads the cookie) and the auth manager (writes it). The cookie lives in the
/// Keychain; a lightweight profile snapshot is cached in UserDefaults so the UI
/// can render instantly on cold launch before re-validation finishes.
final class SessionStore {
    static let shared = SessionStore()
    private init() {
        cookieLock = OSAllocatedUnfairLock(initialState: Keychain.get(cookieKey))
    }

    private let cookieKey = "session.cookie"
    private let profileKey = "session.profile"

    /// The in-memory cookie is read off the main actor by `APIClient` on every
    /// request and written on the main actor by `AuthManager` at login/logout, so
    /// it's guarded by a lock to keep those accesses from racing. The Keychain is
    /// the durable backing store.
    private let cookieLock: OSAllocatedUnfairLock<String?>

    /// The full cookie string returned by the QR check (`MUSIC_U=...; ...`).
    var cookie: String? {
        get { cookieLock.withLock { $0 } }
        set {
            cookieLock.withLock { $0 = newValue }
            Keychain.set(newValue, for: cookieKey)
        }
    }

    var isLoggedIn: Bool { SessionCookie.hasLoginCredential(cookie) }

    var cachedProfile: Profile? {
        get {
            guard let data = UserDefaults.standard.data(forKey: profileKey) else { return nil }
            return try? JSONDecoder().decode(Profile.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: profileKey)
            } else {
                UserDefaults.standard.removeObject(forKey: profileKey)
            }
        }
    }

    func clear() {
        cookie = nil
        cachedProfile = nil
    }
}
