import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif
enum Theme {
    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "monotask_appearance") ?? "light" {
        case "dark": return .dark
        case "system": return nil
        default: return .light
        }
    }

    private static func adaptive(_ light: String, _ dark: String) -> Color {
        #if os(macOS)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
                return NSColor(
                    srgbRed: Double((value >> 16) & 255) / 255,
                    green: Double((value >> 8) & 255) / 255,
                    blue: Double(value & 255) / 255, alpha: 1)
            })
        #else
        return Color(
            uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
                return UIColor(
                    red: Double((value >> 16) & 255) / 255,
                    green: Double((value >> 8) & 255) / 255,
                    blue: Double(value & 255) / 255, alpha: 1)
            })
        #endif
    }
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Colors
    enum Colors {
        // Surfaces, darkest to lightest
        static let sunGlare = Color(hex: "#D9FF00")
        static let exuberantOrange = Color(hex: "#FF5429")
        static let blueViolet = Color(hex: "#6B57C8")
        static let cloudDancer = Color(hex: "#F2EFEB")
        static let darkestHour = Color(hex: "#221F20")
        static let background = adaptive("#F2EFEB", "#221F20")
        static let sidebar = adaptive("#EAE5E1", "#282426")
        static let surface = adaptive("#FCFAF7", "#2C282C")
        static let surfaceElevated = adaptive("#FFFDFA", "#353035")
        static let surfaceInteractive = adaptive("#E9E2EF", "#433A48")
        static let tabBarBackground = background

        // Translucent fills for chips and controls on any surface
        static let fill = adaptive("#EDE7E3", "#363035")
        static let fillStrong = adaptive("#E2DAD7", "#463D45")

        // Rules
        static let hairline = adaptive("#E6DFDA", "#3E363D")
        static let ruleStrong = adaptive("#D1C7CD", "#5C505C")
        static let border = adaptive("#DBD1D7", "#504550")
        static let borderSubtle = adaptive("#E9E1DE", "#3B333B")

        // Text
        static let textPrimary = adaptive("#221F20", "#F2EFEB")
        static let textSecondary = adaptive("#746B74", "#BDB2BD")
        static let textMuted = adaptive("#827783", "#A799A7")
        static let textTertiary = textMuted
        // Violet keeps small text readable on cream; lime lights up dark surfaces.
        static let accent = adaptive("#6550B8", "#D9FF00")
        static let primary = accent
        static let primaryMuted = accent.opacity(0.14)
        static let onAccent = adaptive("#FCFAF7", "#221F20")
        static let inverse = accent
        static let onInverse = onAccent
        static let priority = adaptive("#B83A1B", "#FF7959")
        static let info = adaptive("#6550B8", "#B7A4FF")

        static let success = accent
        static let accentGreen = accent
        static let successMuted = accent.opacity(0.14)

        static let warning = priority
        static let warningMuted = warning.opacity(0.14)

        static let danger = adaptive("#BD341C", "#FF8466")
        static let dangerMuted = danger.opacity(0.14)
        static let tagColorOptions: [(hex: String, name: String)] = [
            ("#FF5429", "Ярко-оранжевый"),
            ("#6B57C8", "Фиолетовый"),
            ("#D9FF00", "Лаймовый"),
            ("#B397ED", "Лавандовый"),
            ("#D95D37", "Терракотовый"),
            ("#946BC9", "Орхидея"),
            ("#A7BD19", "Оливковый"),
            ("#CB8575", "Пыльная роза"),
            ("#E84B5C", "Малиновый"),
            ("#E56A9B", "Розовый"),
            ("#DA64C7", "Фуксия"),
            ("#5C76DB", "Индиго"),
            ("#3A8DDE", "Синий"),
            ("#3EB7E0", "Голубой"),
            ("#32BDB0", "Бирюзовый"),
            ("#2D9B83", "Изумрудный"),
            ("#47A96A", "Зелёный"),
            ("#87BF69", "Шалфейный"),
            ("#E4BB39", "Золотистый"),
            ("#F29438", "Абрикосовый"),
            ("#A77653", "Карамельный"),
            ("#BB9A7A", "Песочный"),
            ("#7B91A5", "Серо-голубой"),
            ("#8C8F97", "Графитовый"),
        ]
        static let tagColors = tagColorOptions.map(\.hex)
        // Legacy colours stay compatible with existing databases.
        private static let previousTagPalettes: [[String]] = [
            ["#8BA9D7", "#B4A0D7", "#8CB8A5", "#E1B86C", "#D3988A", "#D8A9C0", "#9DA9CD", "#85B8BD"],
            ["#5AA9FF", "#B48CFF", "#3DDC97", "#FFB547", "#FF6B5B", "#FF8AC6", "#7C83FF", "#4FD8E8"],
            ["#0A84FF", "#BF5AF2", "#30D158", "#FF9F0A", "#FF453A", "#FF375F", "#5E5CE6", "#40C8E0"],
            ["#2F5DA8", "#7A4FB5", "#3F8F5A", "#D98A1E", "#D2452B", "#C9577F", "#4B57C2", "#2A8C8C"],
        ]
        // Keep stored category colours legible against dark surfaces.
        static func tagColor(_ hex: String) -> Color {
            Color(hex: normalizedTagHex(hex))
        }
        static func normalizedTagHex(_ hex: String) -> String {
            if let current = tagColors.first(where: { $0.caseInsensitiveCompare(hex) == .orderedSame }) {
                return current
            }
            if ["#95B7A4", "#96BEAB"].contains(where: { $0.caseInsensitiveCompare(hex) == .orderedSame }) {
                return "#D9FF00"
            }
            if hex.caseInsensitiveCompare("#6366F1") == .orderedSame { return "#6B57C8" }
            for palette in previousTagPalettes {
                if let index = palette.firstIndex(where: { $0.caseInsensitiveCompare(hex) == .orderedSame }) {
                    return tagColors[index]
                }
            }
            return hex
        }
    }

    // MARK: - Typography
    enum Typography {
        static let display = Font.system(size: 32, weight: .semibold)
        static let displayLarge = Font.system(size: 38, weight: .semibold)
        static let displayTracking: CGFloat = -1.2
        static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
        static let editorTitle = Font.system(size: 24, weight: .semibold)
        static let title = Font.system(size: 20, weight: .semibold)
        static let titleTracking: CGFloat = -0.4
        static let body = Font.system(size: 16)
        static let bodyTracking: CGFloat = -0.2
        static let callout = Font.system(size: 14)
        static let caption = Font.system(size: 12)
        static let section = Font.system(size: 12, weight: .medium)
        static let eyebrow = Font.system(size: 10, weight: .medium)
        static let eyebrowTracking: CGFloat = 1.1
        static let subtitle = Font.system(size: 12)
        static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let screenPadding: CGFloat = 20
        static let touchTargetMin: CGFloat = 44
    }

    // MARK: - Corner Radius
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let card: CGFloat = 22
        static let xl: CGFloat = 18
        static let capturePill: CGFloat = 18
        static let sheet: CGFloat = 26
        static let full: CGFloat = 9999
    }
    typealias CornerRadius = Radius

    // MARK: - Animation
    enum Motion {
        static let standard = Animation.easeInOut(duration: 0.28)
        static let quick = Animation.easeInOut(duration: 0.18)
    }

    enum AnimationDuration {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
    }
}

// MARK: - View Modifiers

struct MonoTaskCardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.lg
    var elevated: Bool = false
    var cornerRadius: CGFloat = Theme.Radius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(elevated ? Theme.Colors.surfaceElevated : Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.Colors.hairline, lineWidth: 1)
            )
    }
}

struct MonoTaskBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.background.ignoresSafeArea())
            .preferredColorScheme(Theme.colorScheme)
    }
}

extension View {
    func monoTaskCard(
        padding: CGFloat = Theme.Spacing.lg,
        elevated: Bool = false,
        cornerRadius: CGFloat = Theme.Radius.card
    ) -> some View {
        modifier(MonoTaskCardModifier(padding: padding, elevated: elevated, cornerRadius: cornerRadius))
    }

    func monoTaskBackground() -> some View {
        modifier(MonoTaskBackgroundModifier())
    }
}

private struct MonoScrollEdgeModifier: ViewModifier {
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, value in
                offset = value
            }
            .overlay {
                GeometryReader { geometry in
                    let top = geometry.safeAreaInsets.top
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(
                                        color: Theme.Colors.background.opacity(reduceTransparency ? 1 : 0.96),
                                        location: 0),
                                    .init(color: Theme.Colors.background.opacity(0.88), location: 0.34),
                                    .init(color: Theme.Colors.background.opacity(0.5), location: 0.68),
                                    .init(color: Theme.Colors.background.opacity(0), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: top + 64)
                        .offset(y: -top)
                        .opacity(min(1, offset / 20))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

extension View {
    func monoScrollEdge() -> some View { modifier(MonoScrollEdgeModifier()) }
}
