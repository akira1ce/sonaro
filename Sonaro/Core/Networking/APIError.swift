import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case transport(Error)
    case deviceIdentity(Error)
    /// The backend answers `301 {"code":301,"msg":"需要登录"}` when the supplied
    /// cookie is invalid or expired — it is not a redirect.
    case sessionExpired
    case http(Int, message: String?)
    case decoding(Error)
    /// A logical error surfaced by the API body (`code` != 200).
    case api(code: Int, message: String?)
    /// Song has no playable URL (VIP-only / unavailable / no copyright).
    case noPlayableURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "接口地址无效"
        case .transport(let e): return "网络请求失败：\(e.localizedDescription)"
        case .deviceIdentity(let e): return "设备身份不可用：\(e.localizedDescription)"
        case .sessionExpired: return "登录已过期，请重新登录"
        case .http(let code, let message):
            return message.map { "服务器返回错误（HTTP \(code)）：\($0)" }
                ?? "服务器返回错误（HTTP \(code)）"
        case .decoding: return "数据解析失败"
        case .api(let code, let message): return message ?? "接口错误（\(code)）"
        case .noPlayableURL: return "暂无可播放资源（可能需要会员或无版权）"
        }
    }
}
