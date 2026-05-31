import Foundation
import CoreAudio
import AudioToolbox
import os

final class CoreAudioRecorder: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.govorun.app", category: "CoreAudioRecorder")

    private var audioUnit: AudioUnit?
    private var audioFile: ExtAudioFileRef?
    private var isRecording = false
    private var deviceFormat = AudioStreamBasicDescription()
    private var outputFormat = AudioStreamBasicDescription()

    private var renderBuffer: UnsafeMutablePointer<Float32>?
    private var renderBufferSize: UInt32 = 0
    private var conversionBuffer: UnsafeMutablePointer<Int16>?
    private var conversionBufferSize: UInt32 = 0

    private let meterLock = NSLock()
    private var _averagePower: Float = -160
    private var _peakPower:    Float = -160

    var averagePower: Float { meterLock.withLock { _averagePower } }
    var peakPower:    Float { meterLock.withLock { _peakPower } }

    private let sampleLock = NSLock()
    private var _sampleBuffer: [Float] = []

    func drainSamples() -> [Float] {
        sampleLock.withLock {
            defer { _sampleBuffer.removeAll(keepingCapacity: true) }
            return _sampleBuffer
        }
    }

    deinit { stopRecording() }

    func startRecording(toOutputFile url: URL, deviceID: AudioDeviceID) throws {
        stopRecording()
        guard deviceID != 0 else { throw Err.badDevice }

        try createAudioUnit()
        try setDevice(deviceID)
        try configureFormats()
        try setupCallback()
        try createOutputFile(at: url)
        try startUnit()
        isRecording = true
        logger.info("Recording started, device=\(deviceID)")
    }

    func stopRecording() {
        guard isRecording || audioUnit != nil else { return }
        if let u = audioUnit { AudioOutputUnitStop(u); AudioComponentInstanceDispose(u); audioUnit = nil }
        if let f = audioFile { ExtAudioFileDispose(f); audioFile = nil }
        renderBuffer?.deallocate();    renderBuffer = nil;    renderBufferSize = 0
        conversionBuffer?.deallocate(); conversionBuffer = nil; conversionBufferSize = 0
        isRecording = false
        meterLock.withLock { _averagePower = -160; _peakPower = -160 }
        sampleLock.withLock { _sampleBuffer.removeAll() }
    }

    // MARK: - Setup

    private func createAudioUnit() throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw Err.unitNotFound }
        var unit: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unit) == noErr, let unit else { throw Err.unitCreate }
        audioUnit = unit

        var one: UInt32 = 1
        var zero: UInt32 = 0
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input,  1, &one,  4), Err.enableInput)
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &zero, 4), Err.disableOutput)
    }

    private func setDevice(_ id: AudioDeviceID) throws {
        guard let u = audioUnit else { throw Err.notInit }
        var dev = id
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)), Err.setDevice)
    }

    private func configureFormats() throws {
        guard let u = audioUnit else { throw Err.notInit }
        var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &deviceFormat, &sz), Err.getFormat)

        outputFormat = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)

        var cbFmt = AudioStreamBasicDescription(
            mSampleRate: deviceFormat.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: deviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &cbFmt,
                                       UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), Err.setFormat)

        let maxFrames: UInt32 = 4096
        let renderSamples = maxFrames * deviceFormat.mChannelsPerFrame
        renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(renderSamples))
        renderBufferSize = renderSamples

        let ratio = outputFormat.mSampleRate / deviceFormat.mSampleRate
        let outFrames = UInt32(Double(maxFrames) * ratio) + 1
        conversionBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(outFrames))
        conversionBufferSize = outFrames
    }

    private func setupCallback() throws {
        guard let u = audioUnit else { throw Err.notInit }
        var cb = AURenderCallbackStruct(inputProc: inputCB, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), Err.setCallback)
    }

    private func createOutputFile(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        var ref: ExtAudioFileRef?
        try check(ExtAudioFileCreateWithURL(url as CFURL, kAudioFileWAVEType, &outputFormat, nil,
                                            AudioFileFlags.eraseFile.rawValue, &ref), Err.createFile)
        audioFile = ref
        try check(ExtAudioFileSetProperty(ref!, kExtAudioFileProperty_ClientDataFormat,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &outputFormat), Err.setFileFormat)
    }

    private func startUnit() throws {
        guard let u = audioUnit else { throw Err.notInit }
        try check(AudioUnitInitialize(u), Err.initialize)
        try check(AudioOutputUnitStart(u), Err.start)
    }

    // MARK: - Callback

    private let inputCB: AURenderCallback = { refCon, flags, ts, bus, frames, _ in
        Unmanaged<CoreAudioRecorder>.fromOpaque(refCon).takeUnretainedValue()
            .handleInput(flags: flags, ts: ts, bus: bus, frames: frames)
    }

    private func handleInput(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                              ts: UnsafePointer<AudioTimeStamp>, bus: UInt32, frames: UInt32) -> OSStatus {
        guard let u = audioUnit, isRecording, let renderBuf = renderBuffer else { return noErr }
        let ch = deviceFormat.mChannelsPerFrame
        guard frames * ch <= renderBufferSize else { return noErr }

        var bl = AudioBufferList(mNumberBuffers: 1,
                                 mBuffers: AudioBuffer(mNumberChannels: ch,
                                                       mDataByteSize: frames * ch * 4,
                                                       mData: renderBuf))
        let status = AudioUnitRender(u, flags, ts, bus, frames, &bl)
        guard status == noErr else { return status }

        updateMeters(buf: &bl, frames: frames)
        writeConverted(buf: &bl, frames: frames)
        return noErr
    }

    private func updateMeters(buf: inout AudioBufferList, frames: UInt32) {
        guard let data = buf.mBuffers.mData else { return }
        let samples = data.assumingMemoryBound(to: Float32.self)
        let ch = Int(deviceFormat.mChannelsPerFrame)
        let total = Int(frames) * ch
        guard total > 0 else { return }
        var sum: Float = 0, peak: Float = 0
        for i in 0..<total { let s = abs(samples[i]); sum += s * s; if s > peak { peak = s } }
        let avg = 20 * log10(max(sqrt(sum / Float(total)), 0.000001))
        let pk  = 20 * log10(max(peak, 0.000001))
        meterLock.withLock { _averagePower = avg; _peakPower = pk }
    }

    private func writeConverted(buf: inout AudioBufferList, frames: UInt32) {
        guard let file = audioFile, let inp = buf.mBuffers.mData, let outBuf = conversionBuffer else { return }
        let inSamples = inp.assumingMemoryBound(to: Float32.self)
        let ch = deviceFormat.mChannelsPerFrame
        let inRate  = deviceFormat.mSampleRate
        let outRate = outputFormat.mSampleRate
        let ratio   = outRate / inRate
        let outFrames = UInt32(Double(frames) * ratio)
        guard outFrames > 0, outFrames <= conversionBufferSize else { return }

        if inRate == outRate {
            for i in 0..<Int(frames) {
                var s: Float32 = 0
                for c in 0..<Int(ch) { s += inSamples[i * Int(ch) + c] }
                s /= Float32(ch)
                outBuf[i] = Int16(max(-32768, min(32767, s * 32767)))
            }
        } else {
            for i in 0..<Int(outFrames) {
                let idx  = Double(i) / ratio
                let idx0 = Int(idx)
                let frac = Float32(idx - Double(idx0))
                let i0 = min(idx0, Int(frames) - 1), i1 = min(idx0 + 1, Int(frames) - 1)
                var s: Float32 = 0
                for c in 0..<Int(ch) {
                    let s0 = inSamples[i0 * Int(ch) + c]
                    let s1 = inSamples[i1 * Int(ch) + c]
                    s += s0 + frac * (s1 - s0)
                }
                s /= Float32(ch)
                outBuf[i] = Int16(max(-32768, min(32767, s * 32767)))
            }
        }

        var outBL = AudioBufferList(mNumberBuffers: 1,
                                    mBuffers: AudioBuffer(mNumberChannels: 1,
                                                          mDataByteSize: outFrames * 2,
                                                          mData: outBuf))
        ExtAudioFileWrite(file, outFrames, &outBL)

        let count = Int(outFrames)
        let floats = (0..<count).map { Float(outBuf[$0]) / 32768.0 }
        sampleLock.withLock { _sampleBuffer.append(contentsOf: floats) }
    }

    // MARK: - Helpers

    private func check(_ status: OSStatus, _ err: Err) throws {
        guard status == noErr else { throw err }
    }

    enum Err: Error {
        case badDevice, unitNotFound, unitCreate, notInit
        case enableInput, disableOutput, setDevice, getFormat, setFormat
        case setCallback, createFile, setFileFormat, initialize, start
    }
}
