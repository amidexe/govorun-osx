import AppKit
import SwiftUI

@MainActor
final class ZoneTransitionWindowController: NSWindowController {

    private var dismissTask: Task<Void, Never>?

    convenience init() {
        let size: CGFloat = 52
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        self.init(window: panel)
    }

    func showZone(_ zone: WarningZone) {
        NSLog("[Zone] showZone called: %@", "\(zone)")
        dismissTask?.cancel()

        let color: Color = zone == .red ? .red : .orange
        let hosting = NSHostingView(rootView: ZoneTransitionView(color: color))
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        window?.contentView = hosting

        positionPanel()
        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 1
        }

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await dismiss()
        }
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main, let w = window else { return }
        let frame = screen.visibleFrame
        let wSize = w.frame.size
        // чуть правее центра, чтобы не перекрывать рекордер
        let x = frame.midX - wSize.width / 2 + 60
        let y = frame.minY + 24
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ZoneTransitionView: View {
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            CircleBlurView(isDark: colorScheme == .dark)
            Circle()
                .fill(color.opacity(0.55))
                .padding(6)
        }
        .frame(width: 52, height: 52)
    }
}

private struct CircleBlurView: NSViewRepresentable {
    let isDark: Bool
    func makeNSView(context: Context) -> NSVisualEffectView { BlurView() }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = isDark ? .hudWindow : .popover
    }
    private class BlurView: NSVisualEffectView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            blendingMode = .behindWindow; state = .active; wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            layer?.cornerRadius = bounds.width / 2
            layer?.masksToBounds = true
        }
    }
}
