import SwiftUI
import AppKit

/// Активна ли запись (окно показано). Гейтит pulse-анимацию, чтобы она не
/// крутилась 24/7 в фоне и не жгла CPU, когда запись не идёт.
final class RecorderVisibility: ObservableObject {
    @Published var isActive = false
}

struct FloatingRecorderView: View {
    @ObservedObject var visibility: RecorderVisibility
    @Environment(\.colorScheme) var colorScheme

    @State private var pulse          = false
    @State private var minutesToday:  Int = 0
    @State private var yellowLimit:   Int = WarningSettings.yellowMinutes
    @State private var redLimit:      Int = WarningSettings.redMinutes
    static let size: CGFloat = 44

    private var birdColor: Color {
        guard WarningSettings.isEnabled else {
            return colorScheme == .dark ? .white : Color(NSColor.secondaryLabelColor)
        }
        if minutesToday >= redLimit    { return .red }
        if minutesToday >= yellowLimit { return Color(red: 1.0, green: 0.5, blue: 0.0) }
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
            minutesToday = SessionStats.secondsToday / 60
            yellowLimit  = WarningSettings.yellowMinutes
            redLimit     = WarningSettings.redMinutes
            updatePulse(visibility.isActive)
        }
        .onChange(of: visibility.isActive) { updatePulse($0) }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in
            minutesToday = SessionStats.secondsToday / 60
            yellowLimit  = WarningSettings.yellowMinutes
            redLimit     = WarningSettings.redMinutes
        }
    }

    // Pulse крутится ТОЛЬКО когда окно показано (идёт запись). Иначе анимация
    // остановлена — нет фоновой нагрузки на CPU.
    private func updatePulse(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { pulse = false }
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
