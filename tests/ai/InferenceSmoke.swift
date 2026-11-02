import Foundation

@main
struct InferenceSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass a path to the downloaded Gemma GGUF")
        }
        let folders = [
            MonoAIFolder(id: UUID(), name: "Работа", keywords: ["MonoTask", "проект", "дизайн"]),
            MonoAIFolder(id: UUID(), name: "Личное", keywords: ["дом", "покупки", "семья"]),
            MonoAIFolder(id: UUID(), name: "Учёба", keywords: ["учёба"]),
        ]
        var matchedFolders = 0
        for (input, expected) in [
            ("Закончить дизайн проекта MonoTask", 0), ("Купить продукты домой", 1),
            ("Доделать проект по учёбе, срок сдачи завтра в 15:30", 2),
        ] {
            let start = Date()
            let output = try await LocalInference.shared.generate(
                modelURL: URL(fileURLWithPath: CommandLine.arguments[1]),
                prompt: MonoAIProposal.prompt(text: input, folders: folders, preferredID: nil),
                grammar: MonoAIProposal.grammar(folderCount: folders.count))
            let result = try MonoAIProposal.parse(output, folderCount: folders.count)
            FileHandle.standardOutput.write(
                Data("Input: \(input)\nOutput: \(output)\nSeconds: \(Date().timeIntervalSince(start))\n".utf8))
            let route = MonoAIRouting.decide(
                text: input, folders: folders, suggestedIndex: result.folder, preferredID: nil)
            precondition(route.folderIndex == expected && !route.needsConfirmation, "Incorrect final routing")
            if route.folderIndex == expected { matchedFolders += 1 }
            if input.contains("срок") { precondition(MonoAIDeadlineParser.parse(input).date != nil) }
        }
        print("PASS: three structured responses, no Metal assertion")
        print("Final routing: \(matchedFolders)/3 expected folders; explicit study with deadline included.")
    }
}
