import AppKit
import Foundation

// Mechanical platform export only: retain the generated artwork; resample and apply the macOS icon template.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let catalog = root.appending(path: "MonoTask/Resources/Assets.xcassets")
let fm = FileManager.default

func saveJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

func export(_ source: NSImage, size: Int, mac: Bool, to url: URL) throws {
    let cg = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    if mac {
        let inset = CGFloat(size) * 0.063
        let rect = canvas.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.223, yRadius: rect.height * 0.223)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = CGFloat(size) * 0.015
        shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) * 0.007)
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.addClip()
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        NSColor.white.setFill()
        canvas.fill()
        source.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
let light = NSImage(contentsOf: root.appending(path: "docs/branding/MonoTask-Light.png"))!
let dark = NSImage(contentsOf: root.appending(path: "docs/branding/MonoTask-Dark.png"))!
let primary = catalog.appending(path: "AppIconPalette.appiconset")
try fm.createDirectory(at: primary, withIntermediateDirectories: true)
try export(light, size: 1024, mac: false, to: primary.appending(path: "AppIcon-1024.png"))
try export(dark, size: 1024, mac: false, to: primary.appending(path: "AppIcon-Dark-1024.png"))
var icons: [[String: Any]] = [
    ["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
    [
        "filename": "AppIcon-Dark-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
        "appearances": [["appearance": "luminosity", "value": "dark"]],
    ],
]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try export(light, size: points * scale, mac: true, to: primary.appending(path: filename))
        icons.append(["filename": filename, "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x"])
    }
}
try saveJSON(["images": icons, "info": info], to: primary.appending(path: "Contents.json"))

for (name, image) in [
    ("AppIconLight", light), ("AppIconDark", dark),
    ("AppIconLightPalette", light), ("AppIconDarkPalette", dark),
] {
    let folder = catalog.appending(path: name + ".appiconset")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try export(image, size: 1024, mac: false, to: folder.appending(path: "icon.png"))
    // Explicit in-app selections keep their chosen background in either Home Screen appearance.
    try saveJSON(
        [
            "images": [
                ["filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
                [
                    "filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
                    "appearances": [["appearance": "luminosity", "value": "dark"]],
                ],
            ], "info": info,
        ], to: folder.appending(path: "Contents.json"))
}
let logo = catalog.appending(path: "BrandLogo.imageset")
try fm.createDirectory(at: logo, withIntermediateDirectories: true)
var logoImages: [[String: Any]] = []
for (appearance, image) in [("light", light), ("dark", dark)] {
    for scale in 1...3 {
        let filename = "logo-\(appearance)@\(scale)x.png"
        try export(image, size: 128 * scale, mac: false, to: logo.appending(path: filename))
        var entry: [String: Any] = ["filename": filename, "idiom": "universal", "scale": "\(scale)x"]
        if appearance == "dark" { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
        logoImages.append(entry)
    }
}
try saveJSON(["images": logoImages, "info": info], to: logo.appending(path: "Contents.json"))
for (name, image) in [("BrandDockLight", light), ("BrandDockDark", dark)] {
    let folder = catalog.appending(path: name + ".imageset")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try export(image, size: 1024, mac: true, to: folder.appending(path: "icon.png"))
    try saveJSON(
        ["images": [["filename": "icon.png", "idiom": "universal", "scale": "1x"]], "info": info],
        to: folder.appending(path: "Contents.json"))
}
let mascot = catalog.appending(path: "BrandMascot.imageset")
try fm.createDirectory(at: mascot, withIntermediateDirectories: true)
var mascotImages: [[String: Any]] = []
for appearance in ["Light", "Dark"] {
    let source = NSImage(contentsOf: root.appending(path: "docs/branding/MonoTask-Mascot-\(appearance).png"))!
    for scale in 1...3 {
        let filename = "mascot-\(appearance.lowercased())@\(scale)x.png"
        try export(source, size: 160 * scale, mac: false, to: mascot.appending(path: filename))
        var entry: [String: Any] = ["filename": filename, "idiom": "universal", "scale": "\(scale)x"]
        if appearance == "Dark" { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
        mascotImages.append(entry)
    }
}
try saveJSON(["images": mascotImages, "info": info], to: mascot.appending(path: "Contents.json"))
print("Exported primary, alternate, adaptive logo and macOS Dock icon assets")
