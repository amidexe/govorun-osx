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
    nonisolated(unsafe) private var modifierPressedAt: UInt64?
    nonisolated(unsafe) private var modifierReleasedAt: UInt64?
    nonisolated(unsafe) private var ignoreEventsUntil: UInt64 = 0
    nonisolated(unsafe) private var suppressPasteEventsUntil: UInt64 = 0
    // True, пока проглочен keyDown нашего хоткея-клавиши и ещё не пришёл парный keyUp.
    // Гарантирует симметрию: keyUp глотаем ТОЛЬКО если проглотили его keyDown.
    // Иначе ОС увидит нажатие, но не увидит отпускания → клавиша «залипнет»
    // (аппаратный автоповтор, переживает выход из приложения).
    nonisolated(unsafe) private var keyHotkeyDown = false
    nonisolated(unsafe) var isRecording = false

    nonisolated private static let modifierInterruptionWindowNanos: UInt64 = 1_000_000_000
    nonisolated private static let modifierBounceWindowNanos: UInt64 = 120_000_000

    var isActive: Bool { eventTap != nil }

    func reloadConfig() {
        cfg = HotkeyConfig.stored
        cancelCfg = HotkeyConfig.cancelStored ?? HotkeyConfig.defaultCancel
        modifierIsDown = false
        modifierPressedAt = nil
        modifierReleasedAt = nil
        keyHotkeyDown = false
    }

    @discardableResult
    func start() -> Bool {
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
            return false
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = src
        armAfterTapChange(seconds: 1.0)
        logger.info("HotkeyManager started: \(self.cfg.displayString)")
        return true
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
        modifierPressedAt = nil
        modifierReleasedAt = nil
        keyHotkeyDown = false
    }

    func suspendForRecorder() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
    func resumeAfterRecorder() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        modifierIsDown = false
        modifierPressedAt = nil
        modifierReleasedAt = nil
        armAfterTapChange(seconds: 0.3)
        // keyHotkeyDown НЕ сбрасываем здесь: если клавиша ещё зажата, тап
        // продолжит глотать автоповтор. Флаг обнулится сам, когда придёт keyUp.
    }

    func suppressSyntheticPasteEvents(seconds: Double = 0.25) {
        let nanos = UInt64(seconds * 1_000_000_000)
        suppressPasteEventsUntil = DispatchTime.now().uptimeNanoseconds + nanos
    }

    // MARK: - Event handler

    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                armAfterTapChange(seconds: 1.0)
            }
            return Unmanaged.passUnretained(event)
        }

        if DispatchTime.now().uptimeNanoseconds < suppressPasteEventsUntil,
           isSyntheticPasteEvent(type: type, event: event) {
            return Unmanaged.passUnretained(event)
        }

        if DispatchTime.now().uptimeNanoseconds < ignoreEventsUntil {
            modifierIsDown = false
            modifierPressedAt = nil
            modifierReleasedAt = nil
            keyHotkeyDown = false
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
            // Не наш аккорд (нет нужных модификаторов или есть лишние) — пропускаем
            // как обычную клавишу и НЕ помечаем как проглоченную.
            guard flags.isSuperset(of: mods),
                  flags.intersection(excl).isEmpty
            else { return Unmanaged.passUnretained(event) }

            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                // Автоповтор клавиши, которой мы уже владеем, — продолжаем глотать.
                return keyHotkeyDown ? nil : Unmanaged.passUnretained(event)
            }
            keyHotkeyDown = true
            Task { @MainActor in self.onKeyDown?() }
            return nil
        }

        // keyUp: глотаем ТОЛЬКО если проглотили парный keyDown. Иначе ОС не увидит
        // отпускания и клавиша залипнет (бесконечный автоповтор).
        guard keyHotkeyDown else { return Unmanaged.passUnretained(event) }
        keyHotkeyDown = false
        Task { @MainActor in self.onKeyUp?() }
        return nil
    }

    nonisolated private func handleModifierOnly(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown && modifierIsDown {
            let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if !HotkeyConfig.isModifierKeyCode(kc) {
                if shouldAbortModifierShortcutForChord() {
                    modifierIsDown = false
                    modifierPressedAt = nil
                    modifierReleasedAt = nil
                    Task { @MainActor in self.onKeyAborted?() }
                }
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
            let now = DispatchTime.now().uptimeNanoseconds
            if let modifierReleasedAt,
               now - modifierReleasedAt < Self.modifierBounceWindowNanos {
                return nil
            }
            modifierIsDown = true
            modifierPressedAt = now
            Task { @MainActor in self.onKeyDown?() }
            return nil
        } else {
            if kc == cfg.keyCode {
                guard !cgFlags.contains(expected) else {
                    return nil
                }
                modifierIsDown = false
                modifierPressedAt = nil
                modifierReleasedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in self.onKeyUp?() }
                return nil
            }
            // Не глотаем события других модификаторов — иначе их состояние
            // зависнет в ОС и последующий ввод станет непредсказуемым.
            return Unmanaged.passUnretained(event)
        }
    }

    nonisolated private func armAfterTapChange(seconds: Double) {
        let nanos = UInt64(seconds * 1_000_000_000)
        ignoreEventsUntil = DispatchTime.now().uptimeNanoseconds + nanos
    }

    nonisolated private func shouldAbortModifierShortcutForChord() -> Bool {
        guard let modifierPressedAt else { return true }
        let elapsed = DispatchTime.now().uptimeNanoseconds - modifierPressedAt
        return elapsed <= Self.modifierInterruptionWindowNanos
    }

    nonisolated private func isSyntheticPasteEvent(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isCommand = keyCode == 0x37
        if type == .flagsChanged {
            return isCommand
        }
        guard type == .keyDown || type == .keyUp else { return false }
        return isCommand || keyCode == 0x09
    }
}
