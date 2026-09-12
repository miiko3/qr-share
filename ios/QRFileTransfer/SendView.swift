import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var fileName = ""
    @State private var fileInfo = ""
    @State private var qrTexts: [String] = []
    @State private var index = 0
    @State private var playing = false
    @State private var finished = false
    @State private var error: String?
    @State private var speedMs = 500.0
    @State private var qrImage: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("← Назад") { dismiss() }
                Spacer()
                Text("Отправка").font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if qrTexts.isEmpty {
                VStack(spacing: 20) {
                    Text("Выберите файл для отправки (до 100 МБ).\nПоднесите телефоны друг к другу.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Выбрать файл") { showPicker = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(fileName).lineLimit(1).font(.title3)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                }
                Spacer()

                ProgressView(
                    value: Double(min(index, totalSteps)),
                    total: Double(totalSteps)
                )
                Text("Часть \(min(index, totalSteps)) из \(totalSteps) • \(progressPercent)%")
                    .font(.caption)

                HStack {
                    Button(playing ? "Пауза" : "Продолжить") { playing.toggle() }
                    Spacer()
                    if finished {
                        Button("Заново") { reset() }
                    }
                }

                HStack {
                    Text("Скорость")
                    Slider(value: $speedMs, in: 150...2000, step: 50)
                    Text("\(Int(speedMs)) мс")
                }

                if finished {
                    Text("Готово! Все части показаны. Проверьте, что получатель собрал файл.")
                        .foregroundStyle(.green)
                }
                Text(fileInfo).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.item]
        ) { result in
            if case .success(let url) = result {
                load(url)
            }
        }
        .task(id: playing) {
            guard playing, index < qrTexts.count else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(speedMs) * 1_000_000)
                if Task.isCancelled { return }
                index += 1
                if index >= totalSteps { break }
            }
            if index >= totalSteps {
                playing = false
                finished = true
                error = nil
            }
        }
        .task(id: QrTaskKey(qrTexts, index)) {
            guard index < qrTexts.count else { return }
            qrImage = QrGenerator.image(from: qrTexts[index])
        }
    }

    private var totalSteps: Int { max(qrTexts.count - 1, 1) }

    private var progressPercent: String {
        let p = Int(Double(min(index, totalSteps)) / Double(totalSteps) * 100)
        return "\(min(p, 100))%"
    }

    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count > 0 else {
                error = "Пустой файл"
                return
            }
            guard data.count <= QrProtocol.maxFileSize else {
                error = "Файл больше 100 МБ"
                return
            }
            let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
            let sid = QrProtocol.newSessionId()
            let total = QrProtocol.chunkCount(for: Int64(data.count))
            let sha = QrProtocol.sha256Hex(data)

            let header = QrProtocol.buildHeader(
                sid: sid,
                name: name,
                mime: "application/octet-stream",
                size: Int64(data.count),
                sha: sha,
                total: total
            )

            var texts: [String] = [header]
            for i in 1...total {
                let from = (i - 1) * QrProtocol.chunkRawSize
                let to = min(from + QrProtocol.chunkRawSize, data.count)
                let slice = data.subdata(in: from..<to)
                texts.append(QrProtocol.buildData(
                    sid: sid,
                    index: i,
                    raw: slice,
                    crc: QrProtocol.crc32Value(slice)
                ))
            }
            qrTexts = texts
            fileName = name
            fileInfo = "\(data.count / 1024) КБ • \(total) частей"
            index = 0
            finished = false
            error = nil
            playing = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reset() {
        qrTexts = []
        fileName = ""
        fileInfo = ""
        qrImage = nil
        index = 0
        playing = false
        finished = false
        error = nil
    }
}

private struct QrTaskKey: Equatable {
    let textsHash: [String]
    let index: Int
    init(_ texts: [String], _ index: Int) {
        self.textsHash = texts
        self.index = index
    }
}