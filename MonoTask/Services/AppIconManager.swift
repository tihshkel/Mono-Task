import SwiftUI
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Observable
final class AppIconManager {
    static let shared = AppIconManager()
    private(set) var errorMessage: String?
    #if os(macOS)
    @ObservationIgnored private var appliedDark: Bool?
    #else
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    #endif

    func apply(preference: String, scheme: ColorScheme) {
        #if os(macOS)
        let dark = preference == "dark" || (preference == "system" && scheme == .dark)
        guard appliedDark != dark, let image = NSImage(named: dark ? "BrandDockDark" : "BrandDockLight") else { return }
        NSApp.applicationIconImage = image
        appliedDark = dark
        #else
        // Versioned names refresh icons cached under the previous artwork, including the default light theme.
        guard UIApplication.shared.applicationState == .active,
            UIApplication.shared.supportsAlternateIcons
        else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshots") { return }
        #endif
        let desired: String? =
            preference == "system" ? nil : preference == "dark" ? "AppIconDarkPalette" : "AppIconLightPalette"
        revision += 1
        let ticket = revision
        let previous = updateTask
        updateTask = Task { @MainActor in
            await previous?.value
            guard ticket == revision, UIApplication.shared.alternateIconName != desired else { return }
            do {
                try await UIApplication.shared.setAlternateIconName(desired)
                errorMessage = nil
            } catch {
                errorMessage = "Не удалось изменить иконку: \(error.localizedDescription)"
            }
        }
        #endif
    }
}

struct AppIconAppearance: ViewModifier {
    let preference: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: preference, initial: true) { _, _ in apply() }
            .onChange(of: scheme) { _, _ in apply() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { apply() } }
    }
    private func apply() { AppIconManager.shared.apply(preference: preference, scheme: scheme) }
}
