import Foundation
import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

/// Platform typealias so feature code never has to branch on UIKit / AppKit.
public typealias PlatformImage = NSImage

/// Cross-platform helpers.
extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

extension PlatformImage {
    /// Raw PNG data, used to build lock-screen artwork.
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Generates a crisp QR code from the login `qrurl`, rendered locally with CoreImage
/// so it scales cleanly on every display instead of using the API's small base64 image.
enum QRCodeRenderer {
    static func image(from string: String, scale: CGFloat = 12) -> PlatformImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

extension String {
    /// Netease image/CDN URLs are served over http; upgrade to https for cleaner transport.
    var httpsUpgraded: String {
        hasPrefix("http://") ? replacingOccurrences(of: "http://", with: "https://") : self
    }

    /// Netease images accept a `?param=WxH` sizing hint — request only what we render.
    func sizedImageURL(_ side: Int) -> URL? {
        URL(string: "\(httpsUpgraded)?param=\(side)y\(side)")
    }
}
