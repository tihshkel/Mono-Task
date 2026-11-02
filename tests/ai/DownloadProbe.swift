import Foundation

private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var maximum: Int64 = 0
    var received: Int64 { lock.withLock { maximum } }
    func update(_ bytes: Int64) { lock.withLock { maximum = max(maximum, bytes) } }
}

@main
struct DownloadProbe {
    static func main() async throws {
        let url = URL(
            string:
                "https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf?download=true"
        )!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("bytes=0-1048575", forHTTPHeaderField: "Range")
        let counter = ProgressCounter()
        let downloader = MonoAIModelDownload { counter.update($0) }
        let file = try await downloader.download(request)
        defer { try? FileManager.default.removeItem(at: file) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        precondition(counter.received > 0, "No progress callbacks")
        precondition(size == 1_048_576, "Range response differs from expected fixture size")
        print("PASS: range download \(size) bytes, reported progress \(counter.received) bytes")

        let cancelled = Task {
            try await MonoAIModelDownload { _ in }.download(request)
        }
        cancelled.cancel()
        do {
            let leftover = try await cancelled.value
            try? FileManager.default.removeItem(at: leftover)
            preconditionFailure("Cancellation was ignored")
        } catch is CancellationError { print("PASS: cancellation before connection") }
    }
}
