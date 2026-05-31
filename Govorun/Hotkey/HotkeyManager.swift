import AppKit
import CoreGraphics
import ApplicationServices
import os

@MainActor
final class HotkeyManager {
    var onKeyDown:    (() -> Void)?
    var onKeyUp:      (() -> Void)?
    var onKeyAborted: (() -> Void)?
    var onCancel:     (() -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.govorun.app", category: "HotkeyManager")

    nonisolated(unsafe) private var eventTap:      CFMachPort?
    nonisolated(unsafe) private var cfg:           HotkeyConfig = HotkeyConfig.stored
    nonisolated(unsafe) private var cancelCfg:     HotkeyConfig = HotkeyConfig.cancelStored ?? HotkeyConfig.defaultCancel
    nonisolated(unsafe) private var modifierIsDown = false
    nonisolated(unsafe) var isRecording = false

    func reloadConfig() {
        cfg = HotkeyConfig.stored
        cancelCfg = HotkeyConfig.cancelStored ?? HotkeyConfig.defaultCancel
        modifierIsDown = false
    }

    func start() {
        stop()
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)     |
            (1 << CGEventType.keyUp.rawValue)       |
            (1 << CGEventType.flagsChanged.rawValue)
        let selfRef = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info -> Unmanaged<CGEvent>? in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<HotkeyManager>.fromOpaque(info)
                    .takeUnretainedValue().handle(type: type, event: event)
            },
            userInfo: selfRef
        ) else {
            logger.error("CGEvent tap failed — check Accessibility permission")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = src
        logger.info("HotkeyManager started: \(self.cfg.displayString)")
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        modifierIsDown = false
    }

    func suspendForRecorder() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
    func resumeAfterRecorder() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        modifierIsDown = false
    }

    // MARK: - Event handler

    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown && isRecording {
            let cc    = cancelCfg
            let kc    = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let mods  = cc.cgModifiers
            let excl  = CGEventFlags([.maskCommand, .maskControl, .maskAlternate, .maskShift]).subtracting(mods)
            if kc == Int64(cc.keyCode) && flags.isSuperset(of: mods) && flags.intersection(excl).isEmpty {
                Task { @MainActor in self.onCancel?() }
                return nil
            }
        }

        switch cfg.kind {
        case .key:          return handleKey(type: type, event: event)
        case .modifierOnly: return handleModifierOnly(type: type, event: event)
        }
    }

    nonisolated private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

        let kc    = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let mods  = cfg.cgModifiers
        let excl  = CGEventFlags([.maskCommand, .maskControl, .maskAlternate, .maskShift]).subtracting(mods)

        guard kc == Int64(cfg.keyCode) else { return Unmanaged.passUnretained(event) }

        if type == .keyDown {
            guard flags.isSuperset(of: mods)       else { return Unmanaged.passUnretained(event) }
            guard flags.intersection(excl).isEmpty  else { return Unmanaged.passUnretained(event) }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            Task { @MainActor in self.onKeyDown?() }
            return nil
        }
        Task { @MainActor in self.onKeyUp?() }
        return nil
    }

    nonisolated private func handleModifierOnly(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown && modifierIsDown {
            let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if !HotkeyConfig.isModifierKeyCode(kc) {
                modifierIsDown = false
                Task { @MainActor in self.onKeyAborted?() }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

        let kc       = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let cgFlags  = event.flags
        let expected = cfg.cgModifiers

        if !modifierIsDown {
            guard kc == cfg.keyCode else { return Unmanaged.passUnretained(event) }
            guard cgFlags.contains(expected) else { return Unmanaged.passUnretained(event) }
            modifierIsDown = true
            Task { @MainActor in self.onKeyDown?() }
            return nil
        } else {
            if kc == cfg.keyCode {
                modifierIsDown = false
                Task { @MainActor in self.onKeyUp?() }
            }
            return nil
        }
    }
}
