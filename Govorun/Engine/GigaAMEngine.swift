import Foundation
import SherpaOnnx
import os

enum GigaAMError: LocalizedError {
    case modelNotFound(URL)
    case initFailed
    case streamFailed
    case noResult
    case audioTooShort

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let url): return "Модель не найдена: \(url.path)"
        case .initFailed:             return "Не удалось инициализировать распознаватель"
        case .streamFailed:           return "Ошибка создания потока"
        case .noResult:               return "Нет результата распознавания"
        case .audioTooShort:          return "Аудио слишком короткое"
        }
    }
}

final class GigaAMEngine {
    private var recognizer: OpaquePointer?
    private let logger = Logger(subsystem: "com.govorun.app", category: "GigaAMEngine")

    init() {
        loadRecognizer()
    }

    deinit {
        if let r = recognizer { SherpaOnnxDestroyOfflineRecognizer(r) }
    }

    private func loadRecognizer() {
        let dir = Self.bundledModelDir()
        let paths = ModelPaths(dir: dir)
        guard paths.areValid() else {
            logger.error("Model files missing at \(dir.path)")
            return
        }

        for provider in ["coreml", "cpu"] {
            if let r = createRecognizer(paths: paths, provider: provider) {
                recognizer = r
                logger.info("GigaAM ready (provider=\(provider))")
                return
            }
        }
        logger.error("Failed to init recognizer with any provider")
    }

    func transcribeSamples(_ samples: [Float]) async throws -> String {
        guard let recognizer else { throw GigaAMError.initFailed }
        guard samples.count > 1600 else { throw GigaAMError.audioTooShort }
        return try await Task.detached(priority: .userInitiated) {
            try Self.decode(recognizer: recognizer, samples: samples)
        }.value
    }

    func transcribe(audioURL: URL) async throws -> String {
        let samples = try Self.readPCM(from: audioURL)
        return try await transcribeSamples(samples)
    }

    private func createRecognizer(paths: ModelPaths, provider: String) -> OpaquePointer? {
        let modelType = "nemo_transducer"
        let decoding  = "greedy_search"
        return paths.encoder.path.withCString { enc in
            paths.decoder.path.withCString { dec in
                paths.joiner.path.withCString { join in
                    paths.tokens.path.withCString { tok in
                        modelType.withCString { mtype in
                            provider.withCString { prov in
                                decoding.withCString { dm in
                                    var cfg = SherpaOnnxOfflineRecognizerConfig()
                                    cfg.feat_config.sample_rate = 16000
                                    cfg.feat_config.feature_dim = 80
                                    cfg.model_config.transducer.encoder = enc
                                    cfg.model_config.transducer.decoder = dec
                                    cfg.model_config.transducer.joiner  = join
                                    cfg.model_config.tokens      = tok
                                    cfg.model_config.num_threads = 2
                                    cfg.model_config.provider    = prov
                                    cfg.model_config.model_type  = mtype
                                    cfg.decoding_method          = dm
                                    return SherpaOnnxCreateOfflineRecognizer(&cfg)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated private static func decode(recognizer: OpaquePointer, samples: [Float]) throws -> String {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { throw GigaAMError.streamFailed }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer { ptr in
            SherpaOnnxAcceptWaveformOffline(stream, 16000, ptr.baseAddress, Int32(samples.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw GigaAMError.noResult }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        return result.pointee.text.map { String(cString: $0) } ?? ""
    }

    nonisolated private static func readPCM(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 46 else { throw GigaAMError.audioTooShort }
        let end = data.count - ((data.count - 44) % 2)
        return stride(from: 44, to: end, by: 2).map { offset in
            data[offset..<offset + 2].withUnsafeBytes {
                let s = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(s) / 32768.0, 1.0))
            }
        }
    }

    static func bundledModelDir() -> URL {
        Bundle.main.resourceURL!.appendingPathComponent("Model")
    }
}

private struct ModelPaths {
    let encoder: URL
    let decoder: URL
    let joiner:  URL
    let tokens:  URL

    init(dir: URL) {
        encoder = dir.appendingPathComponent("gigaam_v3_e2e_rnnt_encoder_int8.onnx")
        decoder = dir.appendingPathComponent("gigaam_v3_e2e_rnnt_decoder.onnx")
        joiner  = dir.appendingPathComponent("gigaam_v3_e2e_rnnt_joint.onnx")
        tokens  = dir.appendingPathComponent("gigaam_v3_e2e_rnnt_tokens.txt")
    }

    func areValid() -> Bool {
        [encoder, decoder, joiner, tokens].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }
}
