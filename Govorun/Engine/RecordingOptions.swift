import CoreAudio
import Foundation

enum RecordingOptions {
    static var muteAudioDuringRecording: Bool {
        get { UserDefaults.standard.bool(forKey: "muteAudioDuringRecording") }
        set { UserDefaults.standard.set(newValue, forKey: "muteAudioDuringRecording") }
    }
}

@MainActor
final class SystemAudioMuter {
    private var didMute      = false
    private var wasAlreadyMuted = false

    func muteIfNeeded() {
        guard RecordingOptions.muteAudioDuringRecording else { return }
        let already = isSystemAudioMuted()
        if already { wasAlreadyMuted = true; didMute = false }
        else { wasAlreadyMuted = false; didMute = setSystemMuted(true) }
    }

    func unmuteIfNeeded() {
        guard didMute && !wasAlreadyMuted else { didMute = false; wasAlreadyMuted = false; return }
        setSystemMuted(false)
        didMute = false; wasAlreadyMuted = false
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var id: AudioDeviceID = 0
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &id) == noErr ? id : nil
    }

    private func isSystemAudioMuted() -> Bool {
        guard let id = defaultOutputDevice() else { return false }
        var muted: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if !AudioObjectHasProperty(id, &addr) { addr.mElement = 0; if !AudioObjectHasProperty(id, &addr) { return false } }
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &sz, &muted) == noErr && muted != 0
    }

    @discardableResult
    private func setSystemMuted(_ muted: Bool) -> Bool {
        guard let id = defaultOutputDevice() else { return false }
        var val: UInt32 = muted ? 1 : 0
        let sz = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if !AudioObjectHasProperty(id, &addr) { addr.mElement = 0; if !AudioObjectHasProperty(id, &addr) { return false } }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        return AudioObjectSetPropertyData(id, &addr, 0, nil, sz, &val) == noErr
    }
}
