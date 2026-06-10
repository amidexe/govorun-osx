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

final class GigaAMEngine: @unchecked Sendable {
    private var recognizer: OpaquePointer?
    // Serial queue владеет recognizer: гарантирует, что выгрузка никогда не
    // случится во время декодирования (всё — load/unload/decode — на ней).
    private let queue = DispatchQueue(label: "com.govorun.gigaam")
    private let logger = Logger(subsystem: "com.govorun.app", category: "GigaAMEngine")
    private static let defaultThreadCount: Int32 = 2

    // Модель НЕ грузится при старте приложения. Грузится по требованию
    // (preload при старте записи / первая фраза) и выгружается после простоя
    // (см. AudioEngine.scheduleIdleCleanup). Это убирает ~500 МБ ОЗУ и спин
    // потоков ONNX Runtime в покое, когда диктовка не идёт.

    deinit {
        if let r = recognizer { SherpaOnnxDestroyOfflineRecognizer(r) }
    }

    /// Прогреть модель заранее — чтобы первая фраза не ждала загрузку.
    func preload() {
        queue.async { [self] in if recognizer == nil { loadOnQueue() } }
    }

    /// Выгрузить модель из памяти (освобождает ОЗУ и гасит потоки ONNX).
    func unload() {
        queue.async { [self] in
            guard let r = recognizer else { return }
            SherpaOnnxDestroyOfflineRecognizer(r)
            recognizer = nil
            logger.info("GigaAM выгружена из памяти")
        }
    }

    func transcribeSamples(_ samples: [Float]) async throws -> String {
        guard samples.count > 1600 else { throw GigaAMError.audioTooShort }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                if recognizer == nil { loadOnQueue() }
                guard let r = recognizer else { cont.resume(throwing: GigaAMError.initFailed); return }
                do { cont.resume(returning: try Self.decode(recognizer: r, samples: samples)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        let samples = try Self.readPCM(from: audioURL)
        return try await transcribeSamples(samples)
    }

    // Загрузка распознавателя. Вызывается ТОЛЬКО на serial queue.
    private func loadOnQueue() {
        let dir = Self.bundledModelDir()
        let paths = ModelPaths(dir: dir)
        guard paths.areValid() else {
            logger.error("Model files missing at \(dir.path)")
            DiagnosticsLog.record("Файлы модели GigaAM не найдены.", category: "Распознавание", level: .error)
            return
        }
        for provider in ["coreml", "cpu"] {
            if let r = createRecognizer(paths: paths, provider: provider) {
                recognizer = r
                logger.info("GigaAM ready (provider=\(provider), threads=\(Self.threadCount))")
                DiagnosticsLog.record("GigaAM готова: \(provider), \(Self.threadCount) потока.", category: "Распознавание")
                return
            }
        }
        logger.error("Failed to init recognizer with any provider")
        DiagnosticsLog.record("Не удалось инициализировать GigaAM.", category: "Распознавание", level: .error)
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
                                    cfg.model_config.num_threads = Self.threadCount
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

    private static var threadCount: Int32 {
        let env = ProcessInfo.processInfo.environment["GOVORUN_ASR_THREADS"].flatMap(Int32.init)
        let stored = UserDefaults.standard.object(forKey: "recognitionThreads") as? Int
        let raw = env ?? stored.map(Int32.init) ?? defaultThreadCount
        return min(4, max(1, raw))
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
