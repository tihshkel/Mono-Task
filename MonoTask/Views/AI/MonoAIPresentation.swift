import SwiftUI
import Observation

@MainActor
@Observable
final class MonoAIRouter {
    static let shared = MonoAIRouter()
    struct Request: Identifiable {
        let id = UUID()
        var folderID: UUID?
        var text = ""
        var fromIsland = false
    }
    var request: Request?
}

struct MonoAIEntryButton: View {
    var title = "Mono AI"
    var folderID: UUID?
    var text = ""
    var onOpen: (() -> Void)?
    @State private var presented = false

    var body: some View {
        Button {
            #if os(macOS)
            onOpen?()
            MonoAIRouter.shared.request = .init(folderID: folderID, text: text)
            #else
            presented = true
            #endif
        } label: {
            Label(title, systemImage: "sparkles").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent).padding(.horizontal, 13).padding(.vertical, 11)
                .background(Theme.Colors.accent.opacity(0.09), in: Capsule())
        }.buttonStyle(SoftPressStyle()).accessibilityIdentifier("mono-ai-open")
            #if os(iOS)
        .fullScreenCover(isPresented: $presented) {
            MonoAIView(initialFolderID: folderID, initialText: text) { presented = false }
        }
            #endif
    }
}

struct MonoAIPresentation: ViewModifier {
    @State private var router = MonoAIRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .disabled(router.request != nil)
            .accessibilityHidden(router.request != nil)
            .overlay {
                if let request = router.request {
                    MonoAIView(
                        initialFolderID: request.folderID, initialText: request.text, fromIsland: request.fromIsland
                    ) {
                        router.request = nil
                    }
                    .id(request.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.08), value: router.request?.id)
            .onChange(of: AuthManager.shared.userID) { _, _ in router.request = nil }
    }
}
