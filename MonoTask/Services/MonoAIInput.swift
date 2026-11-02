import Foundation

struct MonoAIInput {
    var draft = ""
    private(set) var message = ""
    private(set) var voiceTranscript = ""
    private(set) var voiceMode = false

    var pending: String {
        let parts = voiceMode ? [draft, voiceTranscript] : [draft]
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    mutating func beginVoice() {
        voiceMode = true
        voiceTranscript = ""
    }

    mutating func receive(_ transcript: String) {
        guard voiceMode else { return }
        voiceTranscript = transcript
    }

    mutating func useKeyboard() {
        guard voiceMode else { return }
        draft = pending
        voiceTranscript = ""
        voiceMode = false
    }

    @discardableResult
    mutating func submit() -> String? {
        let input = pending
        guard !input.isEmpty else { return nil }
        message = input
        draft = ""
        voiceTranscript = ""
        voiceMode = false
        return input
    }
}
