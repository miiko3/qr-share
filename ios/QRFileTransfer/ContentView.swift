import SwiftUI

struct ContentView: View {
    @State private var updateAvailable = false
    @State private var latestTag = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("QR File Transfer")
                    .font(.largeTitle).bold()
                Text("Передача файлов между устройствами через QR-код.\nОдин QR-код = одна часть файла.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                NavigationLink("Отправить файл") { SendView() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                NavigationLink("Принять файл") { ReceiveView() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                if updateAvailable {
                    VStack(spacing: 8) {
                        Text("Доступна новая версия \(latestTag)")
                            .font(.subheadline).bold()
                        Text("Обновите приложение на этом устройстве — часть функций может не работать со старыми версиями.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://github.com/miiko3/qr-share/releases")!) {
                            Text("Открыть релизы")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Главная")
            .task {
                let local = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                if let tag = try? await ReleaseChecker.latestTag(),
                   isNewer(tag, local) {
                    latestTag = tag
                    updateAvailable = true
                }
            }
        }
    }
}

private func isNewer(_ latest: String, _ local: String) -> Bool {
    let a = versionParts(latest)
    let b = versionParts(local)
    let count = max(a.count, b.count)
    for i in 0..<count {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

private func versionParts(_ s: String) -> [Int] {
    s.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
        .split(separator: ".").compactMap { Int($0) }
}

enum ReleaseChecker {
    static func latestTag() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/miiko3/qr-share/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tag = object?["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return tag
    }
}