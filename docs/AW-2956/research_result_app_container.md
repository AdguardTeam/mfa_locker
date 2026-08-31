# AW-2956 — Запуск AdGuard Wallet в Windows AppContainer: инженерная осуществимость и план

## TL;DR

**Вердикт: осуществимо, но дорого; на стадии preview ОС-технологии; с непроверенным эффектом для безопасности — и решение в первую очередь зависит от дешёвого эксперимента по безопасности, а не от инженерной работы.** Есть ровно один жизнеспособный путь (Win32 App Isolation: `uap18:TrustLevel="appContainer"` + `RuntimeBehavior="appSilo"`); UWP мёртв для Flutter, а обычный MSIX не даёт изоляции (уже опровергнуто).

**Сначала проведите эксперимент по безопасности.** До любых вложений в загрузку/упаковку запустите AppContainer MSIX, который исполнитель уже собрал, и направьте распакованный exe того же пользователя на учётные данные Windows Hello. Если seed всё ещё извлекается, изоляция не блокирует атакующего, и весь объём работ ~8–16+ недель не даёт ничего с точки зрения безопасности — остановитесь. Этот тест на 1–3 дня — решающий шлюз и **не** требует исправления белого экрана.

Только если этот шлюз пройден, инженерная работа имеет смысл. Ею доминируют три сложные проблемы, и ни одна из них — не сам манифест: (1) **сбой инициализации с белым экраном** (наиболее вероятно: создание GPU-поверхности ANGLE/D3D под токеном low-integrity или ранний отказ доступа к хранилищу/путям); (2) **хранилище, ломающееся в песочнице** — `flutter_secure_storage_windows` хранит секреты в **файле с шифрованием DPAPI**, ключи которого перепривязываются к user+package identity в AppContainer, а пути `path_provider` виртуализируются/блокируются, поэтому ключ БД MFA-locker и постоянная БД под реальным риском **потери данных / блокировки пользователя**; и (3) **диалоги выбора файлов** (`file_selector_windows`/`file_picker`), которые бросают `E_ACCESSDENIED` в partialTrust (подтверждено Microsoft, Won't Fix).

**Два дополнительных честных оговорки заранее:** (a) даже полностью рабочая AppContainer-сборка даёт **нулевую изоляцию на Windows 10 / Windows 11 23H2 и ранее** — там она молча работает в full trust, поэтому большая часть текущей базы установок остаётся незащищённой, пока пользователи не обновятся до 24H2+; и (b) запланированная feasibility-сборка исключает `biometric_cipher`, поэтому функционально она идентична уже выпущенной позиции AW-2957 (Hello отключён), пока эксперимент по безопасности не пройдёт и последующая фаза не включит Hello снова. **Не вкладывайтесь в многомесячную инженерную работу, пока не пройдут и эксперимент по безопасности, и Фаза 0 (получить машину с 24H2 + прочитать `app_container_init.log`).**

## 1. Где мы сейчас

Временное исправление (AW-2957, PR#920, смержено 2026-05-29) отключило автономную разблокировку Windows Hello и сделало пароль корнем доверия, поэтому уязвимость закрыта для обновившихся пользователей. Обычная MSIX-упаковка с отдельным Package Family Name была **экспериментально опровергнута** (видеодемо 2026-06-17): она не изолирует учётные данные Hello. **Единственный** оставшийся кандидат на уровне ОС — запуск кошелька в настоящем AppContainer через **Win32 App Isolation** (appSilo). Исполнитель собрал AppContainer MSIX, но приложение не инициализируется — **белый экран** — а `partialTrust` дополнительно ломает доступ к файловой системе, включая `file_picker` (см. `microsoft/WindowsAppSDK#3536`, `microsoft/microsoft-ui-xaml#9557`). Init-лог (`app_container_init.log`) прикреплён к Jira на внутреннем сервере с авторизацией и здесь недоступен.

## 2. Что на самом деле требуется для «запуска в AppContainer»

Есть три маршрута на уровне ОС; жизнеспособен только один:

| Маршрут | Статус для проекта | Почему |
|---|---|---|
| **(a) UWP** | **Мёртв — недоступен** | Flutter-embedder `winuwp` был в alpha (2021-05), сворачивание объявлено 2022-04 (`flutter/flutter#102172`), инструментарий (в т.ч. `flutter create --platforms=winuwp`) удалён в Flutter 3.3.0. Закреплённый Flutter 3.41.4 не имеет UWP-таргета. |
| **(b) Обычный MSIX (full-trust)** | **Без изоляции** | Инженер Microsoft подтверждает: «Regular MSIX apps do not run in an AppContainer» (`WindowsAppSDK Discussion #410`). Trust задаётся только манифестом `EntryPoint`/`TrustLevel`. Уже опровергнуто демо. |
| **(c) Win32 App Isolation (appSilo)** | **Единственный жизнеспособный путь — но PUBLIC PREVIEW, только Win11 24H2 / build 26100+** | `uap18:TrustLevel="appContainer"` + `uap18:RuntimeBehavior="appSilo"`. Процесс работает с low-integrity и Package SID, доступ к ресурсам через broker. |

**Критический факт-шлюз:** Win32 App Isolation всё ещё в **public preview** (страница Microsoft Learn обновлена 2025-05-15, до середины 2026 помечена как preview) и **молча откатывается к FullTrust на любой ОС ниже 24H2**. Манифест намеренно dual-entrypoint (`EntryPoint="Windows.FullTrustApplication"` как fallback + `uap18:EntryPoint="Isolated.App"`). На Win10 / Win11 23H2 и ранее — большая часть текущей базы установок — приложение работает в **full trust и не защищено**. Песочница включается только на 24H2+.

Ключевые URL: [App Isolation overview](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-overview) · [Packaging with VS](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-packaging-with-vs) · [MSIX container model](https://learn.microsoft.com/en-us/windows/msix/msix-container) · [flutter/flutter#102172 (UWP wind-down)](https://github.com/flutter/flutter/issues/102172).

## 3. Блокеры — конкретно

### (a) Инициализация приложения / белый экран

Белый экран — видимый симптом сбоя `FlutterWindow::OnCreate()` или необработанного Dart-исключения на первом кадре. Вероятные причины по рангу:

| Ранг | Причина | Механизм | Как подтвердить |
|---|---|---|---|
| **#1 (жёсткий abort)** | **Создание GPU-поверхности ANGLE/EGL/D3D11 запрещено** под токеном low-integrity | `flutter_window.cpp` `OnCreate()` возвращает `false`, если `!engine() \|\| !view()`; это всплывает через `win32_window.cpp` → сбой `window.Create(...)` в `wWinMain`, который возвращает `EXIT_FAILURE` в `main.cpp:74`. ANGLE (libEGL/libGLESv2→D3D11) часто падает или не имеет WARP-fallback в AppContainer. Если ANGLE откатывается к software-пути без кадра: классический белый экран. *(Точные диапазоны строк `flutter_window.cpp`/`win32_window.cpp` на этом macOS-checkout не проверяемы; проверить на Windows-checkout перед инструментированием.)* | Init-лог показывает сбой engine **до** любого Dart-вывода (ошибки EGL/ANGLE/D3D, `EXIT_FAILURE`, нет Flutter-логов). |
| **#2 (функциональный)** | **Запись/чтение DPAPI-файла `flutter_secure_storage_windows` заблокированы**; чтение MFA-locker выполняется при старте | Активный Windows-путь в `flutter_secure_storage_windows 3.1.2` — **Dart FFI / DPAPI**: хранит DPAPI-зашифрованный JSON-файл `flutter_secure_storage.dat` под `getApplicationSupportDirectory()` через `CryptProtectData`/`CryptUnprotectData` (`flutter_secure_storage_windows_ffi.dart:177,184,231,333`). В AppContainer ключи DPAPI перепривязываются к **user + package identity**, поэтому blob, записанный full-trust-сборкой, может не расшифроваться через границу (ошибка `CryptUnprotectData`), а записи попадают в виртуализированное хранилище пакета. Legacy-код `CredReadW`/`CredWriteW` Credential Manager в C++-плагине — только путь `useBackwardCompatibility` (legacy-read), **не** основное хранилище. Фактическое чтение/расшифровка locker происходит в слое хранилища MFA-locker (`LockerStorage*`, `lib/data/storage/locker/`) при старте; сбой там бросает исключение на первом кадре → engine жив, UI нет. *(`locker_storage_path_util.dart` только вычисляет путь к файлу; locker не читает.)* | Init-лог показывает запуск Dart `main()`, затем исключение `secure_storage` / DPAPI / `CryptUnprotectData` или сбой расшифровки MFA-locker. |
| **#3 (функциональный)** | **Пути БД и логов `path_provider` перенаправлены/запрещены** | `app_database.dart:52,99` открывает зашифрованные Drift-БД под `getApplicationDocumentsDirectory()` (FOLDERID_Documents — обычно **недоступен** в AppContainer без `broadFileSystemAccess`). `DbLifecycleService.openDb` бросает исключение. | Init-лог показывает `sqlite3 "unable to open database file"` или `FileSystemException` на Documents/RoamingAppData. |

**Самый быстрый дискриминатор (#1 vs #2/#3): наличие/отсутствие Dart-логов** в `app_container_init.log`. Нет Dart-вывода ⇒ GPU; есть Dart-вывод, затем исключение storage/locker ⇒ storage. **Нужно получить и прочитать этот лог до любых крупных вложений.**

### (b) Файловая система и pickers

При настоящей изоляции WinRT `FileOpenPicker`/`FileSavePicker` бросают `E_ACCESSDENIED` на обязательном вызове `InitializeWithWindow.Initialize(picker, hWnd)` — подтверждено Microsoft и **Won't Fix** (`microsoft-ui-xaml#9557`: «WinUI 3 can either use the WinRT file dialogs OR run in partial trust. But NOT both.»; `WindowsAppSDK#3536`). Это напрямую затрагивает `file_selector_windows 0.9.3+4` (через `file_picker 10.3.3`). Конкретные рискованные потоки, все в итоге пишут/читают через `dart:io File` по абсолютному пути picker:

- **Экспорт логов (save):** `lib/feature/settings/support/export_logs/data/repository/file_picker_repository.dart` — `saveFile` (строка 24) вызывает picker `saveFile` (строка 31), затем пишет через `dart:io File` в `_saveBytesToFileForDesktop` (строки 54-55).
- **Вложения в contact-support (pick):** `lib/feature/settings/contact_support/attachment_picker/data/data_source/file_picker_data_source.dart:30-70` **и** отдельная обёртка-репозиторий `lib/feature/settings/contact_support/attachment_picker/data/repository/file_picker_repository.dart` (`pickFiles`, строки 19-22); затем `.../contact_support/data/contact_support_api.dart:62`.
- **Скачивание/шаринг QR:** `lib/feature/receive_crypto/receive_qr/domain/qr_image_share_service.dart:40-69`.
- **Debug (низкий приоритет):** `lib/feature/settings/debug/view/debug_init_error_screen.dart` тоже использует file_picker; не production-поток, но сломается под изоляцией.

Единственный благословенный Microsoft путь восстановления — **implicit open/save-dialog broker** Win32 App Isolation плюс restricted capability `isolatedWin32-promptForAccess` — и этот broker только для 24H2. `broadFileSystemAccess` — альтернатива, но требует Store и подрывает цель безопасности.

### (c) Нативные плагины

| Плагин / native | Статус | Требуемое изменение |
|---|---|---|
| `screenshot_blocker` (локальный) | **РАБОТАЕТ** | `SetWindowDisplayAffinity` на **своём** окне (`packages/screenshot_blocker/windows/screenshot_blocker_plugin.cpp:42-58`); разрешено, capability не нужен. |
| `url_launcher_windows 3.1.4` | **РАБОТАЕТ** | `ShellExecute("open", url)` идёт через broker shell. |
| `permission_handler_windows 0.2.1` | **РАБОТАЕТ** | По сути stub на Windows; привилегированных API нет. |
| `connectivity_plus 6.1.5` | **РАБОТАЕТ (capability)** | WinRT `NetworkInformation`; нужен `internetClient` (уже объявлен). |
| `biometric_cipher` (локальный, в bundle `mfa_locker`) | **НУЖНО ИЗМЕНИТЬ / исключить (с оговоркой — см. ниже)** | Предмет AW-2956; `KeyCredentialManager`. Hello unlock уже отключён (AW-2957) → мёртвый код в shipping-сборке. Также нарушитель компиляции coroutine `/await`. **Не автономный плагин:** транзитивная git-зависимость, поставляемая *внутри* git-пакета `mfa_locker` (`pubspec.lock:109-115`, ref `02d4b2b…`, путь `packages/biometric_cipher` под `github.com/AdguardTeam/mfa_locker`), а `mfa_locker` — ядро MFA Locker, хранящее `app::db_encryption_key` и seed. При исключении нужно проверить, что `mfa_locker` всё ещё компилируется/регистрируется на Windows без sub-plugin `biometric_cipher`; иначе сам `mfa_locker` нуждается в forked / Windows-conditional сборке. Локус: `packages/biometric_cipher` внутри git-источника `mfa_locker`. |
| `window_manager` (форк AdGuard, git `d775b5d`, v0.4.2) | **НУЖНО ПРОВЕРИТЬ (ожидается РАБОТАЕТ)** | Приложение использует show/focus/listeners на своём окне (`lib/main.dart:166`, `lib/common/deep_link/deep_link_handler.dart:110-120`). Прочитать native-источник форка на Windows-checkout, чтобы подтвердить отсутствие путей `SetWindowsHookEx`/чужих окон в сборке. |
| `screen_retriever_windows 0.2.0` | **НУЖНО ПРОВЕРИТЬ (низкий риск)** | Транзитивно через `window_manager`, прямого использования в приложении нет; read-only API мониторов. Подтвердить регистрацию без падения под low integrity. |
| `screen_lock_detector` (локальный) | **ВЕРОЯТНО СЛОМАН / НУЖНО ИЗМЕНИТЬ** | `WTSRegisterSessionNotification` + top-level WindowProc (`packages/screen_lock_detector/windows/screen_lock_stream_handler.cpp:28-44`) идёт через Terminal Services RPC — вероятно, не в default AppContainer token. Падает молча (ничего не эмитит) → ломает auto-lock. Fallback: события focus/minimize окна через `window_manager`, или принять деградированный auto-lock. |
| `screenshot_detector` (локальный) | **N/A на Windows** | В pubspec есть, но **отсутствует в `windows/flutter/generated_plugins.cmake`** — нет Windows native-стороны. Действий для AppContainer не требуется. |
| `share_plus 11.1.0` | **НУЖНО ПРОВЕРИТЬ** | Шаринг QR (`qr_image_share_service.dart:43`); убедиться, что temp-файл попадает в writable store пакета и DataTransferManager broker доступен. Низкий blast radius. |
| `app_links 6.4.1` | **НУЖНО ИЗМЕНИТЬ** | Активация `agwallet://` должна идти через **упакованный** контракт активации (OnActivated/command-line), а не через схему registry/window-relay распакованного приложения. `lib/data/repository/app_link_repository.dart:20`. |
| `sentry_flutter 9.16.1` | **НУЖНО ПРОВЕРИТЬ** | Native crashpad handler порождает дочерний процесс + named-pipe IPC + dump-файлы; может быть ограничен изоляцией named-object в AppContainer. Допустимый fallback: reporting на уровне Dart. |
| `TrustWalletCore.dll` (FFI) | **НУЖНО ИЗМЕНИТЬ (усилить — тривиально)** | `init()` загружает `_overridePath ?? _defaultResolvePath()`; на Windows `_defaultResolvePath()` возвращает голую константу `_windowsTWC` `'TrustWalletCore.dll'` (`trust_wallet_core.dart:84,91,100-116`), а `_load(path)` (строка 119) открывает любую переданную строку. DLL копируется рядом с exe (`windows/CMakeLists.txt:132`). **Пакет уже даёт чистый seam:** вызвать `TrustWalletCore.overrideLibraryPath(absolutePath)` (устанавливает `_overridePath`, строки 86/96, используется `init()` на строке 91) с абсолютным путём DLL в install-dir **до** `init()`. Изменение исходников плагина не нужно — снижает усилия/риск для этой строки. |
| `sqlite3mc` (sqlcipher) | **РАБОТАЕТ (ломается путь)** | Статически слинкован, in-process file I/O + crypto, привилегированных API нет. Ломается **путь** (см. (e)), не библиотека. |
| `jni` (FFI) | **НЕИЗВЕСТНО / вероятно убрать** | Runtime-использования на Windows не найдено (упоминания только в TWC proto `java_package` metadata). Загрузка `jvm.dll` извне пакета будет заблокирована. Подтвердить неиспользование и **убрать из Windows dependency graph** (см. (g) для реального механизма). |

### (d) Native runner и single-instance IPC

Сам runner совместим с контейнером: `win32_window.cpp` (RegisterClass/CreateWindow), `main.cpp:60` `CoInitializeEx(COINIT_APARTMENTTHREADED)` — всё разрешено; глобальных named kernel objects нет. **Но** single-instance + app-link relay в `main.cpp:9-41` — это `SendAppLinkToInstance()`, который делает `FindWindow("FLUTTER_RUNNER_WIN32_WINDOW","AdGuard Wallet")` → `SendAppLink(hwnd)` (helper плагина `app_links`, постит window message существующему экземпляру — подтвердить точное сообщение в исходниках плагина). Через границу пакета это фильтруется UIPI/integrity. **Fails open** (FindWindow возвращает null → новое окно), поэтому **не** причина белого экрана, но молча ломает доставку `agwallet://` второму экземпляру и гарантию single-instance. Packaged single-instance + protocol activation должны идти из модели активации appxmanifest.

### (e) Миграция данных / риск блокировки пользователя (наивысший риск потери данных)

| Актив | Где сейчас | Эффект AppContainer | Миграция |
|---|---|---|---|
| **Файл MFA-locker** (`wallet_locker.dat`, хранит `EntryId('app::db_encryption_key')`) | Windows: `%AppData%\<appName>\Data\` через `Platform.environment['AppData']` в ветке `Platform.isWindows` / `_getOrCreateWindowsDirectory` (`locker_storage_path_util.dart:13-19,35`). Сам ключ БД — `EntryId('app::db_encryption_key')` MFALocker (`db_encryption_utils.dart:15`), персистится locker'ом, **не** читается по пути. | Внутри MSIX AppData virtualization; новый PFN ⇒ свежий виртуализированный корень. Чтение может fallback на старый файл, но любая **запись** locker (смена пароля, teardown биометрии, lock-timeout) уходит в store пакета. | Копирование `wallet_locker.dat` в store пакета при первом запуске **или** принудительный повторный ввод пароля для регенерации locker. **Наивысший риск блокировки.** |
| **DPAPI-файл `flutter_secure_storage`** (`flutter_secure_storage.dat`) | DPAPI-зашифрованный файл под `getApplicationSupportDirectory()` (RoamingAppData), записанный FFI-путём `flutter_secure_storage_windows 3.1.2`. (`aw_secure_data` — единственный внутренний JSON **ключ**, под которым приложение хранит все значения внутри blob — `secure_storage.dart:50` — не имя файла на диске.) | DPAPI / credential identity перепривязывается к **user + package**; `.dat`, записанный распакованным приложением, может не расшифроваться под packaged identity (сбой `CryptUnprotectData`) — жёсткий cutover, не прозрачное чтение. | Перенести/перешифровать файл `flutter_secure_storage.dat` через границу при первом packaged-запуске (расшифровать старой identity, перезаписать под новой), или подтвердить, что содержимое можно восстановить и пройти re-onboard. |
| **AppDatabase** (`adguard_wallet.sqlite`, постоянные настройки) | `getApplicationDocumentsDirectory()` (FOLDERID_Documents), без app subdir (`app_database.dart:52,99`) | **Вне** %AppData% virtualization ⇒ переживает по реальному пути, **но** Documents обычно запрещён в AppContainer, и файл **инертен без ключа locker**. | Перенести с `getApplicationDocumentsDirectory()` в package-private app-data dir через `getApplicationSupportDirectory()`; мигрировать файл; зависит от миграции ключа. |
| **CacheDatabase** | `getApplicationCacheDirectory()` (`cache_database.dart:66`) | В AppContainer этот API перенаправляет в package TempState/cache; поведение отличается от сырого LocalAppData. **Регенерируемая** (`recoverCacheIfMissing()` уже есть). | Нет — принять чистый re-sync; проверить, что `getApplicationCacheDirectory()` возвращает writable package path под изоляцией. |
| **Логи** | RoamingAppData (`log_storage_path_util.dart:13-19`) | Виртуализированы; некритично. | Нет. |

Поскольку старый (распакованный) и новый (AppContainer) процессы — **разные security domains**, простое in-place переиспользование DPAPI может не сработать. Реалистично нужен либо **одноразовый распакованный migration helper**, либо путь **принудительного повторного ввода пароля**. Порядок важен: миграция secure-storage / ключа locker должна предшествовать открытию БД, иначе БД не расшифровать.

### (f) Манифест упаковки и build pipeline

`msix:3.16.12` **структурно несовместим** с AppContainer:
- `appx_manifest.dart:59` жёстко задаёт `EntryPoint="Windows.FullTrustApplication"`;
- `appx_manifest.dart:217` безусловно добавляет `runFullTrust` без opt-out;
- namespaces (`appx_manifest.dart:27,30-40`) объявляют `uap..uap10` (uap10 на строке 27), но **НЕ** `uap18`, который несёт атрибуты `TrustLevel`/`RuntimeBehavior` — значит, AppContainer trust выразить нельзя;
- `MaxVersionTested="10.0.22621.2506"` (22H2, ниже порога 24H2/26100) (`appx_manifest.dart:53`);
- неизвестные capabilities **молча отбрасываются** (`capabilities.dart`; `appx_manifest.dart:222-254`) — произвольные AppContainer capabilities объявить нельзя;
- нет raw/custom-manifest override.

Поэтому `make ci-build-msix` / `ci-build-store-msix` не могут выпустить AppContainer-пакет. Команде нужно либо форкнуть/пропатчить `msix`, либо разделить на `msix:build` → **patch `AppxManifest.xml`** → `msix:pack` (или заменить hand-authored manifest + `makeappx`/`signtool`). Манифест runner exe (`windows/runner/runner.exe.manifest`) **уже корректен — не трогать** (проверено: нет `requestedExecutionLevel`); trust level принадлежит package manifest, а добавление `requestedExecutionLevel` сломает packaged activation.

### (g) Включение плагинов определяется dependency graph, а не generated files

`windows/flutter/generated_plugins.cmake` (biometric_cipher на строке 7, jni на строке 22) и `windows/flutter/generated_plugin_registrant.cc` — **автогенерируемые** (`// Generated file, do not edit.`) `flutter build` из resolved pubspec dependency tree. **Ручное редактирование откатывается при каждой сборке** — нельзя «исключить» плагин правкой generated cmake/registrant. Реальные варианты убрать плагин из Windows-сборки:

- **(a) Сделать зависимость Windows-conditional / убрать** из `pubspec.yaml` (настоящая точка правки). Сложно для `biometric_cipher`, потому что он в bundle git-пакета `mfa_locker`, от которого зависит весь vault — см. (c).
- **(b) Post-`flutter build` patch step** в новом make target, который вырезает нежелательный плагин из generated files и перезапускает cmake. Точка правки: AppContainer target в `Makefile`, не generated files.
- **(c) Upstream guard** в самом плагине/пакете (Windows-conditional registration).

## 4. План — что менять и в каком порядке

> **Шлюз 0 (безопасность):** Проведите эксперимент по безопасности ДО любой работы по загрузке/упаковке. Если изоляция его не проходит — остановитесь; ни один шаг ниже ничего не даёт.
> **Шлюзы 0a–c (загрузка):** Затем Фаза 0 должна подтвердить, что приложение можно заставить загрузиться, прежде чем commit'иться к Фазам 1–6.

| # | Шаг | Конкретные файлы / функции / элементы манифеста | Усилия | Риск |
|---|---|---|---|---|
| **−1** | **ЭКСПЕРИМЕНТ ПО БЕЗОПАСНОСТИ (решающий шлюз, первым).** Взять AppContainer MSIX, который исполнитель уже собрал, установить, затем запустить *отдельный распакованный exe того же пользователя*, который знает credential tag и пытается переиспользовать Hello credential / извлечь seed. Белый экран **не** блокирует этот тест. Если извлечение успешно → изоляция неэффективна → **не продолжать** Фазы 0–6. | Существующий AppContainer MSIX artifact; standalone attacker exe (как в refutation demo 2026-06-17); `specs/.current/AW-2956/conclusion/`. | S | **H (kill-switch)** |
| **0a** | **Получить машину Win11 24H2 (build 26100+) / CI agent.** Настоящая изоляция включается только здесь; более старые runner'ы молча откатываются к full trust и ничего не доказывают. **GitHub-hosted `windows-latest` НЕ гарантированно 26100+** — вероятно нужен self-hosted/24H2 runner или VM. Отметить как возможный **hard stop**. | Новый 24H2 build agent в Windows pipeline; явный min-OS. | M | **H** |
| **0b** | **Получить и прочитать `app_container_init.log`; root-cause белого экрана.** Искать первую Dart log line для дискриминации GPU (#1) vs storage/locker (#2/#3). Добавить native diagnostic logging вокруг сбоя `!engine() \|\| !view()`, чтобы причина была наблюдаема (эта небольшая native-instrumentation работа входит в оценку Фазы 0). | `windows/runner/flutter_window.cpp` `OnCreate()` (логировать причину сбоя engine/ANGLE; опционально native error message box); `windows/runner/win32_window.cpp` `Create()`; `main.cpp:74` `EXIT_FAILURE`. **Проверить точные диапазоны строк на Windows-checkout** (на этом macOS-checkout не разрешимо). | S | L |
| **0c** | **Если #1 (GPU): доказать, что ANGLE/D3D11/WARP может создать surface** под AppContainer token; рассмотреть принудительный software/WARP fallback. **Это go/no-go шлюз загрузки.** | Engine surface creation; ANGLE `libEGL.dll`/`libGLESv2.dll`. | L | **H** |
| **1** | **Манифест + build pipeline.** Разделить упаковку: `msix:build` → patch `AppxManifest.xml` → `msix:pack`. Внедрить namespace `uap18`; dual `EntryPoint` (`Windows.FullTrustApplication` + `uap18:EntryPoint="Isolated.App"`); `uap18:TrustLevel="appContainer"`; `uap18:RuntimeBehavior="appSilo"`; `<TargetDeviceFamily MinVersion="10.0.26100.0">`; **убрать** `runFullTrust`; capabilities `internetClient` + `isolatedWin32-promptForAccess`. **Шаг signtool sign должен идти ПОСЛЕ patch+repack** — patch `AppxManifest.xml` между `msix:build` и `msix:pack` инвалидирует подпись и block map, поэтому существующий шаг `Sign MSIX` (`build-for-windows.yaml` строки ~108-126) должен выполняться на repacked package, не раньше. | `pubspec.yaml` `msix_config`; `Makefile` `ci-build-msix`/новый `ci-build-msix-appcontainer` target; `.github/workflows/build-for-windows.yaml` (reorder/repoint sign step); fork/patch `msix:3.16.12` или post-process script. | L | **H** |
| **2** | **Исправления runner / init.** Оградить single-instance + app-link relay `FindWindow`/`SendAppLink` флагом packaged; маршрутизировать активацию через packaged contract. Распакованную сборку не менять. | `windows/runner/main.cpp:9-41` (`SendAppLinkToInstance`); packaged-activation path `app_links`. | M | M |
| **3** | **Миграция filesystem / picker.** Перестать использовать `dart:io File` по абсолютным путям picker; опираться на 24H2 implicit dialog broker (`isolatedWin32-promptForAccess`) или переработать под brokered access. Проверить каждый export/attachment/share flow. | `export_logs/.../file_picker_repository.dart` (`saveFile`/`_saveBytesToFileForDesktop`); `attachment_picker/.../file_picker_data_source.dart:30-70`; `attachment_picker/.../repository/file_picker_repository.dart`; `qr_image_share_service.dart:40-69`; `contact_support_api.dart:62`; (только debug) `debug_init_error_screen.dart`. | M | **H** |
| **4** | **Перенос путей.** Переместить зашифрованные Drift-БД и пути locker/log в package-private app-data. AppDatabase: изменить `getApplicationDocumentsDirectory()` → `getApplicationSupportDirectory()`. Проверить, что `getApplicationCacheDirectory()` CacheDatabase возвращает writable package path. Убрать Windows locker dir с `Platform.environment['AppData']`. Проверить, что `sqlite3mc` открывается по перенаправленному пути. | `app_database.dart:52,99` (текущий `getApplicationDocumentsDirectory` → цель `getApplicationSupportDirectory`); `cache_database.dart:66` (`getApplicationCacheDirectory`); `locker_storage_path_util.dart:13-19,35` (Windows branch); `log_storage_path_util.dart:13-19`. | M | **H** |
| **5** | **Исправление плагинов.** Убрать `biometric_cipher` (только для feasibility spike — см. §7) и (если подтверждено неиспользование) `jni` из Windows dependency graph через **реальный механизм в §3(g)** (Windows-conditional dep в pubspec или post-build patch в новом make target — НЕ правкой generated files), решив вопрос, собирается ли `mfa_locker` на Windows без sub-plugin `biometric_cipher`. Усилить загрузку `TrustWalletCore.dll` через `overrideLibraryPath(absolutePath)` до `init()` (без изменения исходников плагина). Добавить fallback для `screen_lock_detector`. Проверить `window_manager`/`screen_retriever`/`share_plus`/`sentry` crashpad/`connectivity_plus`. | `pubspec.yaml`; новый `Makefile` target / post-build patch; git-источник `mfa_locker` (`packages/biometric_cipher`); `trust_wallet_core.dart:86,91,96`; `screen_lock_stream_handler.cpp:28-44`. | M–L | **H** |
| **6** | **Миграция secure-storage + БД.** First-launch, idempotent migration: прочитать legacy DPAPI `flutter_secure_storage.dat` + `wallet_locker.dat`, перезаписать в AppContainer store **до** вступления package boundary (одноразовый распакованный helper) **или** принудительный повторный ввод пароля. Порядок: ключи до открытия БД. Cache DB не нужна. | `lib/data/storage/secure_storage.dart:50`; `lib/data/storage/locker/*`; `locker_storage_path_util.dart`; новая migration routine при app-init / `DbLifecycleService`. | L | **H** |
| **7** | **QA на 24H2.** Проверить boot, unlock, import кошелька, export/share, deep links, auto-lock, crash reporting; проверить silent full-trust fallback и OS gating ниже 24H2. | Win11 24H2 agent + min-OS gate. | M | M |

## 5. Оценка масштаба

Оценка **бимодальная**, не плавный диапазон. Работа либо умирает за дни на одном из ранних шлюзов, либо превращается в многомесячное усилие с реальным шансом быть неотгружаемой.

| Workstream | Усилия (t-shirt) | Примерно person-weeks | Риск |
|---|---|---|---|
| **Эксперимент по безопасности (Шлюз −1)** | **S** | **~дни (0.2–0.6)** | **H — решающий kill-switch** |
| Фаза 0: 24H2 box + log + GPU go/no-go (вкл. native instrumentation) | M | 0.5–1.5 | **H** (может быть hard stop) |
| Манифест + build pipeline (fork/patch `msix`, reorder signing) | L | 1.5–3 | **H** |
| Runner / init / activation fixes | M | 0.5–1.5 | M |
| Filesystem / picker migration | M | 1–2 | **H** |
| Path relocation | M | 0.5–1.5 | **H** |
| Plugin remediation (вкл. вопрос сборки `mfa_locker`/`biometric_cipher`) | M–L | 1–2.5 | **H** |
| Secure-storage + DB data migration | L | 2–3 | **H** |
| QA на 24H2 + OS gating | M | 1–2 | M |

**Условный исход:**
- **(a) Если эксперимент по безопасности ИЛИ Фаза 0 проваливаются:** усилия **~дни**, ответ — **«не продолжать».**
- **(b) Только если ОБА шлюза пройдены:** применим диапазон **~8–16+ person-week** — и даже тогда **отгружаемость не решена** (принятие Store preview-tech, сроки GA). Если миграция вынуждает полный re-onboarding UX и/или переговоры со Store, верх диапазона может **превысить XL / быть по сути неограниченным**.

**Уверенность: низкая.** Preview-stage OS tech, непроверенный security payoff, несколько workstream с Risk=H, которые сам анализ помечает как возможно «полностью заблокированные» / «невозможные in-place». **Топ-3 того, что может всё сорвать:**
1. **Изоляция не блокирует распакованного атакующего того же пользователя** (Шлюз −1). Убивает всё усилие независимо от инженерии.
2. **ANGLE/GPU никогда не инициализируется** в AppContainer token (Фаза 0c). Если не решаемо — всё останавливается.
3. **Миграция данных невозможна in-place** (DPAPI/credential identity не пересекают границу), вынуждая **всех существующих Windows-пользователей к повторному вводу пароля / re-onboarding** — продуктовое/UX-решение, не только инженерия. (Плюс: Win32 App Isolation остаётся preview / Store не примет preview-tech package.)

## 6. Открытые неизвестные и prerequisites

Без машины Win11 24H2, init-лога и/или ответа Microsoft first-party на это не ответить:

- **Блокирует ли изоляция распакованного атакующего того же пользователя?** Единственная решающая неизвестная; сначала провести эксперимент Шлюза −1.
- **Точная причина белого экрана** — `app_container_init.log` с auth-gate и здесь недоступен. Самый ценный отсутствующий артефакт; шлюзует инженерную работу.
- **Может ли bundled ANGLE Flutter создать D3D11/WARP surface** под AppContainer token на 24H2. Решающая инженерная неизвестная.
- **Возвращает ли `path_provider_windows`** usable package-redirected store в AppContainer (вкл. поведение `getApplicationCacheDirectory()`), и может ли `sqlite3mc` открыть БД там.
- **Читается ли DPAPI `.dat` `flutter_secure_storage_windows 3.1.2`**, записанный full-trust-сборкой, из AppContainer — определяет copy/re-encrypt vs обязательный re-onboarding. (Также: перечислить, что реально хранит JSON blob `aw_secure_data` — статически не удалось.)
- **Компилируется/регистрируется ли `mfa_locker` на Windows без sub-plugin `biometric_cipher`**, или нужна forked/Windows-conditional сборка.
- **Восстанавливает ли 24H2 implicit file-dialog broker** `file_selector_windows`/`file_picker` именно для Flutter-приложения (Flutter-specific report отсутствует).
- **Доставляется ли `WTSRegisterSessionNotification`** AppContainer-процессу вообще (undocumented).
- **Даёт ли split build/pack `msix:3.16.12`** valid, signable package после ручного patch манифеста (signing post-repack; hash table, block map).
- **Даёт ли `windows-latest` CI build 26100+** — вероятно нет; заложить self-hosted/24H2 runner.
- **Компилирует ли форк `window_manager` (`d775b5d`)** global-hook paths — native source отсутствует на этом macOS-checkout.
- **Переживает ли `sentry`/crashpad named-pipe IPC** изоляцию named-object в AppContainer.
- **GA status Win32 App Isolation** после mid-2026 и примет ли Microsoft Store preview-stage isolated package.
- **Продуктовое решение: минимальная версия Windows**, которую мы готовы требовать (пол 24H2 для реальной изоляции vs silent full-trust fallback ниже).

## 7. Честная оговорка

**Даже если приложение безупречно работает в AppContainer, выгода для безопасности НЕ ДОКАЗАНА.** Вся предпосылка — что AppContainer переназначает credential `KeyCredentialManager` плагина `biometric_cipher` на Package SID и тем самым блокирует **распакованного атакующего того же пользователя** от переиспользования Hello credential по имени — не проверена и не может быть без эмпирического эксперимента на 24H2 из conclusion docs (`specs/.current/AW-2956/conclusion/`). Этот эксперимент — **Шлюз −1** и должен идти **до** любых вложений в упаковку/загрузку (§4, §5).

Две усиливающие честные точки:
- **Нет защиты для большинства текущих пользователей.** На основной массе install base (pre-24H2) пакет **молча работает в full trust** (§2), поэтому **изоляции вообще нет** для этих пользователей, пока они не обновятся до 24H2+.
- **Feasibility-сборка по плану не даёт ничего сверх AW-2957.** Фазы 0–6 поставляются с **исключённым** `biometric_cipher` — т.е. Hello unlock остаётся отключённым, ровно как в AW-2957, но за 8–16+ недель стоимости. Реальный продуктовый payoff (безопасное **повторное включение** Hello) зависит от прохождения эксперимента Шлюза −1; только тогда **поздняя** фаза снова включает `biometric_cipher`. **Если эксперимент провалится, isolated-but-no-Hello AppContainer-сборка строго хуже AW-2957 (та же безопасность, куда больше cost/risk) и не должна ship'иться.** Не давать ship'ить её под иллюзией прогресса и не oversell'ить AppContainer как fix, пока эксперимент не подтвердит payoff.

## 8. Источники

- App Isolation overview — https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-overview
- App Isolation release notes (build 26100.2161, 2024-10-24; implicit picker broker) — https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-release-notes
- AppContainer isolation (credential isolation, file/registry virtualization) — https://learn.microsoft.com/en-us/windows/win32/secauthz/appcontainer-isolation
- App Isolation packaging with Visual Studio (manifest contract) — https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-packaging-with-vs
- MSIX container model + capabilities — https://learn.microsoft.com/en-us/windows/msix/msix-container
- Public preview blog: improve Win32 app security via App Isolation — https://blogs.windows.com/windowsdeveloper/2023/06/14/public-preview-improve-win32-app-security-via-app-isolation/
- "Regular MSIX apps do not run in an AppContainer" — https://github.com/microsoft/WindowsAppSDK/discussions/410
- file_picker breakage (Won't Fix) — https://github.com/microsoft/microsoft-ui-xaml/issues/9557
- file picker E_ACCESSDENIED under partialTrust — https://github.com/microsoft/WindowsAppSDK/issues/3536
- Flutter UWP wind-down — https://github.com/flutter/flutter/issues/102172
- Flutter 3.3.0 release notes (UWP tooling removed) — https://docs.flutter.dev/release/release-notes/release-notes-3.3.0
- Flutter UWP for Xbox (unimplemented) — https://github.com/flutter/flutter/issues/137045
- ANGLE/D3D white-/black-screen engine init — https://github.com/flutter/flutter/issues/150546 · https://github.com/flutter/flutter/issues/88407 · https://github.com/flutter/flutter/issues/110948
- Flutter Windows building — https://docs.flutter.dev/platform-integration/windows/building
- Prior security conclusion (this repo) — `specs/.current/AW-2956/conclusion/02-proposed-solutions.md`, `04-action-plan.md`
