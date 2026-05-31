import AppKit
import CoreGraphics

enum PasteManager {
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard let src = CGEventSource(stateID: .hidSystemState) else { return }

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

        cmdDown?.flags = .maskCommand
        vDown?.flags   = .maskCommand
        vUp?.flags     = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
