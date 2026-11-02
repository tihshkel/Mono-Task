import Foundation
import Observation

@MainActor
@Observable
final class MonoAIKeywordsStore {
    static let shared = MonoAIKeywordsStore()
    private var revision = 0

    private var key: String { "monotask.ai.keywords." + (AuthManager.shared.userID?.uuidString ?? "preview") }

    func customKeywords(for folderID: UUID) -> [String] {
        _ = revision
        return (UserDefaults.standard.dictionary(forKey: key)?[folderID.uuidString] as? [String]) ?? []
    }

    func keywords(for folder: Tag) -> [String] {
        MonoAIKeywords.normalize(
            (MonoAIKeywords.automatic(for: folder.name) + customKeywords(for: folder.id)).joined(separator: ","))
    }

    func set(_ words: [String], for folderID: UUID) {
        var folders = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        folders[folderID.uuidString] = MonoAIKeywords.normalize(words.joined(separator: ","))
        UserDefaults.standard.set(folders, forKey: key)
        revision += 1
    }
}
