import SwiftUI

struct DictionaryEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var text: String = WordDictionary.toText()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Словарь замен").font(.headline)
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { WordDictionary.fromText(text); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach([
                        ("ё = е",              "символ — везде"),
                        ("дев = dev",          "слово — только целиком"),
                        ("опен эй ай = OpenAI","фраза — везде"),
                        ("кхм =",             "пустая замена — удаляет"),
                    ], id: \.0) { example, comment in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(example)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 200, alignment: .leading)
                            Text(comment)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("# это комментарий")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Spacer()
            }
        }
        .frame(width: 480, height: 430)
    }
}
