import Foundation
import SwiftUI

enum WarningZone: Equatable { case green, yellow, red }

enum WarningSettings {
    private static let d = UserDefaults.standard

    static var isEnabled: Bool {
        get { d.bool(forKey: "warningsEnabled") }
        set { d.set(newValue, forKey: "warningsEnabled") }
    }
    // Напоминание об отдыхе считается по минутам речи за день.
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
        if minutes >= redMinutes { return .red }
        if minutes >= yellowMinutes { return .yellow }
        return .green
    }
}

// MARK: - Info sheet

struct VoiceZonesInfoView: View {
    @Environment(\.dismiss) var dismiss
    @State private var yellow: Int = WarningSettings.yellowMinutes
    @State private var red: Int = WarningSettings.redMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: GovorunTheme.blue))
                    .frame(width: 28, height: 28)
                    .background(Color(nsColor: GovorunTheme.blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Напоминание об отдыхе")
                        .font(.system(size: 15, weight: .semibold))
                    Text("По суммарному времени речи за день")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }

            Text("Говорун считает минуты речи за день и меняет цвет птички, когда пора сделать паузу.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ZoneInfoRow(
                    color: Color(nsColor: GovorunTheme.green),
                    title: "Спокойно",
                    range: "до \(yellow) мин",
                    detail: "Можно продолжать в обычном темпе."
                )
                ZoneInfoRow(
                    color: Color(nsColor: GovorunTheme.amber),
                    title: "Пора на паузу",
                    range: "\(yellow)-\(red) мин",
                    detail: "Лучше ненадолго отойти и вернуться к диктовке позже."
                )
                ZoneInfoRow(
                    color: Color(nsColor: GovorunTheme.red),
                    title: "Нужен отдых",
                    range: "\(red)+ мин",
                    detail: "Диктовок за день уже много, стоит сделать настоящий перерыв."
                )
            }

            Text("Пороги можно настроить под свой темп.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 380)
        .background(GovorunTheme.pageBackground)
        .onAppear {
            yellow = WarningSettings.yellowMinutes
            red = WarningSettings.redMinutes
        }
    }
}

private struct ZoneInfoRow: View {
    let color: Color
    let title: String
    let range: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(range)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule())
                    Spacer(minLength: 0)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(GovorunTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}
