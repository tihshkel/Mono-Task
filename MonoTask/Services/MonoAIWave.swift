import Foundation

enum MonoAIWave {
    enum EncodingError: LocalizedError {
        case invalidAudio

        var errorDescription: String? { "Нейроголос вернул некорректный звук. Попробуйте другой голос." }
    }

    static func validatedData(samples: [Float], sampleRate: Int) throws -> Data {
        guard (8_000...192_000).contains(sampleRate), !samples.isEmpty,
            samples.count <= (Int(UInt32.max) - 36) / MemoryLayout<Int16>.size,
            samples.allSatisfy(\.isFinite), samples.contains(where: { abs($0) > 0.000_01 })
        else { throw EncodingError.invalidAudio }
        return data(samples: samples, sampleRate: sampleRate)
    }

    static func data(samples: [Float], sampleRate: Int) -> Data {
        guard (8_000...192_000).contains(sampleRate),
            samples.count <= (Int(UInt32.max) - 36) / MemoryLayout<Int16>.size
        else { return Data() }
        let pcm = samples.map { sample in
            Int16((min(max(sample.isFinite ? sample : 0, -1), 1) * 32767).rounded()).littleEndian
        }
        let payload = pcm.withUnsafeBytes { Data($0) }
        var result = Data("RIFF".utf8)
        func append(_ value: UInt32) {
            var encoded = value.littleEndian
            withUnsafeBytes(of: &encoded) { result.append(contentsOf: $0) }
        }
        append(UInt32(payload.count + 36))
        result.append(contentsOf: "WAVEfmt ".utf8)
        append(16)
        result.append(contentsOf: [1, 0, 1, 0])
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        result.append(contentsOf: [2, 0, 16, 0])
        result.append(contentsOf: "data".utf8)
        append(UInt32(payload.count))
        result.append(payload)
        return result
    }
}
