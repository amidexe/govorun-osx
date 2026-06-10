import Foundation
import SherpaOnnx

enum BenchError: Error {
    case badArguments
    case audioTooShort
    case recognizerFailed(Int32)
    case streamFailed
    case noResult
}

struct ModelPaths {
    let encoder: String
    let decoder: String
    let joiner: String
    let tokens: String
}

func readPCM(from url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    guard data.count >= 46 else { throw BenchError.audioTooShort }
    let end = data.count - ((data.count - 44) % 2)
    return stride(from: 44, to: end, by: 2).map { offset in
        data[offset..<offset + 2].withUnsafeBytes {
            let s = Int16(littleEndian: $0.load(as: Int16.self))
            return max(-1.0, min(Float(s) / 32768.0, 1.0))
        }
    }
}

func createRecognizer(paths: ModelPaths, threads: Int32) throws -> OpaquePointer {
    let modelType = "nemo_transducer"
    let decoding = "greedy_search"
    return try paths.encoder.withCString { enc in
        try paths.decoder.withCString { dec in
            try paths.joiner.withCString { join in
                try paths.tokens.withCString { tok in
                    try modelType.withCString { mtype in
                        try "cpu".withCString { provider in
                            try decoding.withCString { dm in
                                var cfg = SherpaOnnxOfflineRecognizerConfig()
                                cfg.feat_config.sample_rate = 16000
                                cfg.feat_config.feature_dim = 80
                                cfg.model_config.transducer.encoder = enc
                                cfg.model_config.transducer.decoder = dec
                                cfg.model_config.transducer.joiner = join
                                cfg.model_config.tokens = tok
                                cfg.model_config.num_threads = threads
                                cfg.model_config.provider = provider
                                cfg.model_config.model_type = mtype
                                cfg.decoding_method = dm
                                guard let recognizer = SherpaOnnxCreateOfflineRecognizer(&cfg) else {
                                    throw BenchError.recognizerFailed(threads)
                                }
                                return recognizer
                            }
                        }
                    }
                }
            }
        }
    }
}

func decode(recognizer: OpaquePointer, samples: [Float]) throws -> String {
    guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { throw BenchError.streamFailed }
    defer { SherpaOnnxDestroyOfflineStream(stream) }
    samples.withUnsafeBufferPointer { ptr in
        SherpaOnnxAcceptWaveformOffline(stream, 16000, ptr.baseAddress, Int32(samples.count))
    }
    SherpaOnnxDecodeOfflineStream(recognizer, stream)
    guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw BenchError.noResult }
    defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
    return result.pointee.text.map { String(cString: $0) } ?? ""
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: benchmark_gigaam_threads.swift MODEL_DIR AUDIO_WAV [threads...]\n", stderr)
    exit(2)
}

let modelDir = URL(fileURLWithPath: args[1])
let audioURL = URL(fileURLWithPath: args[2])
let threads = args.dropFirst(3).compactMap { Int32($0) }
let threadCounts = threads.isEmpty ? [1, 2, 4] : threads
let paths = ModelPaths(
    encoder: modelDir.appendingPathComponent("gigaam_v3_e2e_rnnt_encoder_int8.onnx").path,
    decoder: modelDir.appendingPathComponent("gigaam_v3_e2e_rnnt_decoder.onnx").path,
    joiner: modelDir.appendingPathComponent("gigaam_v3_e2e_rnnt_joint.onnx").path,
    tokens: modelDir.appendingPathComponent("gigaam_v3_e2e_rnnt_tokens.txt").path
)

let samples = try readPCM(from: audioURL)
let duration = Double(samples.count) / 16000.0
print(String(format: "audio %.2fs, %d samples, %@", duration, samples.count, audioURL.lastPathComponent))

for threadCount in threadCounts {
    let loadStart = CFAbsoluteTimeGetCurrent()
    let recognizer = try createRecognizer(paths: paths, threads: threadCount)
    let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
    defer { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    let start = CFAbsoluteTimeGetCurrent()
    let text = try decode(recognizer: recognizer, samples: samples)
    let decodeMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
    let realTimeFactor = (decodeMs / 1000.0) / max(duration, 0.001)
    print(String(
        format: "threads=%d load=%.0fms decode=%.0fms rtf=%.3f chars=%d",
        threadCount,
        loadMs,
        decodeMs,
        realTimeFactor,
        text.count
    ))
}
