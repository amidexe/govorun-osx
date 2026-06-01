import SwiftUI
import AppKit

struct FloatingRecorderView: View {
    @Environment(\.colorScheme) var colorScheme

    @State private var pulse          = false
    @State private var sessionCount:  Int = 0
    @State private var yellowLimit:   Int = WarningSettings.yellowSessions
    @State private var redLimit:      Int = WarningSettings.redSessions
    static let size: CGFloat = 44

    private var birdColor: Color {
        guard WarningSettings.isEnabled else {
            return colorScheme == .dark ? .white : Color(NSColor.secondaryLabelColor)
        }
        if sessionCount >= redLimit    { return .red }
        if sessionCount >= yellowLimit { return Color(red: 1.0, green: 0.5, blue: 0.0) }
        return colorScheme == .dark ? .white : Color(NSColor.secondaryLabelColor)
    }

    var body: some View {
        ZStack {
            CircularBlur(isDark: colorScheme == .dark)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.red.opacity(pulse ? (colorScheme == .dark ? 0.45 : 0.70) : (colorScheme == .dark ? 0.10 : 0.25)), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.size * 0.48
                    )
                )

            BirdLogoView(color: birdColor, size: 18)

        }
        .frame(width: Self.size, height: Self.size)
        .onAppear {
            sessionCount = SessionStats.sessionCountToday
            yellowLimit  = WarningSettings.yellowSessions
            redLimit     = WarningSettings.redSessions
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in
            sessionCount = SessionStats.sessionCountToday
            yellowLimit  = WarningSettings.yellowSessions
            redLimit     = WarningSettings.redSessions
        }
    }
}

private struct CircularBlur: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        CircularEffectView()
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = isDark ? .hudWindow : .popover
    }

    private class CircularEffectView: NSVisualEffectView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            blendingMode = .behindWindow
            state = .active
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            layer?.cornerRadius = bounds.width / 2
            layer?.masksToBounds = true
        }
    }
}
