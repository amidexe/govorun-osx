import SwiftUI

struct LicensesView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GovorunSheetHeader(
                title: "Лицензии",
                subtitle: "Сторонние компоненты и исходный код",
                systemImage: "scroll"
            ) {
                GovorunCloseButton { dismiss() }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(License.all, id: \.name) { lic in
                        LicenseRow(license: lic)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Говорун для macOS")
                                .font(.system(size: 13, weight: .semibold))
                            Text("MIT")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Spacer(minLength: 0)
                        }
                        Text("Copyright (c) 2026 amidexe")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Link("https://github.com/amidexe/govorun-osx",
                             destination: URL(string: "https://github.com/amidexe/govorun-osx")!)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .govorunSurface()
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 480)
        .background(GovorunTheme.pageBackground)
    }
}

private struct LicenseRow: View {
    let license: License

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(license.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(license.spdx)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                Spacer(minLength: 0)

                Link(destination: URL(string: license.url)!) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(license.url)
            }

            Text(license.copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .govorunSurface()
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
