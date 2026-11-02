import Foundation

struct MonoAIVoiceFile: Sendable {
    let path: String
    let bytes: Int64
    let sha256: String
}

enum MonoAIVoiceManifest {
    static let repository = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"
    static let revision = "08c72cad5e2fd0f41730c8bd1f28149585e46361"
    static let files: [MonoAIVoiceFile] = [
        .init(
            path: "config.json", bytes: 6058, sha256: "612cb591b44547319e5c68a78c0e93e4defb57882a4aa9ef5f06cc2f071ed036"
        ),
        .init(
            path: "generation_config.json", bytes: 245,
            sha256: "f1b90b4513f3b34c62851049e2492d7b4c5940daf1276f89c82b8ef04127f3aa"),
        .init(
            path: "merges.txt", bytes: 1671839,
            sha256: "599bab54075088774b1733fde865d5bd747cbcc7a547c5bc12610e874e26f5e3"),
        .init(
            path: "model.safetensors", bytes: 1006772520,
            sha256: "4ab02a20be381700f6e73dbb5efdc424cadf9f1d0652cbffd662872ea41e296a"),
        .init(
            path: "preprocessor_config.json", bytes: 127,
            sha256: "efdde1022ea9d76928bf7a9cd53139138f5ba2e466e837f08f6105ab1af1c119"),
        .init(
            path: "speech_tokenizer/config.json", bytes: 2336,
            sha256: "ee65bb901c876664ab8707c487157aa1a6ee57c65969b28fb5ec9dc211e68167"),
        .init(
            path: "speech_tokenizer/configuration.json", bytes: 76,
            sha256: "6bc26d64eb5024b4d1dab5a52371958b429256d6c9d59787f1f5294a54e0cebd"),
        .init(
            path: "speech_tokenizer/model.safetensors", bytes: 682293092,
            sha256: "836b7b357f5ea43e889936a3709af68dfe3751881acefe4ecf0dbd30ba571258"),
        .init(
            path: "speech_tokenizer/preprocessor_config.json", bytes: 234,
            sha256: "fcb3805e597e786d4067706e602f6688524640f8d3396790e2e09b5942fcbdfb"),
        .init(
            path: "tokenizer_config.json", bytes: 7344,
            sha256: "dc3c31c3bdaedd5016382bb3cbe07323026775ad51f5a4fb564505992ae4a670"),
        .init(
            path: "vocab.json", bytes: 2776833,
            sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
    ]
    static var byteCount: Int64 { files.reduce(0) { $0 + $1.bytes } }
    static func url(for file: MonoAIVoiceFile) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)?download=true")!
    }
}

enum MonoAIPresetVoice: String, CaseIterable, Identifiable, Sendable {
    case ryan, aiden, vivian, serena
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var gender: String {
        switch self {
        case .ryan, .aiden: "Мужской"
        case .vivian, .serena: "Женский"
        }
    }
    var detail: String {
        switch self {
        case .ryan: "Выразительный, ритмичный"
        case .aiden: "Светлый, ясный"
        case .vivian: "Яркий, энергичный"
        case .serena: "Мягкий, тёплый"
        }
    }
}
