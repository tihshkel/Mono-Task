import AppKit
import Foundation
import SwiftUI

private struct InvitationSocialCard: View {
    let logo: NSImage

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 15) {
                    Image(nsImage: logo).resizable().frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 19))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MonoTask").font(.system(size: 31, weight: .semibold)).tracking(-1)
                        Text("Главное — в фокусе.").font(.system(size: 13)).tracking(0)
                            .foregroundStyle(Color(hex: "#BDB2BD"))
                    }
                }
                Spacer().frame(height: 55)
                Text("Всё важное.").foregroundStyle(Color(hex: "#F2EFEB"))
                Text("Теперь вместе.").foregroundStyle(Color(hex: "#D9FF00"))
                Spacer().frame(height: 26)
                Text("Для ваших общих планов.")
                    .font(.system(size: 24)).tracking(-0.3).foregroundStyle(Color(hex: "#BDB2BD"))
                Spacer().frame(height: 54)
                HStack(spacing: 9) {
                    Circle().fill(Color(hex: "#D9FF00")).frame(width: 6, height: 6)
                    Text("ОБЩИЕ ПАПКИ / ЗАДАЧИ / ПРОГРЕСС")
                        .font(.system(size: 11, design: .monospaced)).tracking(1)
                        .foregroundStyle(Color(hex: "#BDB2BD"))
                }
            }
            .font(.system(size: 60, weight: .semibold)).tracking(-2)
            .frame(width: 610, alignment: .leading)

            ZStack {
                Circle().strokeBorder(Color(hex: "#463D45"), lineWidth: 1)
                    .frame(width: 430, height: 340).rotationEffect(.degrees(-25))
                FolderArtwork(tint: Color(hex: "#6B57C8"), icon: "person.2.fill")
                    .frame(width: 400, height: 320).rotationEffect(.degrees(-7)).offset(y: 55)
                VStack(alignment: .leading, spacing: 12) {
                    Text("MONOTASK / ВМЕСТЕ").font(.system(size: 10, design: .monospaced)).tracking(1)
                    Text("Место\nдля вас.").font(.system(size: 40, weight: .semibold)).tracking(-1.5)
                }
                .foregroundStyle(Color(hex: "#322B24"))
                .padding(24).frame(width: 250, alignment: .leading)
                .background(Color(hex: "#F2EFEB"), in: RoundedRectangle(cornerRadius: 17))
                .rotationEffect(.degrees(-12)).offset(x: -12, y: -105)
                HStack(spacing: 9) {
                    Text(":)").font(.system(size: 17, design: .monospaced)).rotationEffect(.degrees(90))
                        .foregroundStyle(Color(hex: "#221F20"))
                        .frame(width: 34, height: 34).background(Color(hex: "#D9FF00"), in: Circle())
                    Text("Вы + мы").font(.system(size: 17, weight: .medium)).tracking(0)
                }
                .padding(12).background(Color(hex: "#353035"), in: RoundedRectangle(cornerRadius: 17))
                .rotationEffect(.degrees(6)).offset(x: 100, y: 190)
            }.frame(width: 400, height: 450)
        }
        .padding(64).frame(width: 1200, height: 630)
        .background(Color(hex: "#221F20"))
        .foregroundStyle(Color(hex: "#F2EFEB"))
        .environment(\.colorScheme, .dark)
    }
}

@main
private struct ExportInvitationAssets {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let root = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let assets = root.appending(path: "docs/join/assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for appearance in ["light", "dark"] {
            let source = root.appending(
                path: "MonoTask/Resources/Assets.xcassets/BrandLogo.imageset/logo-\(appearance)@2x.png")
            try Data(contentsOf: source).write(to: assets.appending(path: "logo-\(appearance)-v2.png"))
        }
        let font = root.appending(path: "MonoTask/Resources/Fonts/JetBrainsMono-Regular.ttf")
        try Data(contentsOf: font).write(to: assets.appending(path: "JetBrainsMono-Regular.ttf"))
        let license = root.appending(path: "MonoTask/Resources/Fonts/JetBrainsMono-OFL.txt")
        try Data(contentsOf: license).write(to: assets.appending(path: "JetBrainsMono-OFL.txt"))
        let logo = NSImage(contentsOf: assets.appending(path: "logo-dark-v2.png"))!
        let renderer = ImageRenderer(content: InvitationSocialCard(logo: logo))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: assets.appending(path: "invitation-v2.png"))
        print("Exported invitation cover (1200 × 630), current logos and local font.")
    }
}
