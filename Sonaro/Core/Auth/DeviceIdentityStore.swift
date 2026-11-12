import Foundation
import Security
import os

/// One identity for this Mac, independent of the account cookie and logout.
final class DeviceIdentityStore {
    static let shared = DeviceIdentityStore()

    private let cachedIdentity = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let load: () throws -> String?
    private let create: (String) throws -> Bool
    private let generate: () throws -> String

    init(
        load: @escaping () throws -> String? = { try Keychain.read("device.identity") },
        create: @escaping (String) throws -> Bool = { try Keychain.create($0, for: "device.identity") },
        generate: @escaping () throws -> String = DeviceIdentityStore.generateID
    ) {
        self.load = load
        self.create = create
        self.generate = generate
    }

    func deviceID() throws -> String {
        try cachedIdentity.withLock { cached in
            if let cached { return cached }
            // Cache success only: a temporarily locked Keychain can recover,
            // while no unpersisted identity is ever returned to a request.
            if let stored = try load() {
                try Self.validate(stored)
                cached = stored
                return stored
            }
            let candidate = try generate()
            try Self.validate(candidate)
            if try create(candidate) {
                cached = candidate
                return candidate
            }
            // Another app process may have created the item after our read.
            // Reuse its identity rather than replacing it with our candidate.
            guard let stored = try load() else { throw IdentityError.missingStoredIdentity }
            try Self.validate(stored)
            cached = stored
            return stored
        }
    }

    func cookie(accountCookie: String?) throws -> String {
        var fields = SessionCookie.fields(accountCookie)
        fields["deviceId"] = try deviceID()
        return fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: "; ")
    }

    private static func validate(_ value: String) throws {
        let hex = "0123456789abcdefABCDEF"
        guard value.count == 52, value.allSatisfy({ hex.contains($0) }) else {
            throw IdentityError.invalidIdentity
        }
    }

    private static func generateID() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 26)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw IdentityError.randomGenerationFailed }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    private enum IdentityError: LocalizedError {
        case invalidIdentity
        case missingStoredIdentity
        case randomGenerationFailed

        var errorDescription: String? {
            switch self {
            case .invalidIdentity: return "本地设备标识无效"
            case .missingStoredIdentity: return "无法读取已保存的设备标识"
            case .randomGenerationFailed: return "无法生成设备标识"
            }
        }
    }
}
