import Foundation
import CoreAudio
import AVFoundation
import os

@MainActor
final class AudioEngine: ObservableObject {
    enum State { case idle, recording, processing }

    struct RecognitionJob {
        fileprivate let tasks: [Task<RecognitionChunk, Never>]
        let speechSamples: Int

        var isEmpty: Bool { tasks.isEmpty }
        var chunkCount: Int { tasks.count }
    }

    fileprivate struct RecognitionChunk {
        let index: Int
        let text: String
    }

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
    private var recognizerPreloadStarted = false

    // Streaming transcription
    private var nextChunkIdx     = 0
    private var pendingTasks     = [Task<RecognitionChunk, Never>]()
    // Только реальная речь (VAD-сегменты), без пауз
    private(set) var speechSamples: Int = 0

    func startRecording() async throws {
        guard state == .idle else { return }
        state = .recording
        transcribedText = ""

        // Прерываем отложенную выгрузку. Распознаватель греем только после
        // появления речи, чтобы включенная запись в тишине не жгла CPU.
        idleCleanupTask?.cancel(); idleCleanupTask = nil

        nextChunkIdx  = 0
        pendingTasks  = []
        windowBuf     = []
        recognizerPreloadStarted = false
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

    func stopRecordingForRecognition() -> RecognitionJob {
        guard state == .recording else {
            return RecognitionJob(tasks: [], speechSamples: 0)
        }
        state = .processing
        stopLevelTimer()
        audioLevel = 0

        // Drain remaining PCM from recorder
        let remaining = recorder?.drainSamples() ?? []
        recorder?.stopRecording()
        recorder = nil

        // Feed remaining + flush VAD to get final segment
        if let vad {
            _ = feedSamplesToVAD(remaining)
            // Flush for final segment
            let finalSegs = vad.flushAndDrain()
            for s in finalSegs where s.count > 1600 { scheduleChunk(s) }
        } else if remaining.count > 1600 {
            scheduleChunk(remaining)
        }
        windowBuf = []

        let job = RecognitionJob(tasks: pendingTasks, speechSamples: speechSamples)

        pendingTasks = []
        nextChunkIdx = 0
        speechSamples = 0

        if let url = recordingURL {
            recordingURL = nil
            try? FileManager.default.removeItem(at: url)
        }

        state = .idle
        return job
    }

    func recognize(_ job: RecognitionJob) async -> String {
        let results = await withTaskGroup(of: RecognitionChunk.self) { group in
            for task in job.tasks {
                group.addTask { await task.value }
            }

            var chunks: [RecognitionChunk] = []
            for await chunk in group {
                chunks.append(chunk)
            }
            return chunks.sorted { $0.index < $1.index }
        }

        let result = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        transcribedText = result
        logger.info("Final: \(result.prefix(80))")
        scheduleIdleCleanup()
        return result
    }

    func cancelRecording() {
        guard state == .recording || state == .processing else { return }
        stopLevelTimer()
        audioLevel = 0
        recorder?.stopRecording()
        recorder = nil
        pendingTasks.forEach { $0.cancel() }
        pendingTasks = []
        nextChunkIdx = 0
        windowBuf = []
        speechSamples = 0
        if let url = recordingURL {
            recordingURL = nil
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
        scheduleIdleCleanup()
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
        let recognizer = gigaAM
        let logger = logger
        let task = Task<RecognitionChunk, Never> {
            guard !Task.isCancelled else {
                return RecognitionChunk(index: idx, text: "")
            }
            do {
                let text = try await recognizer.transcribeSamples(samples)
                return RecognitionChunk(index: idx, text: text)
            } catch {
                logger.error("Chunk \(idx) error: \(error.localizedDescription)")
                return RecognitionChunk(index: idx, text: "")
            }
        }
        pendingTasks.append(task)
    }

    @discardableResult
    private func feedSamplesToVAD(_ samples: [Float]) -> Bool {
        guard let vad, !samples.isEmpty else { return false }
        windowBuf.append(contentsOf: samples)

        var offset = 0
        var segments: [[Float]] = []
        windowBuf.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            while buffer.count - offset >= SileroVAD.windowSize {
                let window = UnsafeBufferPointer(
                    start: base.advanced(by: offset),
                    count: SileroVAD.windowSize
                )
                segments.append(contentsOf: vad.accept(window))
                offset += SileroVAD.windowSize
            }
        }

        if offset == windowBuf.count {
            windowBuf.removeAll(keepingCapacity: true)
        } else if offset > 0 {
            windowBuf.removeFirst(offset)
        }

        if vad.isSpeechDetected() {
            preloadRecognizerOnce()
        }

        var emittedSegment = false
        for seg in segments where seg.count > 1600 {
            emittedSegment = true
            scheduleChunk(seg)
        }
        return emittedSegment
    }

    private func preloadRecognizerOnce() {
        guard !recognizerPreloadStarted else { return }
        recognizerPreloadStarted = true
        gigaAM.preload()
    }

    private func startLevelTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, let rec = self.recorder else { return }

            // Level meter — floor -70dB so whispers (≈-55dB) show visibly
            let db = rec.averagePower
            let minDb: Float = -70
            let norm = db < minDb ? 0.0 : Double((db - minDb) / (-minDb))
            self.audioLevel = max(0, min(1, norm))

            // Pull new samples and feed Silero VAD in 512-sample windows
            guard self.vad != nil else { return }
            let newSamples = rec.drainSamples()
            guard !newSamples.isEmpty else { return }
            _ = self.feedSamplesToVAD(newSamples)
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
