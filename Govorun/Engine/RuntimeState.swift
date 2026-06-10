import Foundation

enum RuntimeState {
    private static let d = UserDefaults.standard

    private static let busyKey = "runtimeBusyActive"
    private static let recordingKey = "runtimeRecordingActive"
    private static let pidKey = "runtimeBusyPID"
    private static let recordingPIDKey = "runtimeRecordingPID"
    private static let updatedAtKey = "runtimeBusyUpdatedAt"

    static func setBusy(_ active: Bool) {
        set(microphoneActive: active, busy: active)
    }

    static func set(microphoneActive: Bool, busy: Bool) {
        d.set(busy, forKey: busyKey)
        d.set(microphoneActive, forKey: recordingKey)
        d.set(ProcessInfo.processInfo.processIdentifier, forKey: pidKey)
        d.set(ProcessInfo.processInfo.processIdentifier, forKey: recordingPIDKey)
        d.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
    }
}
