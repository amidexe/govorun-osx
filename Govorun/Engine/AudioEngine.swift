import Foundation
import CoreAudio
import AVFoundation
import os

@MainActor
final class AudioEngine: ObservableObject {
    enum State { case idle, recording, processing }

    @Published var state: State = .idle
    @Published var audioLevel: Double = 0
    @Published var transcribedText: String = ""

    private var recorder: CoreAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: DispatchSourceTimer?
    private let gigaAM = GigaAMEngine()
    private let logger = Logger(subsystem: "com.govorun.app", category: "AudioEngine")

    // Silero VAD (rebuilt when pause setting changes)
    private var vad: SileroVAD?
    private var lastPause: PauseLength = .medium

    // Выгрузка модели/VAD из памяти после простоя (экономия ОЗУ + CPU в покое).
    private var idleCleanupTask: Task<Void, Never>?
    private let idleUnloadDelay: TimeInterval = 120

    // PCM window accumulator — Silero needs exactly 512 samples per call
    private var windowBuf: [Float] = []

    // Streaming transcription
    private var accumulated      = ""
    private var chunkResults     = [Int: String]()
    private var nextChunkIdx     = 0
    private var nextFlushIdx     = 0
    private var pendingTasks     = [Task<Void, Never>]()
    // Только реальная речь (VAD-сегменты), без пауз
    private(set) var speechSamples: Int = 0

    func startRecording() async throws {
        guard state == .idle else { return }
        state = .recording
        transcribedText = ""

        // Прерываем отложенную выгрузку и греем модель, пока пользователь говорит.
        idleCleanupTask?.cancel(); idleCleanupTask = nil
        gigaAM.preload()

        accumulated   = ""
        chunkResults  = [:]
        nextChunkIdx  = 0
        nextFlushIdx  = 0
        pendingTasks  = []
        windowBuf     = []
        speechSamples = 0

        let pause = PauseLength.stored
        if vad == nil || lastPause != pause {
            vad = SileroVAD(pauseLength: pause)
            lastPause = pause
        }
        vad?.reset()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("govorun_\(Int(Date().timeIntervalSince1970)).wav")
        recordingURL = url

        let rec = CoreAudioRecorder()
        recorder = rec
        let deviceID = defaultInputDeviceID()
        try rec.startRecording(toOutputFile: url, deviceID: deviceID)
        startLevelTimer()
        logger.info("Recording started → \(url.lastPathComponent)")
    }

    func stopRecording() async throws -> String {
        guard state == .recording else { return "" }
        state = .processing
        stopLevelTimer()
        audioLevel = 0

        // Drain remaining PCM from recorder
        let remaining = recorder?.drainSamples() ?? []
        recorder?.stopRecording()
        recorder = nil

        // Feed remaining + flush VAD to get final segment
        if let vad {
            var leftovers = windowBuf + remaining
            var offset = 0
            while leftovers.count - offset >= SileroVAD.windowSize {
                let end = offset + SileroVAD.windowSize
                let win = Array(leftovers[offset..<end])
                offset = end
                let segs = vad.accept(win)
                for s in segs where s.count > 1600 { scheduleChunk(s) }
            }
            if offset > 0 { leftovers.removeFirst(offset) }
            // Flush for final segment
            let finalSegs = vad.flushAndDrain()
            for s in finalSegs where s.count > 1600 { scheduleChunk(s) }
            // Raw tail fallback: if nothing came from VAD but we have audio
            if finalSegs.isEmpty && !leftovers.isEmpty && leftovers.count > 1600 {
                scheduleChunk(leftovers)
            }
        } else if remaining.count > 1600 {
            scheduleChunk(remaining)
        }
        windowBuf = []

        for task in pendingTasks { await task.value }
        pendingTasks = []
        flushResults()

        if let url = recordingURL {
            recordingURL = nil
            try? FileManager.default.removeItem(at: url)
        }

        let result = accumulated
        transcribedText = result
        accumulated  = ""
        chunkResults = [:]
        nextChunkIdx = 0
        nextFlushIdx = 0

        state = .idle
        logger.info("Final: \(result.prefix(80))")
        scheduleIdleCleanup()
        return result
    }

    /// После простоя выгружаем GigaAM и VAD из памяти — чтобы в покое не висели
    /// ~500 МБ и не крутились потоки ONNX. При новой записи модель грузится снова.
    private func scheduleIdleCleanup() {
        idleCleanupTask?.cancel()
        idleCleanupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.idleUnloadDelay ?? 120))
            guard !Task.isCancelled, let self, self.state == .idle else { return }
            self.gigaAM.unload()
            self.vad = nil
            self.logger.info("Idle \(Int(self.idleUnloadDelay)) c: GigaAM и VAD выгружены")
        }
    }

    private func scheduleChunk(_ samples: [Float]) {
        speechSamples += samples.count
        let idx = nextChunkIdx
        nextChunkIdx += 1
        let task = Task<Void, Never> { [weak self] in
            await self?.processChunk(samples, index: idx)
        }
        pendingTasks.append(task)
    }

    private func processChunk(_ samples: [Float], index: Int) async {
        do {
            let text = try await gigaAM.transcribeSamples(samples)
            chunkResults[index] = text
        } catch {
            chunkResults[index] = ""
            logger.error("Chunk \(index) error: \(error.localizedDescription)")
        }
        flushResults()
    }

    private func flushResults() {
        while let text = chunkResults[nextFlushIdx] {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                accumulated += accumulated.isEmpty ? t : " " + t
                transcribedText = accumulated
            }
            chunkResults.removeValue(forKey: nextFlushIdx)
            nextFlushIdx += 1
        }
    }

    private func startLevelTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(64))
        timer.setEventHandler { [weak self] in
            guard let self, let rec = self.recorder else { return }

            // Level meter — floor -70dB so whispers (≈-55dB) show visibly
            let db = rec.averagePower
            let minDb: Float = -70
            let norm = db < minDb ? 0.0 : Double((db - minDb) / (-minDb))
            self.audioLevel = max(0, min(1, norm))

            // Pull new samples and feed Silero VAD in 512-sample windows
            guard let vad = self.vad else { return }
            let newSamples = rec.drainSamples()
            guard !newSamples.isEmpty else { return }

            self.windowBuf.append(contentsOf: newSamples)
            var offset = 0
            while self.windowBuf.count - offset >= SileroVAD.windowSize {
                let end = offset + SileroVAD.windowSize
                let win = Array(self.windowBuf[offset..<end])
                offset = end
                let segs = vad.accept(win)
                for seg in segs where seg.count > 1600 {
                    self.scheduleChunk(seg)
                }
            }
            if offset > 0 { self.windowBuf.removeFirst(offset) }
        }
        timer.resume()
        levelTimer = timer
    }

    private func stopLevelTimer() {
        levelTimer?.cancel()
        levelTimer = nil
    }

    private func defaultInputDeviceID() -> AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return deviceID
    }
}
