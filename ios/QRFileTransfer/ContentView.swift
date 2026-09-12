import SwiftUI

struct ContentView: View {
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

                NavigationLink("Принять файл") { ReceiveView() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding()
            .navigationTitle("Главная")
        }
    }
}