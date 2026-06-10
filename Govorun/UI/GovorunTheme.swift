import SwiftUI
import AppKit

enum GovorunTheme {
    static var pageBackground: Color { Color(nsColor: pageBackgroundColor) }
    static var sidebarBackground: Color { Color(nsColor: sidebarBackgroundColor) }
    static var surface: Color { Color(nsColor: surfaceColor) }
    static var elevatedSurface: Color { Color(nsColor: elevatedSurfaceColor) }
    static var fieldSurface: Color { Color(nsColor: fieldSurfaceColor) }
    static var stroke: Color { Color(nsColor: strokeColor) }
    static var quietStroke: Color { Color(nsColor: quietStrokeColor) }

    static let blue = NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.92, alpha: 1)
    static let green = NSColor(calibratedRed: 0.18, green: 0.56, blue: 0.34, alpha: 1)
    static let amber = NSColor(calibratedRed: 0.82, green: 0.48, blue: 0.10, alpha: 1)
    static let red = NSColor(calibratedRed: 0.82, green: 0.18, blue: 0.20, alpha: 1)

    private static let pageBackgroundColor = adaptive(light: 1.00, dark: 0.145)
    private static let sidebarBackgroundColor = adaptive(light: 0.965, dark: 0.115)
    private static let surfaceColor = adaptive(light: 1.00, dark: 0.105)
    private static let elevatedSurfaceColor = adaptive(light: 1.00, dark: 0.135)
    private static let fieldSurfaceColor = adaptive(light: 1.00, dark: 0.085)
    private static let strokeColor = adaptive(light: 0.82, dark: 0.28)
    private static let quietStrokeColor = adaptive(light: 0.90, dark: 0.20)

    private static func adaptive(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.aqua, .darkAqua])
            let value = best == .darkAqua ? dark : light
            return NSColor(calibratedWhite: value, alpha: 1)
        }
    }
}

extension View {
    func govorunSurface(cornerRadius: CGFloat = 8) -> some View {
        background(
            GovorunTheme.surface,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(GovorunTheme.quietStroke, lineWidth: 1)
        )
    }

    func govorunFieldSurface(cornerRadius: CGFloat = 8) -> some View {
        background(
            GovorunTheme.fieldSurface,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(GovorunTheme.stroke, lineWidth: 1)
        )
    }
}

struct GovorunSheetHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: NSColor
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: NSColor = GovorunTheme.blue,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: tint))
                .frame(width: 30, height: 30)
                .background(
                    Color(nsColor: tint).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GovorunTheme.elevatedSurface)
    }
}

struct GovorunCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .keyboardShortcut(.cancelAction)
        .help("Закрыть")
    }
}
