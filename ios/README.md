# iOS: QR File Transfer

Нативное iOS-приложение на **Swift + SwiftUI**. Сканер — **AVFoundation + Vision**,
генерация QR — **CoreImage**, хэши — **CryptoKit/zlib**.

## Зависимости от системы

- macOS с **Xcode 15+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — генерирует `.xcodeproj` из `project.yml`

```bash
brew install xcodegen
```

## Быстрый старт (XcodeGen)

```bash
cd ios
xcodegen generate      # создаёт QRFileTransfer.xcodeproj
open QRFileTransfer.xcodeproj
# выберите схему QRFileTransfer и запустите на симуляторе
```

`Info.plist` генерируется автоматически и содержит `NSCameraUsageDescription`
(нужен доступ к камере для сканирования QR).

## Ручной способ (без XcodeGen)

1. Xcode → File → New → Project → **iOS App**, имя `QRFileTransfer`.
2. Deployment target: **iOS 16.0**.
3. Удалите автоматический `ContentView.swift`, скопируйте в проект все `.swift` файлы
   из папки `QRFileTransfer/`.
4. В Info.plist добавьте:
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Нужен доступ к камере для сканирования QR-кодов</string>
   ```

## Сборка из командной строки (без подписи, для симулятора)

```bash
cd ios
xcodegen generate
xcodebuild \
  -project QRFileTransfer.xcodeproj \
  -scheme QRFileTransfer \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
# .app лежит в build/Build/Products/Debug-iphonesimulator/QRFileTransfer.app
```

## Релиз в App Store

1. Нужен Apple Developer Program аккаунт (бесплатная персональная подпись для теста
   на своём устройстве тоже возможна).
2. В Xcode выберите Target → Signing & Capabilities → выберите свою команду.
3. Product → Archive → Distribute.

## Примечания

- Получатель сохраняет файл в папку `Documents/Received` и может поделиться
  через системный Share Sheet (кнопка появляется после завершения приёма).
- Протокол QR-кодов полностью совместим с Android-версией из папки `android/`.