import XCTest
@testable import Sonaro

final class DeviceIdentityTests: XCTestCase {
    private let firstID = String(repeating: "A", count: 52)
    private let otherID = String(repeating: "B", count: 52)

    func testIdentityIsPersistedAndReusedAcrossStoreInstances() throws {
        var saved: String?
        var creations = 0
        let first = DeviceIdentityStore(load: { saved }, create: {
            creations += 1
            saved = $0
            return true
        }, generate: { self.firstID })
        XCTAssertEqual(try first.deviceID(), firstID)

        let reopened = DeviceIdentityStore(load: { saved }, create: { _ in
            XCTFail("An existing identity must not be replaced")
            return false
        }, generate: {
            XCTFail("An existing identity must not be regenerated")
            return self.otherID
        })

        XCTAssertEqual(try reopened.deviceID(), firstID)
        XCTAssertEqual(creations, 1)
    }

    func testConcurrentCreationUsesTheIdentityAlreadyStored() throws {
        var saved: String?
        let store = DeviceIdentityStore(load: { saved }, create: { _ in
            saved = self.otherID
            return false
        }, generate: { self.firstID })

        XCTAssertEqual(try store.deviceID(), otherID)
    }

    func testStorageFailureDoesNotReturnAnEphemeralIdentity() {
        struct StorageFailure: Error {}
        let store = DeviceIdentityStore(load: { nil }, create: { _ in
            throw StorageFailure()
        }, generate: { self.firstID })

        XCTAssertThrowsError(try store.deviceID())
        XCTAssertThrowsError(try store.cookie(accountCookie: nil))
    }

    func testReadFailureDoesNotCreateANewIdentity() {
        struct StorageFailure: Error {}
        let store = DeviceIdentityStore(load: { throw StorageFailure() }, create: { _ in
            XCTFail("A failed read must not replace the stored identity")
            return true
        })

        XCTAssertThrowsError(try store.deviceID())
    }

    func testRestoredKeychainAccessReusesTheExistingIdentity() throws {
        struct StorageFailure: Error {}
        var accessible = false
        let store = DeviceIdentityStore(load: {
            guard accessible else { throw StorageFailure() }
            return self.firstID
        }, create: { _ in
            XCTFail("Restoring access must not replace the existing identity")
            return true
        })

        XCTAssertThrowsError(try store.deviceID())
        accessible = true
        XCTAssertEqual(try store.deviceID(), firstID)
    }

    func testMalformedStoredIdentityIsNotSilentlyReplaced() {
        let store = DeviceIdentityStore(load: { "invalid" }, create: { _ in
            XCTFail("A malformed identity must not be silently replaced")
            return true
        })

        XCTAssertThrowsError(try store.deviceID())
    }

    func testCookiesUseTheSameIdentityBeforeAndAfterLogin() throws {
        let store = DeviceIdentityStore(load: { self.firstID }, create: { _ in false })
        let beforeLogin = try store.cookie(accountCookie: nil)
        let signedIn = try store.cookie(accountCookie:
            "MUSIC_U=token==;; deviceId=old; NMTID=server-token; Path=/; HttpOnly")
        let afterLogout = try store.cookie(accountCookie: nil)

        XCTAssertEqual(beforeLogin, "deviceId=" + firstID)
        XCTAssertEqual(afterLogout, beforeLogin)
        XCTAssertEqual(signedIn, "MUSIC_U=token==; NMTID=server-token; deviceId=" + firstID)
        XCTAssertTrue(SessionCookie.hasLoginCredential(signedIn))
        XCTAssertFalse(SessionCookie.hasLoginCredential(afterLogout))
    }

    func testOnlyANonemptyMusicULoginCookieCountsAsLoggedIn() {
        let anonymousCookies: [String?] = [nil, "", "deviceId=abc; NMTID=xyz", "MUSIC_A=visitor",
                                           "MUSIC_U=", "MUSIC_U=\"\"", "MUSIC_U=old; MUSIC_U="]
        for cookie in anonymousCookies {
            XCTAssertFalse(SessionCookie.hasLoginCredential(cookie), "Cookie: \(cookie ?? "nil")")
        }
        XCTAssertTrue(SessionCookie.hasLoginCredential("MUSIC_U=token==; deviceId=abc"))
    }
}
