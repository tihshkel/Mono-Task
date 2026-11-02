import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class MonoAIModelStore {
    static let shared = MonoAIModelStore()
    nonisolated static let byteCount: Int64 = 806_058_240
    nonisolated static let digest = "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135"
    static let downloadURL = URL(
        string:
            "https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf?download=true"
    )!

    private(set) var isInstalled = false
    private(set) var isDownloading = false
    private(set) var isVerifying = false
    private(set) var progress = 0.0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var isGenerating = false
    var error: String?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID: UUID?
    @ObservationIgnored private var generationID: UUID?
    @ObservationIgnored private var verifiedModificationDate: Date?
    @ObservationIgnored private var rejectedModificationDate: Date?

    let modelURL: URL

    init(directory: URL? = nil) {
        #if DEBUG
        let preview =
            ProcessInfo.processInfo.arguments.contains("--screenshots")
            || Bundle.main.object(forInfoDictionaryKey: "MonoAIReviewMode") as? Bool == true
        #else
        let preview = false
        #endif
        let root =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(preview ? "MonoTask/MonoAI-Preview" : "MonoTask/MonoAI", isDirectory: true)
        modelURL = root.appendingPathComponent("gemma-3-1b-it-Q4_K_M.gguf")
        refreshAvailability()
    }

    func refreshAvailability() {
        let values = try? modelURL.resolvingSymlinksInPath().resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey,
        ])
        let rejected = rejectedModificationDate != nil && values?.contentModificationDate == rejectedModificationDate
        isInstalled = values?.fileSize == Int(Self.byteCount) && !rejected
        if !isInstalled { verifiedModificationDate = nil }
    }

    func beginGeneration() -> UUID? {
        refreshAvailability()
        guard isInstalled, !isGenerating, !isDownloading else { return nil }
        let identifier = UUID()
        generationID = identifier
        isGenerating = true
        return identifier
    }

    func finishGeneration(_ identifier: UUID) {
        guard generationID == identifier else { return }
        generationID = nil
        isGenerating = false
    }

    func prepareForInference() async throws {
        refreshAvailability()
        guard isInstalled else {
            throw MonoAIError.message(
                "Файл Gemma недоступен. Локальный черновик задачи сохранён; модель можно скачать заново.")
        }
        error = nil
        let actualURL = modelURL.resolvingSymlinksInPath()
        let modification = try actualURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let modification, verifiedModificationDate == modification { return }
        let verification = Task.detached { try Self.verify(actualURL) }
        do {
            try await withTaskCancellationHandler {
                try await verification.value
            } onCancel: {
                verification.cancel()
            }
            try Task.checkCancellation()
            let current = try actualURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard current == modification else {
                throw MonoAIError.message("Файл модели изменился во время проверки. Повторите попытку.")
            }
            verifiedModificationDate = modification
        } catch {
            if !(error is CancellationError) {
                isInstalled = false
                verifiedModificationDate = nil
                rejectedModificationDate = modification
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    var status: String {
        if isVerifying { return "Проверяю целостность модели…" }
        if isDownloading {
            if downloadedBytes == 0 { return "Подключаюсь к серверу модели…" }
            return
                "\(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .decimal)) из 806 МБ · \(Int(progress * 100))%"
        }
        if isInstalled { return "Готова к работе · на этом устройстве" }
        return "Gemma 3 1B · 806 МБ"
    }

    func download() {
        guard !isDownloading, !isInstalled, !isGenerating else { return }
        error = nil
        isDownloading = true
        progress = 0
        downloadedBytes = 0
        let identifier = UUID()
        downloadID = identifier
        let downloader = MonoAIModelDownload { [weak self] received in
            Task { @MainActor in
                guard self?.downloadID == identifier else { return }
                self?.downloadedBytes = received
                self?.progress = min(1, max(0, Double(received) / Double(Self.byteCount)))
            }
        }
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(
                    at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let values = try modelURL.deletingLastPathComponent().resourceValues(forKeys: [
                    .volumeAvailableCapacityForImportantUsageKey
                ])
                if let free = values.volumeAvailableCapacityForImportantUsage, free < Self.byteCount + 200_000_000 {
                    throw MonoAIError.message("Для загрузки нужен минимум 1 ГБ свободного места.")
                }
                let request = URLRequest(
                    url: Self.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
                let temporary = try await downloader.download(request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                isVerifying = true
                progress = 1
                downloadedBytes = Self.byteCount
                let verification = Task.detached { try Self.verify(temporary) }
                try await withTaskCancellationHandler {
                    try await verification.value
                } onCancel: {
                    verification.cancel()
                }
                try Task.checkCancellation()
                guard downloadID == identifier else { return }
                if FileManager.default.fileExists(atPath: modelURL.path) {
                    _ = try FileManager.default.replaceItemAt(modelURL, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: modelURL)
                }
                verifiedModificationDate = try modelURL.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                rejectedModificationDate = nil
                for name in ["GemmaTerms", "GemmaProhibitedUse", "MonoAINotice"] {
                    if let source = Bundle.main.url(forResource: name, withExtension: "txt") {
                        let destination = modelURL.deletingLastPathComponent().appendingPathComponent(name + ".txt")
                        if !FileManager.default.fileExists(atPath: destination.path) {
                            try? FileManager.default.copyItem(at: source, to: destination)
                        }
                    }
                }
                var resource = modelURL
                var exclusions = URLResourceValues()
                exclusions.isExcludedFromBackup = true
                try? resource.setResourceValues(exclusions)
                isInstalled = true
            } catch {
                if downloadID == identifier && !Task.isCancelled {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        self.error = "Сервер модели не отвечает. Проверьте интернет и повторите загрузку."
                    } else {
                        self.error = error.localizedDescription
                    }
                }
            }
            guard downloadID == identifier else { return }
            isDownloading = false
            isVerifying = false
            downloadID = nil
            downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadID = nil
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        isVerifying = false
        progress = 0
        downloadedBytes = 0
    }

    func remove() {
        guard !isDownloading, !isGenerating else { return }
        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
            isInstalled = false
            verifiedModificationDate = nil
            rejectedModificationDate = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    nonisolated static func verify(_ url: URL) throws {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(byteCount) else {
            throw MonoAIError.message("Модель загрузилась не полностью. Повторите загрузку.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else {
            throw MonoAIError.message("Проверка SHA-256 не пройдена. Файл не будет использован.")
        }
    }
}
