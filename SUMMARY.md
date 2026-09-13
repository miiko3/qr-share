# SUMMARY.md

> Контекст сессий работы над проектом `miiko3/qr-share` — содержательный срез,
> чтобы продолжать работу с любого места. Обновляйте после каждой сессии.

## Objective
- Главный незакрытый вопрос: QR-коды **не считываются на устройстве пользователя (Android)**.
  Генерация кодов доказанно валидна (round-trip через ZXing), проблема на стороне
  приёмника/камеры — диагностика v1.7.0 (яркость/контраст кадра, тап-фокус,
  COMPATIBLE-preview) **ещё не протестирована пользователем**; нужен отзыв
  «Что под рамкой: Декодировано QR / Яркость % / Контраст».
- Последняя крупная задача (выполнена в v1.8.0): iOS — смена иконки приложения
  (stock + 11 альтернатив), цвет меню/кнопок в цвет активной иконки, экран
  «Настройки» с кнопкой «Разработчик» (Telegram `yetilov`), SF Symbols, таймер
  завершения при приёме, оповещение «Держите телефон ровнее» при наклоне,
  оповещение «Файл слишком большой» для файлов > 99 МБ (iOS + Android).

## Важное / проверенные факты
- Репозиторий публичный: `https://github.com/miiko3/qr-share` (аккаунт `miiko3`).
  Локальный клон: `C:\Users\123\Documents\Default Project\qr-share`.
  CI: workflows «Build Android» (push/main), «Build iOS» (macos-15, XcodeGen),
  «Release» (`gh workflow run "Release" -f version=X.Y.Z`, permissions contents:write).
  Артефакты релизов: `app-release.apk` + `QRFileTransfer-iOS-device.ipa`
  (unsigned, для Sideloadly). ReleaseChecker в iOS-приложении проверяет последний
  тег через GitHub API и предлагает обновление.
- iOS локально (Windows) не собирается — собирается только на CI. Локальные
  Android-сборки тоже нестабильны: на этом ПК не хватает ОЗУ, Kotlin daemon
  умирает (`errno=1455`, «недостаточно памяти»); рабочий путь — `gradlew.bat
  assembleDebug --no-daemon`, но чаще проверяем через CI.
- `android/gradle.properties` (закоммичено): `org.gradle.jvmargs=-Xmx2048m
  -XX:MaxMetaspaceSize=512m`, `kotlin.daemon.jvmargs=-Xmx2048m
  -XX:MaxMetaspaceSize=384m`, workers.max=2. Пробовали больше памяти и
  `kotlin.compiler.execution.strategy=in-process` — не помогло/нестабильно.
- Версии: Android versionCode/versionName, iOS CFBundleShortVersionString и
  CFBundleVersion синхронизированы. Сейчас в репо: **1.8.0 / code 21**.
  История: v1.5.1 (`af7b2b5`), v1.6.0 (`83e65d9`), v1.6.1 (`de8dc00`),
  v1.6.2 (`e575910`), v1.7.0 (`a32f5f5`), v1.8.0 (`c76b82a`).
  v1.5.1 … v1.8.0 — все опубликованы на GitHub Releases. v1.7.0 отдельно не
  релизили — его исправления вошли в v1.8.0.
- **QR-коды приложения валидны**: round-trip тест через ZXing
  (`C:\Users\123\AppData\Local\Temp\opencode\qrcheck\QrRoundTrip.java`,
  использует zxing core-3.5.3 из gradle cache) — заголовок/чанк (800 байт →
   ~1138 символов base64) закодировались и декодировались EQUAL=true.
  Симптомы с устройства пользователя: v1.6.0 «камера вообще ничего не
  показывает (не пишет)»; v1.6.1 «не сканируется и вечная проверка камеры»
  (счётчик кадров РОС — кадры приходят, но не декодируются; чистый ZXing,
  ML Kit удалён); v1.6.2 «ничего не поменялось» (диагностику не прислал).
- Протокол `QrProtocol` (общий с Android): заголовок `{"t":"h",...}` +
  чанки `{"t":"d","i":N,"d":base64,"c":crc32}`, sha256, sid (16 hex) + nonce —
  проверен, ошибок не найдено. maxFileSize = 99 МБ (iOS `QrProtocol.maxFileSize`,
  Android `QrProtocol.MAX_FILE_SIZE`).
- Успешная передача файл сама больше НЕ открывает: Android — `openSavedFile`
  удалён из ReceiveScreen; iOS — быстрый QuickLook автоматически не показывается,
  доступна кнопка «Открыть полученный файл» + ShareLink.
- v1.7.0 добавил Android-диагностику: `processFrame` с luma mean/std
  (яркость/контраст кадра), тап-фокус `SurfaceOrientedMeteringPointFactory(float,
  float)` + `FocusMeteringAction.Builder(point, FLAG_AF)` + `setAutoCancelDuration
  (1500L, MILLISECONDS)` (сигнатуры подтверждены через javap),
  `PreviewView.ImplementationMode.COMPATIBLE`, подсказка про 10–20 см.
- v1.8.0 (iOS): `IconKit.swift` (AppIconCatalog: stock + frame-32…frame-42;
  `AppSettings` ObservableObject — переключение иконки через
  `UIApplication.shared.setAlternateIconName` + акцентный цвет по доминирующему
  цвету PNG через `UIImage.dominantColor()` (48×48, бакеты 6 бит/канал,
  предпочтение насыщенности); хранение выбора в UserDefaults key `appIcon`),
  `SettingsView.swift` (List с сеткой иконок, галочка, кнопка «Разработчик» →
  https://t.me/yetilov), `TiltMonitor.swift` (CMMotionManager deviceMotion,
  порог 35°, publish `isTilted`), ReceiveView: баннер «Держите телефон ровнее»,
  «Осталось ~N c» по скорости чанков (`startedAt`), лимит 99 МБ на приёме;
  `Assets.xcassets/AppIcon.appiconset/AppIcon.png` = stock.png (1024×1024),
  альтернативы — `ios/QRFileTransfer/frame-32.png…frame-42.png` + `stock.png`
  (235×235, копии из `C:\Users\123\Desktop\icon\`), в `project.yml` прописан
  `CFBundleAlternateIcons` (frame-32…frame-42) и версия 1.8.0/21. Акцент
  применяется на корне `.tint(settings.accent)` в `QRFileTransferApp`.
- Пользователь пишет по-русски; тексты UI — по-русски, сленг мира иконок
  «Frame N» сохранён как есть.

## Work State
### Completed
- v1.8.0: все iOS-фичи реализованы и релиз опубликован
  (https://github.com/miiko3/qr-share/releases/tag/v1.8.0), оба артефакта на месте.
- Релизы v1.5.1, v1.6.0, v1.6.1, v1.6.2, v1.7.0(без отдельного релиза), v1.8.0.
- Round-trip тест QR (генерация не виновата).

### Active
- Ждём теста v1.8.0 пользователем (смена иконок, настройки, таймер, наклон,
  лимит 99 МБ) и отзыва по Android-диагностике из v1.7.0/1.8.0.

### Blocked
- Android-QR на устройстве пользователя: причина не подтверждена, нужны значения
  яркости/контраста (в v1.8.0 такая же диагностика, как в v1.7.0).
- Локальные сборки (Android — память; iOS на Windows невозможно) → только CI.

## Next Move
1. Дождаться отзыва пользователя по v1.8.0.
2. Попросить прислать диагностику сканера (под рамкой: «Декодировано QR: N»,
   «Яркость: X%», «Контраст: Y»).
3. По итогам диагностики — продолжать лечить Android-сканирование
   (гипотезы: чёрный кадр при COMPATIBLE-режиме, фокус, экспозиция;
   следующий шаг — сравнить preview и кадр processFrame).

## Relevant Files
- `ios/QRFileTransfer/IconKit.swift` — каталог иконок + акцентный цвет + переключение.
- `ios/QRFileTransfer/SettingsView.swift` — «Настройки»: иконка + Разработчик.
- `ios/QRFileTransfer/TiltMonitor.swift` — датчик наклона.
- `ios/QRFileTransfer/ReceiveView.swift` — таймер ETA, баннер наклона, лимит 99 МБ.
- `ios/QRFileTransfer/SendView.swift` — лимит 99 МБ («Файл слишком большой»).
- `ios/QRFileTransfer/ContentView.swift` — батон «Настройки» (gearshape, toolBar).
- `ios/QRFileTransfer/QrProtocol.swift` — `maxFileSize = 99 МБ`.
- `ios/project.yml` — `CFBundleAlternateIcons`, версия 1.8.0/21.
- `android/app/.../QrProtocol.kt`, `ui/SendScreen.kt`, `ui/ReceiveScreen.kt` —
  лимит 99 МБ и сообщение «Файл слишком большой»; блок приёма (версия/диагностика).
- `android/app/build.gradle.kts` — versionCode 21 / name "1.8.0".
- `android/gradle.properties` — jvmargs (урезаны под память ПК).
- `C:\Users\123\Desktop\icon\` — исходники иконок (stock.png + Frame 32…42).
- `C:\Users\123\AppData\Local\Temp\opencode\qrcheck\QrRoundTrip.java` — стенд
  проверки кодирования/декодирования QR (EQUALS=true).