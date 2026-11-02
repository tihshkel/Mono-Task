import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class MonoAIVoicePack {
    static let shared = MonoAIVoicePack()
    static var isSupported: Bool {
        #if arch(arm64) && !targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    let directory: URL
    private(set) var isInstalled = false
    private(set) var isDownloading = false
    private(set) var isVerifying = false
    private(set) var hasPartialDownload = false
    private(set) var received: Int64 = 0
    var isGenerating = false
    var error: String?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID: UUID?

    init(directory: URL? = nil) {
        #if DEBUG
        let preview =
            ProcessInfo.processInfo.arguments.contains("--screenshots")
            || Bundle.main.object(forInfoDictionaryKey: "MonoAIReviewMode") as? Bool == true
        #else
        let preview = false
        #endif
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                preview ? "MonoTask/MonoVoices-Preview/Qwen3" : "MonoTask/MonoVoices/Qwen3", isDirectory: true)
        isInstalled = Self.isComplete(self.directory)
        hasPartialDownload = FileManager.default.fileExists(atPath: stagingDirectory.path)
    }

    private var stagingDirectory: URL {
        directory.deletingLastPathComponent().appendingPathComponent(
            "Qwen3.partial-" + MonoAIVoiceManifest.revision, isDirectory: true)
    }

    var progress: Double { min(1, Double(received) / Double(MonoAIVoiceManifest.byteCount)) }
    var status: String {
        if isVerifying { return "Проверяю целостность файлов…" }
        if isDownloading {
            if received == 0 { return "Подключаюсь к серверу голосов…" }
            return
                "\(ByteCountFormatter.string(fromByteCount: received, countStyle: .decimal)) из 1,69 ГБ · \(Int(progress * 100))%"
        }
        return isInstalled ? "Четыре голоса готовы · офлайн" : "Одна модель для четырёх голосов · 1,69 ГБ"
    }

    func download() {
        guard Self.isSupported, !isDownloading, !isInstalled else { return }
        let identifier = UUID()
        downloadID = identifier
        error = nil
        received = 0
        isDownloading = true
        downloadTask = Task {
            let parent = directory.deletingLastPathComponent()
            let staging = stagingDirectory
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                hasPartialDownload = true
                var exclusions = URLResourceValues()
                exclusions.isExcludedFromBackup = true
                var excludedParent = parent
                try? excludedParent.setResourceValues(exclusions)
                let capacity = try parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage
                let cachedBytes = MonoAIVoiceManifest.files.reduce(Int64.zero) { total, file in
                    let size = try? staging.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey])
                        .fileSize
                    return total + (size == Int(file.bytes) ? file.bytes : 0)
                }
                if let capacity, capacity < MonoAIVoiceManifest.byteCount - cachedBytes + 500_000_000 {
                    throw MonoAIError.message(
                        "Для загрузки голосов не хватает свободного места. Загруженные файлы сохранены; освободите место и продолжите."
                    )
                }
                var completed: Int64 = 0
                for file in MonoAIVoiceManifest.files {
                    try Task.checkCancellation()
                    guard downloadID == identifier else { throw CancellationError() }
                    let destination = staging.appendingPathComponent(file.path)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        isVerifying = true
                        do {
                            try await verifyFile(destination, file: file)
                            try Task.checkCancellation()
                            guard downloadID == identifier else { throw CancellationError() }
                            completed += file.bytes
                            received = completed
                            isVerifying = false
                            continue
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            try Task.checkCancellation()
                            guard downloadID == identifier else { throw CancellationError() }
                            try FileManager.default.removeItem(at: destination)
                            isVerifying = false
                        }
                    }
                    let base = completed
                    let progress: @Sendable (Int64) -> Void = { [weak self] bytes in
                        Task { @MainActor in
                            guard let self, self.downloadID == identifier else { return }
                            self.received = max(self.received, base + min(bytes, file.bytes))
                        }
                    }
                    let available = try parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                        .volumeAvailableCapacityForImportantUsage
                    if let available, available < file.bytes + 500_000_000 {
                        throw MonoAIError.message(
                            "Недостаточно места для следующего файла голоса. Освободите место и продолжите загрузку.")
                    }
                    let temporary = try await downloadFile(file, progress: progress)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try Task.checkCancellation()
                    guard downloadID == identifier else { throw CancellationError() }
                    isVerifying = true
                    try await verifyFile(temporary, file: file)
                    try Task.checkCancellation()
                    guard downloadID == identifier else { throw CancellationError() }
                    isVerifying = false
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    completed += file.bytes
                    received = completed
                }
                try Data(MonoAIVoiceManifest.revision.utf8).write(
                    to: staging.appendingPathComponent("verified-revision"), options: .atomic)
                try Task.checkCancellation()
                guard downloadID == identifier else { throw CancellationError() }
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
                try FileManager.default.moveItem(at: staging, to: directory)
                isInstalled = true
                hasPartialDownload = false
            } catch {
                if downloadID == identifier && !Task.isCancelled { self.error = error.localizedDescription }
            }
            guard downloadID == identifier else { return }
            isDownloading = false
            isVerifying = false
            downloadID = nil
            downloadTask = nil
        }
    }

    private func verifyFile(_ url: URL, file: MonoAIVoiceFile) async throws {
        let verification = Task.detached { try Self.verify(url, file: file) }
        try await withTaskCancellationHandler {
            try await verification.value
        } onCancel: {
            verification.cancel()
        }
    }

    private func downloadFile(_ file: MonoAIVoiceFile, progress: @escaping @Sendable (Int64) -> Void) async throws
        -> URL
    {
        for attempt in 0..<3 {
            do {
                let downloader = MonoAIModelDownload(progress: progress)
                return try await downloader.download(
                    URLRequest(url: MonoAIVoiceManifest.url(for: file), timeoutInterval: 45))
            } catch let error as URLError
                where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code)
            {
                guard attempt < 2 else { throw error }
                try await Task.sleep(for: .seconds(2 * (attempt + 1)))
            }
        }
        throw MonoAIError.message("Не удалось загрузить голоса. Повторите попытку.")
    }

    func cancelDownload() {
        downloadID = nil
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        isVerifying = false
        received = 0
    }

    func remove() {
        guard !isGenerating, !isDownloading else { return }
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            if FileManager.default.fileExists(atPath: stagingDirectory.path) {
                try FileManager.default.removeItem(at: stagingDirectory)
            }
            isInstalled = false
            hasPartialDownload = false
            received = 0
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    nonisolated static func isComplete(_ directory: URL) -> Bool {
        guard
            (try? String(contentsOf: directory.appendingPathComponent("verified-revision"), encoding: .utf8))
                == MonoAIVoiceManifest.revision
        else { return false }
        return MonoAIVoiceManifest.files.allSatisfy { file in
            (try? directory.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize)
                == Int(file.bytes)
        }
    }

    nonisolated static func verify(_ url: URL, file: MonoAIVoiceFile) throws {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(file.bytes) else {
            throw MonoAIError.message("Файл голоса загрузился не полностью. Повторите загрузку.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw MonoAIError.message("Проверка целостности голоса не прошла. Повторите загрузку.")
        }
    }
}
