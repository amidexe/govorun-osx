import SwiftUI

struct LicensesView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Лицензии").font(.headline)
                Spacer()
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(License.all, id: \.name) { lic in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(lic.name).font(.headline)
                                Text(lic.spdx)
                                    .font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                                Spacer()
                                Link(lic.url, destination: URL(string: lic.url)!)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(lic.copyright)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Говорун для macOS").font(.headline)
                        Text("MIT License — Copyright (c) 2025 amidexe")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("https://github.com/amidexe/govorun-osx",
                             destination: URL(string: "https://github.com/amidexe/govorun-osx")!)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 420)
    }
}

private struct License {
    let name: String
    let spdx: String
    let copyright: String
    let url: String

    static let all: [License] = [
        License(
            name: "GigaAM v3",
            spdx: "Apache-2.0",
            copyright: "Copyright © 2024 SaluteSpeech (Сбер)",
            url: "https://github.com/salute-developers/GigaAM"
        ),
        License(
            name: "sherpa-onnx v1.13.1",
            spdx: "Apache-2.0",
            copyright: "Copyright © 2022–2024 k2-fsa / Next-gen Kaldi Authors",
            url: "https://github.com/k2-fsa/sherpa-onnx"
        ),
        License(
            name: "ONNX Runtime",
            spdx: "MIT",
            copyright: "Copyright © Microsoft Corporation",
            url: "https://github.com/microsoft/onnxruntime"
        ),
        License(
            name: "Silero VAD v4",
            spdx: "MIT",
            copyright: "Copyright © 2021 Silero Team",
            url: "https://github.com/snakers4/silero-vad"
        ),
        License(
            name: "GigaAM v3 ONNX (istupakov)",
            spdx: "MIT",
            copyright: "ONNX-конвертация модели GigaAM v3",
            url: "https://huggingface.co/istupakov/gigaam-v3-onnx"
        ),
    ]
}
