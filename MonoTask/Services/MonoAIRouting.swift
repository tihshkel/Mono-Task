import Foundation

struct MonoAIRoutingDecision: Equatable, Sendable {
    let folderIndex: Int?
    let explanation: String
    let needsConfirmation: Bool
}

enum MonoAIRouting {
    private static let aliases: [[String]] = [
        [
            "учеба", "учебе", "учебу", "учебой", "учебы", "учебный", "учебного", "учебному", "учебным", "учебные",
            "учебную", "study", "studies", "school", "university",
        ],
        [
            "работа", "работе", "работу", "работой", "работы", "рабочий", "рабочую", "рабочего", "рабочие", "work",
            "job", "office",
        ],
        ["личное", "личные", "личного", "личную", "личная", "personal"],
        ["дом", "дома", "домой", "дому", "домашний", "home"],
        ["семья", "семьи", "семье", "семью", "семейный", "family"],
        ["покупка", "покупки", "покупок", "купить", "покупать", "shopping"],
        ["проект", "проекта", "проекту", "проектом", "проекты", "project", "projects"],
        ["отчет", "отчета", "отчету", "отчетом", "отчеты", "report"],
        ["экзамен", "экзамена", "экзамену", "экзамены", "exam"],
        ["лаба", "лабу", "лабы", "лабораторная", "лабораторную", "лабораторной"],
        ["продукты", "продуктов", "продуктами", "groceries"],
        ["клиент", "клиента", "клиенту", "клиентом", "клиенты", "client"],
        ["босс", "босса", "боссу", "boss"],
        ["папка", "папку", "папке", "папки", "папкой", "folder"],
        ["задача", "задачу", "задаче", "задачи", "task", "tasks"],
        ["дело", "дела", "делу"],
        ["список", "списка", "списку", "list"],
    ]
    private static let generic = Set(["проект", "задача", "задачи", "дело", "дела", "список", "папка"])
    private static let hints: [(names: Set<String>, words: Set<String>)] = [
        (
            ["учеба", "школа", "университет"],
            ["экзамен", "лаба", "конспект", "курсовая", "диплом", "зачет", "преподаватель"]
        ),
        (["работа", "офис"], ["клиент", "босс", "отчет", "совещание", "договор", "заказчик"]),
        (["личное", "дом", "семья", "покупка"], ["дом", "семья", "покупка", "продукты", "магазин", "подарок"]),
    ]

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.map { word in
                aliases.first { $0.contains(word) }?.first ?? word
            }
    }

    private static func occurrences(_ phrase: [String], in text: [String]) -> [Int] {
        guard !phrase.isEmpty, phrase.count <= text.count else { return [] }
        return (0...(text.count - phrase.count)).filter { offset in
            Array(text[offset..<(offset + phrase.count)]) == phrase
        }
    }

    private static func negated(at offset: Int, in input: [String]) -> Bool {
        let preceding = Array(input[max(0, offset - 3)..<offset])
        guard let marker = preceding.lastIndex(where: { ["не", "not", "кроме", "except"].contains($0) }) else {
            return false
        }
        return preceding[(marker + 1)...].allSatisfy {
            ["в", "во", "для", "к", "ко", "папка", "список", "а", "the", "in", "to"].contains($0)
        }
    }

    private static func matches(_ phrase: [String], in input: [String]) -> Bool {
        occurrences(phrase, in: input).contains { !negated(at: $0, in: input) }
    }

    static func decide(text: String, folders: [MonoAIFolder], suggestedIndex: Int, preferredID: UUID?)
        -> MonoAIRoutingDecision
    {
        let input = words(text)
        let exclusions = Set(
            folders.indices.filter { index in
                occurrences(words(folders[index].name), in: input).contains { negated(at: $0, in: input) }
            })
        let explicit = folders.indices.filter { index in
            let name = words(folders[index].name)
            return !Set(name).isSubset(of: generic) && matches(name, in: input)
        }
        let withoutFolder =
            matches(["без", "папка"], in: input)
            || matches(["no", "папка"], in: input) || matches(["без", "список"], in: input)
            || input.contains("unfiled")
        if withoutFolder {
            let namedDestination = input.indices.contains { index in
                input[index] == "папка" && index > 0 && ["в", "во", "to", "in"].contains(input[index - 1])
                    && !negated(at: index, in: input)
            }
            guard !namedDestination || explicit.isEmpty else {
                return .init(
                    folderIndex: nil, explanation: "Указаны и папка, и «без папки». Выберите один вариант.",
                    needsConfirmation: true)
            }
            return .init(
                folderIndex: nil, explanation: "Вы попросили оставить задачу без папки.", needsConfirmation: false)
        }
        var directed: Set<Int> = []
        var unknownDestination = false
        for marker in input.indices where input[marker] == "папка" && marker + 1 < input.count {
            guard marker == 0 || ["в", "во", "to", "in"].contains(input[marker - 1]) else { continue }
            let start = ["по", "для", "the"].contains(input[marker + 1]) ? marker + 2 : marker + 1
            guard start < input.count, !negated(at: start, in: input) else { continue }
            let destination = Array(input[start...])
            let candidates = folders.indices.filter { index in
                occurrences(words(folders[index].name), in: destination).contains(0)
            }
            if candidates.isEmpty { unknownDestination = true }
            directed.formUnion(candidates)
        }
        if unknownDestination {
            return .init(
                folderIndex: nil,
                explanation: "Не нашёл названную папку. Выберите существующую или создайте её отдельно.",
                needsConfirmation: true)
        }
        if folders.isEmpty {
            return .init(
                folderIndex: nil, explanation: "Папок пока нет. Задача будет сохранена без папки.",
                needsConfirmation: false)
        }
        if directed.count == 1, let index = directed.first {
            return .init(
                folderIndex: index, explanation: "Вы выбрали папку «\(folders[index].name)».", needsConfirmation: false)
        }
        if directed.count > 1 {
            return .init(
                folderIndex: nil, explanation: "Названы разные папки назначения. Выберите одну.",
                needsConfirmation: true)
        }
        if explicit.count == 1, let index = explicit.first {
            return .init(
                folderIndex: index, explanation: "Вы назвали папку «\(folders[index].name)».", needsConfirmation: false)
        }
        if explicit.count > 1 {
            return .init(
                folderIndex: nil, explanation: "Вы упомянули несколько папок. Выберите нужную.", needsConfirmation: true
            )
        }
        let scores = folders.enumerated().map { index, folder in
            guard !exclusions.contains(index) else { return (index: index, score: 0) }
            let keywordScore =
                Set(folder.keywords.map { words($0) }).map { phrase in
                    guard !Set(phrase).isSubset(of: generic), matches(phrase, in: input) else { return 0 }
                    return 40 + min(phrase.count, 4) * 10
                }.max() ?? 0
            let names = Set(words(folder.name))
            let semantic = hints.filter { !$0.names.isDisjoint(with: names) }.reduce(0) { total, hint in
                total + hint.words.filter { matches([$0], in: input) }.count * 12
            }
            return (index: index, score: keywordScore + semantic)
        }
        let best = scores.map(\.score).max() ?? 0
        let bestMatches = scores.filter { $0.score == best && best > 0 }
        if bestMatches.count == 1, let index = bestMatches.first?.index {
            return .init(
                folderIndex: index, explanation: "Совпадение с темами и хештегами папки.", needsConfirmation: false)
        }
        if bestMatches.count > 1 {
            return .init(
                folderIndex: nil, explanation: "Подходят несколько папок. Уточните, куда добавить задачу.",
                needsConfirmation: true)
        }
        if let preferredID, let index = folders.firstIndex(where: { $0.id == preferredID }), !exclusions.contains(index)
        {
            return .init(folderIndex: index, explanation: "Используется текущая папка.", needsConfirmation: false)
        }
        if folders.indices.contains(suggestedIndex), !exclusions.contains(suggestedIndex) {
            return .init(
                folderIndex: suggestedIndex,
                explanation: "Это предположение модели. Подтвердите папку или выберите другую.", needsConfirmation: true
            )
        }
        return .init(
            folderIndex: nil, explanation: "Папку определить не удалось. Можно оставить задачу без папки.",
            needsConfirmation: true)
    }

    static func explicitPriority(in text: String) -> Bool {
        let input = words(text)
        let phrase = input.joined(separator: " ")
        if phrase.range(
            of:
                #"\b(?:без\s+(?:высокого\s+)?приоритета|не\s+(?:(?:ставь|ставить|делай|делать)\s+)?(?:высокий\s+)?приоритет|no\s+(?:high\s+)?priority|without\s+priority|not\s+high\s+priority)\b"#,
            options: .regularExpression) != nil
        {
            return false
        }
        if matches(["без", "приоритета"], in: input) || matches(["low", "priority"], in: input)
            || matches(["normal", "priority"], in: input) || matches(["not", "urgent"], in: input)
        {
            return false
        }
        return ["срочно", "срочная", "срочный", "приоритет", "важно", "urgent", "asap"]
            .contains { matches([$0], in: input) }
    }
}
