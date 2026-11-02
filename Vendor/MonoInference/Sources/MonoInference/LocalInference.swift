import Foundation
import llama

public enum InferenceError: LocalizedError {
    case load, context, prompt, decode, incomplete, timedOut

    public var errorDescription: String? {
        switch self {
        case .load: "Не удалось открыть модель. Попробуйте скачать её заново."
        case .context: "Не хватает памяти для Mono AI. Закройте другие приложения и повторите."
        case .prompt: "Слишком много текста для одного запроса. Попробуйте короче."
        case .decode: "Mono AI не смог обработать запрос. Попробуйте ещё раз."
        case .incomplete: "Mono AI не закончил ответ. Попробуйте сформулировать задачу короче."
        case .timedOut: "Gemma отвечает слишком долго. Локальный черновик задачи остаётся доступным."
        }
    }
}

public actor LocalInference {
    public static let shared = LocalInference()
    private var initialized = false

    public func generate(modelURL: URL, prompt: String, grammar: String, maximumDuration: TimeInterval = 20) throws
        -> String
    {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: .seconds(maximumDuration.isFinite ? min(max(maximumDuration, 1), 60) : 20))
        func checkWork() throws {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw InferenceError.timedOut }
        }
        try checkWork()
        if !initialized { llama_backend_init(); initialized = true }
        var modelParameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #else
        modelParameters.n_gpu_layers = 99
        #endif
        guard let model = llama_model_load_from_file(modelURL.path, modelParameters) else {
            throw InferenceError.load
        }
        defer { llama_model_free(model) }
        try checkWork()
        var parameters = llama_context_default_params()
        parameters.n_ctx = 4096
        parameters.n_batch = 256
        parameters.n_ubatch = 256
        parameters.n_threads = Int32(min(6, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
        parameters.n_threads_batch = parameters.n_threads
        guard let context = llama_init_from_model(model, parameters) else { throw InferenceError.context }
        defer { llama_free(context) }
        guard let vocabulary = llama_model_get_vocab(model) else { throw InferenceError.load }
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = llama_tokenize(
            vocabulary, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0, count < 3400 else { throw InferenceError.prompt }
        tokens = Array(tokens.prefix(Int(count)))
        for offset in stride(from: 0, to: tokens.count, by: 256) {
            try checkWork()
            let batchCount = Int32(min(256, tokens.count - offset))
            let result = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, batchCount))
            }
            guard result == 0 else { throw InferenceError.decode }
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw InferenceError.decode
        }
        defer { llama_sampler_free(sampler) }
        guard let constraint = llama_sampler_init_grammar(vocabulary, grammar, "root") else {
            throw InferenceError.decode
        }
        llama_sampler_chain_add(sampler, constraint)
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        var bytes: [UInt8] = []
        for _ in 0..<384 {
            try checkWork()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { return String(decoding: bytes, as: UTF8.self) }
            var piece = [CChar](repeating: 0, count: 512)
            let length = llama_token_to_piece(vocabulary, token, &piece, Int32(piece.count), 0, false)
            guard length >= 0 else { throw InferenceError.decode }
            bytes.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            let result = withUnsafeMutablePointer(to: &token) {
                llama_decode(context, llama_batch_get_one($0, 1))
            }
            guard result == 0 else { throw InferenceError.decode }
        }
        throw InferenceError.incomplete
    }
}
