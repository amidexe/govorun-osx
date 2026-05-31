import Foundation
import SwiftUI

enum WarningZone: Equatable { case green, yellow, red }

enum WarningSettings {
    private static let d = UserDefaults.standard

    static var isEnabled: Bool {
        get { d.bool(forKey: "warningsEnabled") }
        set { d.set(newValue, forKey: "warningsEnabled") }
    }
    static var yellowSessions: Int {
        get { let v = d.integer(forKey: "warningYellow"); return v == 0 ? 50 : v }
        set { d.set(newValue, forKey: "warningYellow") }
    }
    static var redSessions: Int {
        get { let v = d.integer(forKey: "warningRed"); return v == 0 ? 80 : v }
        set { d.set(newValue, forKey: "warningRed") }
    }

    static func zone(sessions: Int) -> WarningZone {
        guard isEnabled else { return .green }
        if sessions >= redSessions    { return .red }
        if sessions >= yellowSessions { return .yellow }
        return .green
    }
}

// MARK: - Info sheet

struct VoiceZonesInfoView: View {
    @Environment(\.dismiss) var dismiss
    @State private var yellow: Int = WarningSettings.yellowSessions
    @State private var red:    Int = WarningSettings.redSessions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Голосовые зоны").font(.headline)
                Spacer()
                Button("Закрыть") { dismiss() }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            }
            Text("Каждая диктовка — отдельный когнитивный акт. Их количество за день определяет нагрузку на мозг, а не время записи.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("🟢  до \(yellow) сессий — продуктивная зона, мозг справляется легко")
                Text("🟡  \(yellow)–\(red) сессий — накапливается усталость, формулировки хуже")
                Text("🔴  \(red)+ сессий — нужен перерыв, рабочая память перегружена")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("Пороги — ваши настройки. Наука задаёт принцип, цифры подбирайте под свой темп.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            yellow = WarningSettings.yellowSessions
            red    = WarningSettings.redSessions
        }
    }
}

private struct ZoneCard: View {
    let color:    Color
    let icon:     String
    let title:    String
    let subtitle: String
    let detail:   String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
                .cornerRadius(2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(icon)
                    Text(title).font(.headline)
                    Spacer()
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color.opacity(0.12))
                        .cornerRadius(4)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }
}
