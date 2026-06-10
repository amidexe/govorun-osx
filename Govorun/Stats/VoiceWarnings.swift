import Foundation
import SwiftUI

enum WarningZone: Equatable { case green, yellow, red }

enum WarningSettings {
    private static let d = UserDefaults.standard

    static var isEnabled: Bool {
        get { d.bool(forKey: "warningsEnabled") }
        set { d.set(newValue, forKey: "warningsEnabled") }
    }
    // Зоны усталости — по минутам речи за день (устаёшь от времени, а не от числа нажатий).
    static var yellowMinutes: Int {
        get { let v = d.integer(forKey: "warningYellowMin"); return v == 0 ? 60 : v }
        set { d.set(newValue, forKey: "warningYellowMin") }
    }
    static var redMinutes: Int {
        get { let v = d.integer(forKey: "warningRedMin"); return v == 0 ? 90 : v }
        set { d.set(newValue, forKey: "warningRedMin") }
    }

    static func zone(minutes: Int) -> WarningZone {
        guard isEnabled else { return .green }
        if minutes >= redMinutes    { return .red }
        if minutes >= yellowMinutes { return .yellow }
        return .green
    }
}

// MARK: - Info sheet

struct VoiceZonesInfoView: View {
    @Environment(\.dismiss) var dismiss
    @State private var yellow: Int = WarningSettings.yellowMinutes
    @State private var red:    Int = WarningSettings.redMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Голосовые зоны").font(.headline)
                Spacer()
                Button("Закрыть") { dismiss() }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            }
            Text("Усталость голоса и внимания накапливается от времени речи за день, а не от числа диктовок. Зоны считают суммарные минуты речи.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("🟢  до \(yellow) мин — продуктивная зона, голос и внимание свежие")
                Text("🟡  \(yellow)–\(red) мин — накапливается усталость, формулировки хуже")
                Text("🔴  \(red)+ мин — нужен перерыв, голос и рабочая память перегружены")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("Пороги — ваши настройки. Наука задаёт принцип, цифры подбирайте под свой темп.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            yellow = WarningSettings.yellowMinutes
            red    = WarningSettings.redMinutes
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
