import AppKit
import SwiftUI

@MainActor
final class FloatingWindowController: NSWindowController {

    private let visibility = RecorderVisibility()

    convenience init() {
        let s = FloatingRecorderView.size

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: s, height: s),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        self.init(window: panel)

        let view = FloatingRecorderView(visibility: visibility)
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        positionPanel()
    }

    func show() {
        NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
        visibility.isActive = true          // запускает pulse-анимацию
        positionPanel()
        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window?.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.visibility.isActive = false   // останавливает pulse — нет фоновой нагрузки
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main, let w = window else { return }
        let frame = screen.visibleFrame
        let wSize = w.frame.size
        let x = frame.midX - wSize.width / 2
        let y = frame.minY + 24
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
