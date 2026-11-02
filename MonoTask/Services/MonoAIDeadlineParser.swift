import Foundation

struct MonoAIDeadline: Equatable, Sendable {
    var date: Date?
    var suggestedDate: Date?
    var clarification: String?
}

enum MonoAIDeadlineParser {
    private struct Match {
        let values: [String]
        let range: NSRange
    }

    private struct Word {
        let value: String
        let range: NSRange
    }

    private struct Clock: Hashable {
        let hour: Int
        let minute: Int
        let ambiguous: Bool
    }

    private static let numbers: [String: Int] = [
        "ноль": 0, "нуль": 0, "час": 1, "один": 1, "одна": 1, "два": 2, "две": 2,
        "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
        "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14,
        "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
        "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50,
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
    ]
    private static let months = [
        ["января", "январь", "january", "jan"], ["февраля", "февраль", "february", "feb"],
        ["марта", "март", "march", "mar"], ["апреля", "апрель", "april", "apr"],
        ["мая", "май", "may"], ["июня", "июнь", "june", "jun"],
        ["июля", "июль", "july", "jul"], ["августа", "август", "august", "aug"],
        ["сентября", "сентябрь", "september", "sep"], ["октября", "октябрь", "october", "oct"],
        ["ноября", "ноябрь", "november", "nov"], ["декабря", "декабрь", "december", "dec"],
    ]
    private static let weekdays = [
        ["воскресенье", "воскресенья", "sunday"], ["понедельник", "понедельника", "monday"],
        ["вторник", "вторника", "tuesday"], ["среда", "среду", "среды", "wednesday"],
        ["четверг", "четверга", "thursday"], ["пятница", "пятницу", "пятницы", "friday"],
        ["суббота", "субботу", "субботы", "saturday"],
    ]

    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            Match(
                values: (0..<match.numberOfRanges).map { index in
                    Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
                }, range: match.range)
        }
    }

    private static func number(_ word: String) -> Int? { Int(word) ?? numbers[word] }

    private static func number(_ words: ArraySlice<String>) -> Int? {
        guard let first = words.first, let initial = number(first), words.count <= 2 else { return nil }
        if words.count == 1 { return initial }
        guard initial >= 20, initial.isMultiple(of: 10), let last = words.last,
            let units = number(last), (1...9).contains(units)
        else { return nil }
        return initial + units
    }

    private static func negated(_ range: NSRange, in text: String) -> Bool {
        let prefix = (text as NSString).substring(to: range.location)
        let clause = prefix.components(separatedBy: CharacterSet(charactersIn: ",;.!?\n")).last ?? ""
        let preceding = Array(clause.split(whereSeparator: { $0.isWhitespace }).map(String.init).suffix(3))
        guard let marker = preceding.lastIndex(where: { ["не", "not", "кроме", "except"].contains($0) }) else {
            return false
        }
        return preceding[(marker + 1)...].allSatisfy {
            ["в", "к", "до", "на", "at", "on", "by", "until"].contains($0)
        }
    }

    static func parse(_ input: String, now: Date = .now, calendar inputCalendar: Calendar = .current) -> MonoAIDeadline
    {
        let text = input.lowercased().replacingOccurrences(of: "ё", with: "е")
        if !matches(#"\b(?:без\s+(?:срока|дедлайна|даты)|срок\s+не\s+нужен|no\s+(?:deadline|due\s+date))\b"#, in: text)
            .isEmpty
        {
            return .init()
        }
        var calendar = inputCalendar
        var timezoneRanges: [NSRange] = []
        var explicitOffsets = Set<Int>()
        for match in matches(#"\b(?:utc|gmt)\s*([+-])\s*(\d{1,2})(?::(\d{2}))?\b"#, in: text) {
            guard let hours = Int(match.values[2]), hours <= 14,
                let minutes = Int(match.values[3].isEmpty ? "0" : match.values[3]), minutes < 60,
                hours < 14 || minutes == 0,
                let timezone = TimeZone(
                    secondsFromGMT: (match.values[1] == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
            else { return .init(clarification: "Уточните часовой пояс и время сдачи.") }
            calendar.timeZone = timezone
            timezoneRanges.append(match.range)
            explicitOffsets.insert(timezone.secondsFromGMT(for: now))
        }
        if !matches(#"\b(?:мск|по\s+москве|по\s+московскому\s+времени)\b"#, in: text).isEmpty,
            let timezone = TimeZone(identifier: "Europe/Moscow")
        {
            calendar.timeZone = timezone
            explicitOffsets.insert(timezone.secondsFromGMT(for: now))
        }
        if explicitOffsets.count > 1 {
            return .init(clarification: "Указаны разные часовые пояса. Уточните один часовой пояс и срок.")
        }
        if timezoneRanges.isEmpty && !matches(#"\b(?:utc|gmt)\b"#, in: text).isEmpty {
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        }
        let today = calendar.startOfDay(for: now)
        let words = matches(#"[\p{L}]+|\d+"#, in: text).map { Word(value: $0.values[0], range: $0.range) }
        var days: [Date] = []
        var dateRanges: [NSRange] = []
        var invalidDay = false

        func addDay(_ date: Date?, match: Match) {
            guard !dateRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                !negated(match.range, in: text)
            else { return }
            dateRanges.append(match.range)
            if let date { days.append(date) } else { invalidDay = true }
        }

        for (pattern, offset) in [
            (#"\b(?:послезавтра|day\s+after\s+tomorrow)\b"#, 2),
            (#"\b(?:завтра|tomorrow)\b"#, 1), (#"\b(?:сегодня|today|tonight)\b"#, 0),
        ] {
            for match in matches(pattern, in: text) {
                addDay(calendar.date(byAdding: .day, value: offset, to: today), match: match)
            }
        }
        let numeral = "(?:\\d{1,3}|" + numbers.keys.sorted { $0.count > $1.count }.joined(separator: "|") + ")"
        for match in matches(
            #"\b(?:через|in)\s+("# + numeral + #"(?:\s+"# + numeral + #")?)\s+(?:день|дня|дней|days?)\b"#, in: text)
        {
            let count = number(match.values[1].split(separator: " ").map(String.init)[...])
            addDay(count.flatMap { calendar.date(byAdding: .day, value: $0, to: today) }, match: match)
        }
        for match in matches(#"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#, in: text) {
            addDay(
                strictDay(
                    year: Int(match.values[1]) ?? 0, month: Int(match.values[2]) ?? 0, day: Int(match.values[3]) ?? 0,
                    calendar: calendar), match: match)
        }
        for match in matches(#"(?<![\d.])(\d{1,2})[./](\d{1,2})(?:[./](\d{4}))?(?![\d.])"#, in: text) {
            let prefix = (text as NSString).substring(to: match.range.location)
            let preceding = prefix.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            if ["версия", "версии", "version", "v"].contains(preceding) { dateRanges.append(match.range); continue }
            if !matches(#"(?:\bв|\bat|\bк)\s*$"#, in: prefix).isEmpty { continue }
            if match.values[3].isEmpty && match.values[0].contains("/") && match.values[1].count == 1
                && match.values[2].count == 1
            {
                if matches(#"\b(?:срок|дедлайн|до|к|на|due|by|on)\b"#, in: prefix).isEmpty {
                    dateRanges.append(match.range); continue
                }
            }
            let year = Int(match.values[3]) ?? calendar.component(.year, from: now)
            let candidate = futureDay(
                year: year, month: Int(match.values[2]) ?? 0, day: Int(match.values[1]) ?? 0,
                allowNextYear: match.values[3].isEmpty, today: today, calendar: calendar)
            addDay(candidate, match: match)
        }
        let monthNames = months.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
        for match in matches(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthNames + #")(?:\s+(\d{4}))?\b"#, in: text) {
            let month = (months.firstIndex(where: { $0.contains(match.values[2]) }) ?? -1) + 1
            let year = Int(match.values[3]) ?? calendar.component(.year, from: now)
            addDay(
                futureDay(
                    year: year, month: month, day: Int(match.values[1]) ?? 0, allowNextYear: match.values[3].isEmpty,
                    today: today, calendar: calendar), match: match)
        }
        for match in matches(#"\b("# + monthNames + #")\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#, in: text) {
            let month = (months.firstIndex(where: { $0.contains(match.values[1]) }) ?? -1) + 1
            let year = Int(match.values[3]) ?? calendar.component(.year, from: now)
            addDay(
                futureDay(
                    year: year, month: month, day: Int(match.values[2]) ?? 0, allowNextYear: match.values[3].isEmpty,
                    today: today, calendar: calendar), match: match)
        }
        for (index, names) in weekdays.enumerated() {
            for match in matches(#"\b(?:"# + names.joined(separator: "|") + #")\b"#, in: text) {
                let offset = (index + 1 - calendar.component(.weekday, from: today) + 7) % 7
                let prefix = (text as NSString).substring(to: match.range.location)
                let nextWeek = !matches(#"\b(?:следующ\p{L}*|next)\s*$"#, in: prefix).isEmpty
                if nextWeek {
                    guard let week = calendar.dateInterval(of: .weekOfYear, for: today),
                        let nextStart = calendar.date(byAdding: .weekOfYear, value: 1, to: week.start)
                    else { addDay(nil, match: match); continue }
                    let nextOffset = (index + 1 - calendar.component(.weekday, from: nextStart) + 7) % 7
                    addDay(calendar.date(byAdding: .day, value: nextOffset, to: nextStart), match: match)
                } else {
                    addDay(calendar.date(byAdding: .day, value: offset, to: today), match: match)
                }
            }
        }
        if invalidDay { return .init(clarification: "Такой даты нет в календаре. Уточните срок.") }
        let uniqueDays = Set(days)
        if uniqueDays.count > 1 {
            return .init(clarification: "Вы назвали несколько дней. Уточните одну дату и время сдачи.")
        }
        let day = uniqueDays.first
        if let relativeDuration = duration(in: text, now: now, calendar: calendar) {
            if day != nil {
                return .init(
                    suggestedDate: day, clarification: "Указаны и дата, и относительный срок. Уточните один срок.")
            }
            return relativeDuration
        }

        var clocks: [Clock] = []
        var clockRanges: [NSRange] = []
        for match in matches(#"(?<!\d)(\d{1,2})[:.](\d{2})\s*(am|pm|утра|дня|вечера|ночи)?\b"#, in: text) {
            guard !dateRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                !timezoneRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                !negated(match.range, in: text)
            else { continue }
            clockRanges.append(match.range)
            clocks.append(
                clock(
                    hour: Int(match.values[1]) ?? -1, minute: Int(match.values[2]) ?? -1, part: match.values[3],
                    ambiguous: false))
        }
        for (index, word) in words.enumerated()
        where ["в", "к", "до", "at", "by"].contains(word.value) && index + 1 < words.count {
            let next = words[index + 1]
            guard !clockRanges.contains(where: { NSIntersectionRange($0, next.range).length > 0 }),
                !dateRanges.contains(where: { NSIntersectionRange($0, next.range).length > 0 }),
                !negated(word.range, in: text)
            else { continue }
            if ["полдень", "noon", "полночь", "midnight"].contains(next.value) {
                clocks.append(
                    .init(hour: ["полдень", "noon"].contains(next.value) ? 12 : 0, minute: 0, ambiguous: false))
                continue
            }
            guard let first = number(next.value) else { continue }
            var cursor = index + 2
            var hour = first
            if first == 20, cursor < words.count, let unit = number(words[cursor].value), (1...3).contains(unit) {
                hour += unit; cursor += 1
            }
            if cursor < words.count && ["час", "часа", "часов", "hour", "hours"].contains(words[cursor].value) {
                cursor += 1
            }
            var minute = 0
            if cursor < words.count, let firstMinute = number(words[cursor].value) {
                minute = firstMinute; cursor += 1
                if firstMinute >= 20, firstMinute.isMultiple(of: 10), cursor < words.count,
                    let unit = number(words[cursor].value), (1...9).contains(unit)
                {
                    minute += unit; cursor += 1
                }
            }
            if cursor < words.count
                && ["минута", "минуту", "минуты", "минут", "minute", "minutes"].contains(words[cursor].value)
            {
                cursor += 1
            }
            let part = cursor < words.count ? words[cursor].value : ""
            if cursor < words.count
                && (months.flatMap { $0 }.contains(part) || ["день", "дня", "дней", "day", "days"].contains(part))
            {
                if part != "дня" || hour > 12 { continue }
            }
            if cursor < words.count && ["или", "or"].contains(part), cursor + 1 < words.count,
                number(words[cursor + 1].value) != nil
            {
                return .init(
                    suggestedDate: day, clarification: "Вы назвали несколько вариантов времени. Выберите один.")
            }
            let isTwentyFourHour = next.value.hasPrefix("0") && next.value.count > 1
            clocks.append(
                clock(hour: hour, minute: minute, part: part, ambiguous: (1...12).contains(hour) && !isTwentyFourHour))
        }
        let uniqueClocks = Set(clocks)
        if uniqueClocks.count > 1 {
            return .init(suggestedDate: day, clarification: "Вы назвали несколько вариантов времени. Выберите один.")
        }
        let requested =
            day != nil || !clocks.isEmpty
            || !matches(
                #"\b(?:срок|дедлайн|сдачи|deadline|due|утром|вечером|ночью|недел\p{L}*|месяц\p{L}*)\b"#, in: text
            ).isEmpty
        guard requested else { return .init() }
        guard let day else { return .init(clarification: "На какой день поставить срок? Выберите дату и время.") }
        guard let clock = uniqueClocks.first else {
            return .init(suggestedDate: day, clarification: "День понятен. Уточните точное время сдачи.")
        }
        guard (0...23).contains(clock.hour), (0...59).contains(clock.minute) else {
            return .init(suggestedDate: day, clarification: "Не удалось понять время. Укажите часы и минуты.")
        }
        guard !clock.ambiguous else {
            return .init(suggestedDate: day, clarification: "Уточните время суток: например, в три дня или в 15:00.")
        }
        guard let date = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day), date > now
        else {
            return .init(suggestedDate: day, clarification: "Этот срок уже прошёл. Выберите будущую дату и время.")
        }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let requestedDay = calendar.dateComponents([.year, .month, .day], from: day)
        guard parts.year == requestedDay.year, parts.month == requestedDay.month, parts.day == requestedDay.day,
            parts.hour == clock.hour, parts.minute == clock.minute
        else {
            return .init(
                suggestedDate: day, clarification: "Это время недоступно в вашем часовом поясе. Выберите другое.")
        }
        return .init(date: date, suggestedDate: date)
    }

    private static func clock(hour: Int, minute: Int, part: String, ambiguous: Bool) -> Clock {
        if ["утра", "утром", "ночи", "ночью", "am"].contains(part), (1...12).contains(hour) {
            return .init(hour: hour == 12 ? 0 : hour, minute: minute, ambiguous: false)
        }
        if ["дня", "днем", "вечера", "вечером", "pm"].contains(part), (1...12).contains(hour) {
            return .init(hour: hour == 12 ? 12 : hour + 12, minute: minute, ambiguous: false)
        }
        return .init(hour: hour, minute: minute, ambiguous: ambiguous)
    }

    private static func duration(in text: String, now: Date, calendar: Calendar) -> MonoAIDeadline? {
        var durations: [Int] = []
        for match in matches(#"\b(?:через\s+полчаса|in\s+half\s+an?\s+hour)\b"#, in: text)
        where !negated(match.range, in: text) {
            durations.append(30)
        }
        let numeral = "(?:\\d{1,3}|" + numbers.keys.sorted { $0.count > $1.count }.joined(separator: "|") + ")"
        for match in matches(
            #"\b(?:через|in)\s+("# + numeral + #"(?:\s+"# + numeral
                + #")?)\s+(час(?:а|ов)?|hours?|минут(?:у|ы)?|minutes?)\b(?:\s+(?:и\s+)?(\d{1,2})\s+минут(?:у|ы)?\b)?"#,
            in: text) where !negated(match.range, in: text)
        {
            guard let amount = number(match.values[1].split(separator: " ").map(String.init)[...]) else { continue }
            let isHours = match.values[2].hasPrefix("час") || match.values[2].hasPrefix("hour")
            durations.append(amount * (isHours ? 60 : 1) + (Int(match.values[3]) ?? 0))
        }
        guard !durations.isEmpty else { return nil }
        guard Set(durations).count == 1, let minutes = durations.first, minutes > 0,
            let date = calendar.date(byAdding: .minute, value: minutes, to: now)
        else { return .init(clarification: "Уточните, через сколько часов или минут наступает срок.") }
        return .init(date: date, suggestedDate: date)
    }

    private static func futureDay(year: Int, month: Int, day: Int, allowNextYear: Bool, today: Date, calendar: Calendar)
        -> Date?
    {
        guard let candidate = strictDay(year: year, month: month, day: day, calendar: calendar) else { return nil }
        if allowNextYear && candidate < today {
            return strictDay(year: year + 1, month: month, day: day, calendar: calendar)
        }
        return candidate
    }

    private static func strictDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day ? date : nil
    }
}
