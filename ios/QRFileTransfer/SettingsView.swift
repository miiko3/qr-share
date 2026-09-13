import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                ForEach(AppIconCatalog.options) { option in
                    Button {
                        settings.apply(option: option)
                    } label: {
                        HStack(spacing: 12) {
                            if let image = option.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .cornerRadius(8)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.currentIconName == option.alternateName {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(settings.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Иконка приложения")
            } footer: {
                Text("Цвет меню и кнопок подстраивается под выбранную иконку.")
            }

            Section {
                Link(destination: URL(string: "https://t.me/yetilov")!) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                        Text("Разработчик")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(settings.accent)
                }
            } header: {
                Text("О приложении")
            }
        }
        .navigationTitle("Настройки")
        .tint(settings.accent)
    }
}