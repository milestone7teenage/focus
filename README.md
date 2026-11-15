# focus

Статус: документация MVP v0.3. Платформа: iOS 17+. Стек: Swift, SwiftUI, SwiftData, UserNotifications.

## Назначение
`focus` — минималистичное офлайн-приложение для разовых и ежедневных напоминаний. Задача остаётся активной, пока пользователь не выполнит или не удалит её. Просмотр уведомления не означает выполнение.

## MVP
- две нижние вкладки: «Разовые» и «Регулярные»;
- отдельные монохромные карточки;
- длинные названия отображаются полностью;
- системная светлая/тёмная тема;
- выполнение долгим нажатием около 0,6 секунды;
- свайп влево — удаление с Undo на 3 секунды;
- свайп вправо — snooze на 30 минут;
- локальные уведомления: первоначальное и до трёх повторов через 10 минут;
- открытие уведомления или действие «Увидел» переводит задачу в SEEN;
- ежедневный reset регулярных задач;
- истории и архива нет.

## Стек и автономность
SwiftUI, SwiftData, UserNotifications, Foundation Calendar/DateComponents. Приложение работает без обязательного интернета, сервера, аккаунта или iCloud.

## Рабочий процесс
Разработка ведётся на Windows через OpenCode, исходники хранятся в GitHub. Сборка и тесты выполняются на macOS runner GitHub Actions или настоящем Mac. Windows не используется для `xcodebuild`.

До явного утверждения старта Этапа 1 запрещено создавать Swift-код, `.swift`-файлы и Xcode-проект.

## Git
Работать в feature-ветках. Перед изменениями проверить `git status`, ветку и `HEAD`. Не делать commit/push без разрешения. Не выполнять destructive-команды. После изменений проверить diff и тесты.

## CI и IPA
Успешная компиляция не доказывает успешную упаковку IPA, подпись или возможность установки. Эти пункты проверяются отдельно.

### GitHub Actions Artifacts
CI собирает **неподписанный `.ipa`** (`focus-unsigned.ipa`) как артефакт (`build-unsigned-ipa` job).
- Артефакт создаётся с `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.
- **Неподписанный IPA нельзя установить напрямую на iPhone.**
- Для установки на физическое устройство необходимо локально подписать IPA:
  - через Xcode (`xcodebuild -exportArchive` с вашим Development/Ad-Hoc профилем),
  - или через `fastlane` / `altstore` / `Sideloadly` / `TrollStore`.
- Подпись и способ установки проверяются отдельно от CI.

## Сборка локально (на macOS)
```bash
brew install xcodegen
xcodegen generate
xcodebuild -project focus.xcodeproj -scheme focus -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project focus.xcodeproj -scheme focus -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Архивация и экспорт подписанного IPA (локально)
```bash
xcodebuild archive \
  -project focus.xcodeproj \
  -scheme focus \
  -sdk iphoneos \
  -configuration Release \
  -archivePath build/focus.xcarchive \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="iPhone Distribution"

xcodebuild -exportArchive \
  -archivePath build/focus.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```