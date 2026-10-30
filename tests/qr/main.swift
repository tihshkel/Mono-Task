import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

var checks = 0
@MainActor
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
let code = "0123456789abcdef0123456789abcdef"
let invite = SharedInvite(code: code, expiresAt: .now.addingTimeInterval(72 * 3600))
let qr = SharedQRCode.image(for: invite.url.absoluteString)!
check(SharedQRCode.invitation(in: qr) == code, "Generated invitation QR is readable by the system detector")
let legacy = SharedQRCode.image(for: "com.monotask.ios://join?code=\(code)")!
check(SharedQRCode.invitation(in: legacy) == code, "Existing app links also scan")
let unrelated = SharedQRCode.image(for: "https://evil.test/join/#\(code)")!
check(SharedQRCode.invitation(in: unrelated) == nil, "Other services cannot be treated as invitations")
let truncated = SharedQRCode.image(for: "https://egoar777.github.io/MonoTask/join/#short")!
check(SharedQRCode.invitation(in: truncated) == nil, "A damaged invitation is rejected before joining")

for (type, options) in [
    (UTType.png, [:] as [CFString: Any]),
    (UTType.jpeg, [kCGImageDestinationLossyCompressionQuality: 0.7] as [CFString: Any]),
] {
    let bytes = NSMutableData()
    let output = CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, qr, options as CFDictionary)
    check(CGImageDestinationFinalize(output), "Test image is encoded")
    check(SharedQRCode.invitation(in: bytes as Data) == code, "An invitation survives image export and import")
}

let rotated = CGContext(
    data: nil, width: qr.height, height: qr.width, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
rotated.translateBy(x: CGFloat(qr.height), y: 0)
rotated.rotate(by: .pi / 2)
rotated.draw(qr, in: CGRect(x: 0, y: 0, width: qr.width, height: qr.height))
check(SharedQRCode.invitation(in: rotated.makeImage()!) == code, "A rotated invitation scans")
check(SharedQRCode.invitation(in: Data("not an image".utf8)) == nil, "Unreadable files do not crash the importer")
check(
    SharedQRCode.invitation(in: Data(repeating: 0, count: 20 * 1024 * 1024 + 1)) == nil, "Oversized files are rejected")
print("Passed \(checks) QR generation and recognition checks")
