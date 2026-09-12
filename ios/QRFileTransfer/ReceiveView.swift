import SwiftUI
import AVFoundation

private final class ReceiveSession {
    let header: ReceivedHeader
    var parts: [Data?]
    var count = 0

    init(header: ReceivedHeader) {
        self.header = header
        self.parts = Array(repeating: nil, count: header.total)
    }

    @discardableResult
    func add(_ chunk: ReceivedChunk) -> Bool {
        guard chunk.index >= 1, chunk.index <= parts.count, parts[chunk.index - 1] == nil else {
            return false
        }
        parts[chunk.index - 1] = chunk.bytes
        count += 1
        return true
    }

    func assemble() -> Data {
        var out = Data()
        for part in parts {
            if let part { out.append(part) }
        }
        return out
    }
}

final class SessionStore: ObservableObject {
    @Published var done = 0
    @Published var total = 0
    @Published var info = "Наведите камеру на QR-коды отправителя"
    @Published var savedName: String?
    @Published var failInfo: String?
    @Published var savedURL: URL?

    private var sessions: [String: ReceiveSession] = [:]
    private let queue = DispatchQueue(label: "receive.lock")

    func handle(_ text: String) {
        queue.sync { [weak self] in
            guard let self else { return }
            if let header = parseHeader(text) {
                if sessions[header.sid] == nil {
                    sessions[header.sid] = ReceiveSession(header: header)
                }
                let t = header.total
                let n = header.name
                publish {
                    self.done = 0
                    self.total = t
                    self.info = "Получение: \(n) • \(t) частей"
                    self.savedName = nil
                    self.savedURL = nil
                    self.failInfo = nil
                }
                return
            }

            guard let chunk = parseChunk(text),
                  let session = sessions[chunk.sid] else { return }
            guard chunk.crc == QrProtocol.crc32Value(chunk.bytes) else { return }

            guard session.add(chunk) else { return }
            let count = session.count
            let total = session.header.total
            publish { self.done = count }

            if count == total {
                let full = session.assemble()
                if QrProtocol.sha256Hex(full) == session.header.sha {
                    let name = session.header.name
                    let url = Self.save(full, name: name)
                    publish {
                        self.savedName = name
                        self.savedURL = url
                        self.total = total
                        self.info = "Готово: \(name)"
                    }
                } else {
                    publish { self.failInfo = "Контрольная сумма не совпала. Отправьте файл заново." }
                }
            }
        }
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async { block() }
    }

    private static func save(_ data: Data, name: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
}

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SessionStore()
    @State private var granted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("← Назад") { dismiss() }
                Spacer()
                Text("Получение").font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            ZStack {
                CameraScannerView { text in store.handle(text) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !granted {
                    Text("Нет доступа к камере. Разрешите доступ в настройках.")
                        .foregroundStyle(.red)
                }

                VStack {
                    Spacer()
                    if store.total > 0 {
                        ProgressView(
                            value: Double(min(store.done, store.total)),
                            total: Double(store.total)
                        )
                        Text("Принято частей: \(store.done) / \(store.total)")
                            .font(.caption)
                    }
                }
                .padding()
            }
            .overlay(alignment: .top) {
                Text(store.info)
                    .font(.subheadline)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if store.failInfo != nil {
                Text(store.failInfo!)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }

            if let name = store.savedName {
                Text("Файл сохранён: \(name)")
                    .foregroundStyle(.green)
                    .font(.subheadline)
                if let url = store.savedURL {
                    ShareLink(item: url) {
                        Label("Сохранить / Поделиться", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { granted = ok }
            }
        }
    }
}