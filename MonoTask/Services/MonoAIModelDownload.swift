import Foundation

final class MonoAIModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var started = false
    private var lastUpdate = Date.distantPast
    private let progress: @Sendable (Int64) -> Void

    init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }

    func download(_ request: URLRequest) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    guard !cancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard !started else {
                        continuation.resume(
                            throwing: MonoAIError.message(
                                "Загрузка уже запущена. Дождитесь завершения или отмените её."))
                        return
                    }
                    started = true
                    self.continuation = continuation
                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = 45
                    configuration.timeoutIntervalForResource = 3600
                    configuration.waitsForConnectivity = false
                    configuration.allowsCellularAccess = true
                    configuration.urlCache = nil
                    let queue = OperationQueue()
                    queue.maxConcurrentOperationCount = 1
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                    self.session = session
                    let task = session.downloadTask(with: request)
                    self.task = task
                    task.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        let state = lock.withLock {
            cancelled = true
            let pending = continuation
            let activeTask = task
            let activeSession = session
            continuation = nil
            task = nil
            session = nil
            return (pending, activeTask, activeSession)
        }
        state.1?.cancel()
        state.2?.invalidateAndCancel()
        state.0?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<URL, Error>) {
        let pending = lock.withLock {
            let pending = continuation
            continuation = nil
            return pending
        }
        if let pending {
            pending.resume(with: result)
        } else if case .success(let file) = result {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let notify = lock.withLock {
            guard !cancelled, continuation != nil,
                now.timeIntervalSince(lastUpdate) >= 0.2 || totalBytesWritten == totalBytesExpectedToWrite
            else { return false }
            lastUpdate = now
            return true
        }
        if notify { progress(totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
            (200...299).contains(response.statusCode)
        else {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            finish(.failure(MonoAIError.message("Сервер модели вернул ошибку \(status). Повторите загрузку.")))
            return
        }
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("MonoAI-\(UUID().uuidString).gguf")
            try FileManager.default.moveItem(at: location, to: file)
            finish(.success(file))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.failure(MonoAIError.message("Не удалось сохранить файл модели. Повторите загрузку.")))
        }
        lock.withLock {
            self.task = nil; self.session = nil
        }
        session.finishTasksAndInvalidate()
    }
}
