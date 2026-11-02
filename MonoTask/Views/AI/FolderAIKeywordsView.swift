import SwiftUI

struct FolderAIKeywordsView: View {
    let tag: Tag
    @State private var store = MonoAIKeywordsStore.shared
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Button {
            draft = store.customKeywords(for: tag.id).joined(separator: ", ")
            editing = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                Text(
                    store.keywords(for: tag).map { "#" + $0 }.joined(separator: "  ")
                )
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.system(size: 10))
            }.font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                .padding(12).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("folder-ai-keywords")
            .sheet(isPresented: $editing) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Mono AI · \(tag.name)").font(.title2.bold())
                    Text(MonoAIKeywords.automatic(for: tag.name).map { "#" + $0 }.joined(separator: "  "))
                        .font(.subheadline).foregroundStyle(Theme.Colors.accent)
                    Text(
                        "Хештеги из названия добавляются автоматически. Ниже можно указать свои темы и проекты через запятую. Дополнения хранятся на этом устройстве."
                    )
                    .font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                    TextField("работа, MonoTask, дизайн", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...5).accessibilityIdentifier(
                            "folder-ai-keywords-input")
                    HStack {
                        Button("Отмена") { editing = false }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Сохранить") {
                            store.set(MonoAIKeywords.normalize(draft), for: tag.id)
                            editing = false
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(28).background(Theme.Colors.background)
                    #if os(macOS)
                .frame(width: 460)
                    #else
                .presentationDetents([.medium, .large])
                    #endif
            }
    }
}
