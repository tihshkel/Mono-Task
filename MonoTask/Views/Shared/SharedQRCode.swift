import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO

enum SharedQRCode {
    /// Four blank modules surround the code; artwork never covers its data or finder patterns.
    static func image(for payload: String) -> CGImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(payload.utf8)
        generator.correctionLevel = "M"
        guard let code = generator.outputImage else { return nil }
        let quietZone = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor.white).cropped(to: quietZone)
        let output = code.composited(over: white).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(output, from: output.extent)
    }

    static func invitation(in image: CGImage) -> String? {
        guard
            let detector = CIDetector(
                ofType: CIDetectorTypeQRCode, context: CIContext(),
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return nil }
        return detector.features(in: CIImage(cgImage: image))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .compactMap(SharedInvite.parseCode).first
    }

    static func invitation(in data: Data) -> String? {
        guard data.count <= 20 * 1024 * 1024,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800,
                ] as CFDictionary)
        else { return nil }
        return invitation(in: image)
    }
}
