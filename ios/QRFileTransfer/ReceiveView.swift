import SwiftUI
import AVFoundation
import Photos
import QuickLook

enum ScanState {
    case idle, reading, interrupted, success
}

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
    @Published var startedAt: Date?
    @Published var info = "Наведите камеру на QR-коды отправителя"
    @Published var savedName: String?
    @Published var savedURL: URL?
    @Published var photoSaved = false
    @Published var failInfo: String?
    @Published var state: ScanState = .idle

    private var sessions: [String: ReceiveSession] = [:]
    private let queue = DispatchQueue(label: "receive.lock")
    private var lastRead = Date.distantPast

    func handle(_ text: String) {
        queue.sync { [weak self] in
            guard let self else { return }
            if let header = parseHeader(text) {
                if header.size > QrProtocol.maxFileSize {
                    publish { self.failInfo = "Файл слишком большой" }
                    return
                }
                if sessions[header.sid] == nil {
                    sessions[header.sid] = ReceiveSession(header: header)
                }
                let t = header.total
                let n = header.name
                lastRead = Date()
                publish {
                    self.done = 0
                    self.total = t
                    self.startedAt = Date()
                    self.info = "Получение: \(n) • \(t) частей"
                    self.savedName = nil
                    self.savedURL = nil
                    self.photoSaved = false
                    self.failInfo = nil
                    self.state = .reading
                }
                return
            }

            guard let chunk = parseChunk(text),
                  let session = sessions[chunk.sid] else { return }
            guard chunk.crc == QrProtocol.crc32Value(chunk.bytes) else { return }

            guard session.add(chunk) else { return }
            let count = session.count
            let total = session.header.total
            lastRead = Date()
            publish {
                self.done = count
                self.state = .reading
            }

            if count == total {
                let full = session.assemble()
                if QrProtocol.sha256Hex(full) == session.header.sha {
                    let name = session.header.name
                    let mime = session.header.mime
                    let url = Self.save(full, name: name, mime: mime)
                    let photo = Self.isPhoto(mime)
                    publish {
                        self.state = .success
                        self.savedName = name
                        self.savedURL = url
                        self.photoSaved = photo
                        self.total = total
                        self.info = photo ? "Готово: \(name) — сохранено в Фото" : "Готово: \(name)"
                    }
                } else {
                    publish { self.failInfo = "Контрольная сумма не совпала. Отправьте файл заново." }
                }
            }
        }
    }

    /// Вызывается периодически из UI: если QR-коды не поступают — помечаем чтение прерванным.
    func refreshInterruption() {
        guard total > 0, done < total, state != .success else { return }
        if Date().timeIntervalSince(lastRead) > 2.5, state == .reading {
            state = .interrupted
        }
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async { block() }
    }

    private static func isPhoto(_ mime: String) -> Bool {
        mime.hasPrefix("image/") || mime.hasPrefix("video/")
    }

    private static func save(_ data: Data, name: String, mime: String) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        if isPhoto(mime) {
            saveToPhotosLibrary(data, isImage: mime.hasPrefix("image/"))
        }
        return url
    }

    private static func saveToPhotosLibrary(_ data: Data, isImage: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(
                    with: isImage ? PHAssetResourceType.photo : PHAssetResourceType.video,
                    data: data,
                    options: nil
                )
            }, completionHandler: nil)
        }
    }
}

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SessionStore()
    @StateObject private var tilt = TiltMonitor()
    @State private var granted = false
    @State private var showPreview = false
    @State private var now = Date()

    private var etaText: String? {
        guard let startedAt = store.startedAt, store.total > 0, store.done < store.total else {
            return nil
        }
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 2 else { return nil }
        let remaining = store.total - store.done
        let rate = Double(store.done) / elapsed
        guard rate > 0 else { return nil }
        let seconds = Int(ceil(Double(remaining) / rate))
        return seconds > 0 ? "Осталось ~\(seconds) c" : nil
    }

    private var statusText: String {
        switch store.state {
        case .idle: return "Наведите камеру на квадрат"
        case .reading: return "Считывается: \(store.done) / \(store.total)"
        case .interrupted: return "Считывание прервано — поднесите ближе"
        case .success: return "Считывание прошло успешно — файл передан"
        }
    }

    private var statusColor: Color {
        switch store.state {
        case .idle: return .white
        case .reading, .success: return .green
        case .interrupted: return .orange
        }
    }

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
                if granted {
                    CameraScannerView { text in store.handle(text) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Поле-квадрат для наведения сканера.
                    GeometryReader { geo in
                        let side = max(min(min(geo.size.width, geo.size.height) * 0.68, 340), 200)
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(statusColor, lineWidth: 3)
                                .frame(width: side, height: side)
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(statusColor.opacity(0.45), lineWidth: 1)
                                .frame(width: side * 0.92, height: side * 0.92)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.bottom, 140)
                    .allowsHitTesting(false)
                } else {
                    VStack(spacing: 16) {
                        Text("Для приёма файлов нужен доступ к камере.")
                            .multilineTextAlignment(.center)
                        Button("Разрешить доступ к камере") { requestPermission() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Text("Если кнопка не помогла — включите камеру в настройках приложения.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 420)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack {
                    Spacer()
                    if store.total > 0 {
                        ProgressView(
                            value: Double(min(store.done, store.total)),
                            total: Double(store.total)
                        )
                        .frame(maxWidth: 480)
                        HStack(spacing: 8) {
                            Text("Принято частей: \(store.done) / \(store.total)")
                            if let eta = etaText {
                                Text("• \(eta)")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding()
            }
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(statusColor, lineWidth: 2)
                        )
                    if store.total > 0 {
                        Text(store.info)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 8)
            }
            .overlay(alignment: .top) {
                if tilt.isTilted && (store.state == .idle || store.state == .reading) {
                    Label("Держите телефон ровнее", systemImage: "iphone.and.arrow.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 84)
                }
            }

            if store.failInfo != nil {
                Text(store.failInfo!)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }

            if let name = store.savedName {
                Text(store.photoSaved ? "Файл сохранён в галерею Фото: \(name)" : "Файл сохранён: \(name)")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let url = store.savedURL {
                    Button {
                        showPreview = true
                    } label: {
                        Label("Открыть полученный файл", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
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
            requestPermission()
            tilt.start()
        }
        .onDisappear {
            tilt.stop()
        }
        .task(id: "clock") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                now = Date()
            }
        }
        .task(id: store.total) {
            guard store.total > 0, store.state != .success else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                store.refreshInterruption()
            }
        }
        .onChange(of: store.savedURL) { url in
            // Файл получен — ничего не открываем автоматически, только уведомление выше.
        }
        .sheet(isPresented: $showPreview) {
            if let url = store.savedURL {
                QuickLookView(url: url)
            }
        }
    }

    private func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { granted = ok }
            }
        default:
            granted = false
        }
    }
}

/// Быстрый предпросмотр полученного файла (QLPreviewController).
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        context.coordinator.controller = controller
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        weak var controller: QLPreviewController?

        init(_ url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}