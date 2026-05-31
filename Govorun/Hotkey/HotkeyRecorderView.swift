import SwiftUI
import AppKit
import Carbon.HIToolbox
import CoreGraphics

// MARK: - Main view

struct HotkeyRecorderView: View {
    @Binding var config: HotkeyConfig
    var onChanged: () -> Void = {}

    @StateObject private var model = HotkeyRecorderModel()

    var body: some View {
        Button { toggle() } label: {
            HotkeyVisualization(tokens: displayTokens, isRecording: model.isRecording)
        }
        .buttonStyle(.plain)
        .onDisappear { model.cancel() }
    }

    private var displayTokens: [String] {
        model.isRecording ? model.previewTokens : config.displayTokens
    }

    private func toggle() {
        let save: (HotkeyConfig) -> Void = { [self] newConfig in
            config = newConfig
            onChanged()
        }
        if model.isRecording {
            // Re-click while recording: if a modifier-only key is previewed, save it; otherwise cancel
            model.cancelOrCommit(onCapture: save)
        } else {
            model.start(onCapture: save)
        }
    }
}

// MARK: - Key caps visualization

private struct HotkeyVisualization: View {
    let tokens: [String]
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 4) {
            if tokens.isEmpty && isRecording {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                Text("Нажмите клавишу…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                ForEach(tokens, id: \.self) { KeyCapView(title: $0, isRecording: isRecording) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(minWidth: 130, minHeight: 28)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(isRecording ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

private struct KeyCapView: View {
    let title: String
    let isRecording: Bool
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(NSColor.textBackgroundColor))
            .padding(.horizontal, 5).frame(minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.labelColor)))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(isRecording ? Color.accentColor.opacity(0.6)
                                    : Color(NSColor.textBackgroundColor).opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Recording model

@MainActor
final class HotkeyRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var previewTokens: [String] = []

    // CGEvent tap — system-level, works regardless of window focus
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    private var onCapture: ((HotkeyConfig) -> Void)?
    private var pendingModifierConfig: HotkeyConfig?
    private var peakModifiers: NSEvent.ModifierFlags = []

    deinit {
        removeTap()
    }

    func start(onCapture: @escaping (HotkeyConfig) -> Void) {
        cancel()
        self.onCapture = onCapture
        isRecording = true
        previewTokens = []
        peakModifiers = []
        pendingModifierConfig = nil
        hotkeyManager?.suspendForRecorder()
        installTap()
    }

    func cancel() {
        removeTap()
        hotkeyManager?.resumeAfterRecorder()
        isRecording = false
        previewTokens = []
        peakModifiers = []
        pendingModifierConfig = nil
        onCapture = nil
    }

    var hotkeyManager: HotkeyManager? {
        (NSApplication.shared.delegate as? AppDelegate)?.hotkeyManager
    }

    func cancelOrCommit(onCapture: @escaping (HotkeyConfig) -> Void) {
        if let pending = pendingModifierConfig {
            self.onCapture = onCapture
            finish(with: pending)
        } else {
            cancel()
        }
    }

    private func finish(with cfg: HotkeyConfig) {
        let capture = onCapture
        removeTap()
        hotkeyManager?.resumeAfterRecorder()
        isRecording = false
        previewTokens = []
        peakModifiers = []
        pendingModifierConfig = nil
        onCapture = nil
        capture?(cfg)
    }

    // Called on MainActor via Task from the CGEvent tap callback
    func dispatchEvent(type: CGEventType, kc: UInt16, cgFlags: CGEventFlags) {
        guard isRecording else { return }
        let mods = cgFlags.nsModifierFlags
        switch type {
        case .keyDown:      handleKeyDown(kc: kc, mods: mods)
        case .flagsChanged: handleFlagsChanged(kc: kc, mods: mods)
        default:            break
        }
    }

    // MARK: - CGEvent tap

    private func installTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let selfRef = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info -> Unmanaged<CGEvent>? in
                guard let info else { return Unmanaged.passUnretained(event) }
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let r = Unmanaged<HotkeyRecorderModel>.fromOpaque(info).takeUnretainedValue()
                    if let tap = r.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let recorder = Unmanaged<HotkeyRecorderModel>.fromOpaque(info).takeUnretainedValue()
                let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let cgFlags = event.flags
                Task { @MainActor [recorder] in
                    recorder.dispatchEvent(type: type, kc: kc, cgFlags: cgFlags)
                }
                return nil  // consume all keyboard events while recording
            },
            userInfo: selfRef
        ) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = src
    }

    nonisolated private func removeTap() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    // MARK: keyDown

    private func handleKeyDown(kc: UInt16, mods: NSEvent.ModifierFlags) {
        if kc == UInt16(kVK_Escape) && mods.isEmpty { cancel(); return }
        if HotkeyConfig.isModifierKeyCode(kc) { return }

        let cfg = HotkeyConfig.key(kc, mods)
        if cfg.isValid {
            pendingModifierConfig = nil
            finish(with: cfg)
        }
    }

    // MARK: flagsChanged — live modifier preview + modifier-only detection

    private func handleFlagsChanged(kc: UInt16, mods: NSEvent.ModifierFlags) {
        if mods.isEmpty {
            if let pending = pendingModifierConfig {
                finish(with: pending)
                return
            }
            previewTokens = []
        } else {
            peakModifiers.formUnion(mods)
            previewTokens = mods.shortcutDisplayTokens

            if HotkeyConfig.isModifierKeyCode(kc) {
                let candidate = HotkeyConfig.modifierOnly(kc, peakModifiers)
                pendingModifierConfig = candidate
            }
        }
    }
}

// MARK: - CGEventFlags → NSEvent.ModifierFlags

private extension CGEventFlags {
    var nsModifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.maskControl)   { f.insert(.control) }
        if contains(.maskAlternate) { f.insert(.option) }
        if contains(.maskShift)     { f.insert(.shift) }
        if contains(.maskCommand)   { f.insert(.command) }
        return f
    }
}
