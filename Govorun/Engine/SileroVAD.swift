import Foundation
import SherpaOnnx
import os

enum PauseLength: String, CaseIterable {
    case short  = "short"
    case medium = "medium"
    case long   = "long"

    var seconds: Float {
        switch self {
        case .short:  return 0.5
        case .medium: return 1.0
        case .long:   return 2.0
        }
    }

    var label: String {
        switch self {
        case .short:  return "Короткая"
        case .medium: return "Средняя"
        case .long:   return "Длинная"
        }
    }

    static var stored: PauseLength {
        get {
            let raw = UserDefaults.standard.string(forKey: "pauseLength") ?? ""
            return PauseLength(rawValue: raw) ?? .medium
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "pauseLength") }
    }
}

final class SileroVAD {
    static let windowSize = 512   // samples @ 16kHz — Silero v4 requirement

    private var vad: OpaquePointer?
    private let logger = Logger(subsystem: "com.govorun.app", category: "SileroVAD")

    init?(pauseLength: PauseLength = .medium) {
        guard let modelURL = Bundle.main.url(forResource: "silero_vad", withExtension: "onnx",
                                              subdirectory: "Model") else {
            logger.error("silero_vad.onnx not found in bundle")
            return nil
        }
        vad = modelURL.path.withCString { modelPath in
            var silero = SherpaOnnxSileroVadModelConfig()
            silero.model              = modelPath
            silero.threshold          = 0.25
            silero.min_silence_duration = pauseLength.seconds
            silero.min_speech_duration  = 0.15
            silero.window_size          = Int32(SileroVAD.windowSize)
            silero.max_speech_duration  = 30.0

            var cfg = SherpaOnnxVadModelConfig()
            cfg.silero_vad  = silero
            cfg.sample_rate = 16000
            cfg.num_threads = 1
            cfg.provider    = nil
            cfg.debug       = 0

            return SherpaOnnxCreateVoiceActivityDetector(&cfg, 60.0)
        }
        guard vad != nil else {
            logger.error("Failed to create VAD instance")
            return nil
        }
        logger.info("Silero VAD ready (pause=\(pauseLength.seconds)s)")
    }

    deinit {
        if let v = vad { SherpaOnnxDestroyVoiceActivityDetector(v) }
    }

    func reset() {
        if let v = vad { SherpaOnnxVoiceActivityDetectorReset(v) }
    }

/// Feed exactly `windowSize` Float32 samples. Returns detected speech segments.
    func accept(_ samples: [Float]) -> [[Float]] {
        guard let v = vad else { return [] }
        samples.withUnsafeBufferPointer { ptr in
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(v, ptr.baseAddress, Int32(samples.count))
        }
        return drainSegments()
    }

    func isSpeechDetected() -> Bool {
        guard let v = vad else { return false }
        return SherpaOnnxVoiceActivityDetectorDetected(v) != 0
    }

    private func drainSegments() -> [[Float]] {
        guard let v = vad else { return [] }
        var segments: [[Float]] = []
        while SherpaOnnxVoiceActivityDetectorEmpty(v) == 0 {
            if let seg = SherpaOnnxVoiceActivityDetectorFront(v) {
                let count = Int(seg.pointee.n)
                let floats = Array(UnsafeBufferPointer(start: seg.pointee.samples, count: count))
                segments.append(floats)
                SherpaOnnxDestroySpeechSegment(seg)
            }
            SherpaOnnxVoiceActivityDetectorPop(v)
        }
        return segments
    }

    /// Flush + drain — call when recording stops to get final segment.
    func flushAndDrain() -> [[Float]] {
        guard let v = vad else { return [] }
        SherpaOnnxVoiceActivityDetectorFlush(v)
        return drainSegments()
    }
}
