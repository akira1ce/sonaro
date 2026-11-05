import SwiftUI

/// Full-screen QR login. Mirrors the Netease app flow: show a QR code, poll for
/// scan/confirm, and hand off to the session once authorized.
struct QRLoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var fontManager: FontManager

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 28) {
                Spacer(minLength: 20)

                // Brand mark
                VStack(spacing: 14) {
                    BrandMark(size: 92)
                    Text("Sonaro")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("扫码登录")
                        .font(fontManager.font(.subheadline))
                        .foregroundStyle(.secondary)
                }

                qrCard

                statusHint

                Spacer(minLength: 20)
            }
            .padding()
            .frame(maxWidth: 460)
        }
        .task { await auth.startQRLogin() }
        .onDisappear { auth.stopPolling() }
    }

    // MARK: QR card

    private var qrCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)

            if let image = auth.qrImage {
                Image(platformImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .blur(radius: overlay == nil ? 0 : 6)
            } else {
                ProgressView()
            }

            if let overlay {
                VStack(spacing: 10) {
                    Image(systemName: overlay.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(overlay.tint)
                    if let action = overlay.action {
                        Button("刷新二维码") { Task { await action() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .padding(20)
                .frame(width: 200, height: 200)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private struct Overlay {
        let icon: String
        let tint: Color
        var action: (() async -> Void)? = nil
    }

    private var overlay: Overlay? {
        switch auth.qrPhase {
        case .scanned:
            return Overlay(icon: "checkmark.circle.fill", tint: .green)
        case .succeeded:
            return Overlay(icon: "checkmark.seal.fill", tint: .green)
        case .expired:
            return Overlay(icon: "arrow.clockwise.circle.fill", tint: Theme.accent,
                           action: { await auth.startQRLogin() })
        case .failed:
            return Overlay(icon: "exclamationmark.triangle.fill", tint: .orange,
                           action: { await auth.startQRLogin() })
        default:
            return nil
        }
    }

    // MARK: Status text

    private var statusHint: some View {
        Group {
            switch auth.qrPhase {
            case .idle, .loading:
                Label("正在生成二维码…", systemImage: "qrcode")
            case .waiting:
                Label("打开音乐 App，扫一扫登录", systemImage: "qrcode.viewfinder")
            case .scanned:
                Label("扫描成功，请在手机上确认", systemImage: "iphone.gen3")
            case .expired:
                Label("二维码已过期，请点击刷新", systemImage: "clock.arrow.circlepath")
            case .succeeded:
                Label("登录成功", systemImage: "checkmark.circle.fill")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
            }
        }
        .font(fontManager.font(.subheadline))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}
