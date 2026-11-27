import Foundation
import CommonCrypto

// Protocol reference: NeteaseCloudMusicApiEnhanced (MIT), see THIRD_PARTY_NOTICES.md.
enum EAPI {
    static func encrypt(path: String, json: String) throws -> String {
        guard path.range(of: #"^/api/[A-Za-z0-9/_-]+$"#, options: .regularExpression) != nil else {
            throw APIError.invalidURL
        }
        let digestInput = Data("nobody\(path)use\(json)md5forencrypt".utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = digestInput.withUnsafeBytes { CC_MD5($0.baseAddress, CC_LONG($0.count), &digest) }
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let input = Data("\(path)-36cd479b6b5-\(json)-36cd479b6b5-\(hash)".utf8)
        let key = Data("e82ckenh8dichen8".utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var count = 0
        let capacity = output.count
        let status = key.withUnsafeBytes { keyBytes in
            input.withUnsafeBytes { bytes in
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, nil, bytes.baseAddress, input.count,
                        &output, capacity, &count)
            }
        }
        guard status == kCCSuccess else { throw APIError.api(code: Int(status), message: "请求加密失败") }
        return output.prefix(count).map { String(format: "%02X", $0) }.joined()
    }
}
