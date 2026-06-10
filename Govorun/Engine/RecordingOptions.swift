import CoreAudio
import Foundation
import AppKit

enum RecordingOptions {
    static var muteAudioDuringRecording: Bool {
        get { UserDefaults.standard.bool(forKey: "muteAudioDuringRecording") }
        set { UserDefaults.standard.set(newValue, forKey: "muteAudioDuringRecording") }
    }

    /// Максимальная длительность одной записи в минутах. 0 = без ограничения.
    /// По достижении запись автоматически останавливается и распознаётся.
    static var maxRecordingMinutes: Int {
        get { let v = UserDefaults.standard.object(forKey: "maxRecordingMinutes"); return (v as? Int) ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "maxRecordingMinutes") }
    }

    /// Короткий звук на старте и завершении записи — чтобы на слух понимать,
    /// включена запись или нет (часто забывается выключенной).
    static var playRecordingSounds: Bool {
        get { UserDefaults.standard.object(forKey: "playRecordingSounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "playRecordingSounds") }
    }
}

/// Звук-индикатор записи: мягкий щелчок на базе «Tink» — обрезан по хвосту,
/// громкость 70%. Старт — 1 щелчок, стоп — 2 одинаковых щелчка («тук-тук»).
enum RecordingSound {
    // Держим NSSound в статике: временный NSSound(named:) освобождается до конца
    // воспроизведения — отсюда «иногда играет, иногда нет». Громкость −30%.
    private static let sound: NSSound? = {
        let s = NSSound(named: "Tink")
        s?.volume = 0.7
        return s
    }()
    private static let clipLength = 0.14   // обрезаем звонкий хвост → мягкий щелчок

    static func playStart() {
        guard RecordingOptions.playRecordingSounds else { return }
        click()
    }

    static func playStop() {
        guard RecordingOptions.playRecordingSounds else { return }
        click()
        // Оба щелчка обрезаются до clipLength → одинаково мягкие, симметричное «тук-тук».
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { click() }
    }

    // Играем щелчок и через clipLength обрываем — чтобы не звенел длинный хвост.
    private static func click() {
        guard let s = sound else { return }
        s.stop()
        s.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + clipLength) {
            if s.isPlaying { s.stop() }
        }
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
