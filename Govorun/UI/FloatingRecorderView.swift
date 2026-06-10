import SwiftUI
import AppKit

/// Активна ли запись (окно показано). Держим это состояние отдельно от окна,
/// чтобы индикатор не выполнял лишнюю работу, когда запись не идёт.
final class RecorderVisibility: ObservableObject {
    @Published var isActive = false
}

struct FloatingRecorderView: View {
    @ObservedObject var visibility: RecorderVisibility
    @Environment(\.colorScheme) var colorScheme

    @State private var minutesToday:  Int = 0
    @State private var yellowLimit:   Int = WarningSettings.yellowMinutes
    @State private var redLimit:      Int = WarningSettings.redMinutes
    static let size: CGFloat = 44

    private var birdColor: Color {
        guard WarningSettings.isEnabled else {
            return colorScheme == .dark ? .white : Color(NSColor.secondaryLabelColor)
        }
        if minutesToday >= redLimit    { return Color(nsColor: GovorunTheme.red) }
        if minutesToday >= yellowLimit { return Color(nsColor: GovorunTheme.amber) }
        return colorScheme == .dark ? .white : Color(NSColor.secondaryLabelColor)
    }

    var body: some View {
        ZStack {
            CircularBlur(isDark: colorScheme == .dark)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.red.opacity(visibility.isActive ? (colorScheme == .dark ? 0.32 : 0.48) : 0),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.size * 0.48
                    )
                )

            BirdLogoView(color: birdColor, size: 18)

        }
        .frame(width: Self.size, height: Self.size)
        .onAppear {
            minutesToday = SessionStats.secondsToday / 60
            yellowLimit  = WarningSettings.yellowMinutes
            redLimit     = WarningSettings.redMinutes
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in
            minutesToday = SessionStats.secondsToday / 60
            yellowLimit  = WarningSettings.yellowMinutes
            redLimit     = WarningSettings.redMinutes
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
