=== SUMMARY ===
biometric_cipher (Android): предаудитные правки одним PR — setKeySize(256) вместо дефолтных 128 бит, честный getTPMStatus(), гард API 28 для setIsStrongBoxBacked, мелочи

=== DESCRIPTION (Jira wiki) ===
h2. Описание

При генерации биометрического ключа-обёртки в AndroidKeyStore размер ключа нигде не задаётся: {{setKeySize(256)}} не вызывается ни в одном месте пакета {{biometric_cipher}} (проверено по коду), поэтому действует дефолт Keystore — *128 бит*. В результате 256-битный мастер-ключ оборачивается более слабым 128-битным AES-ключом.

Задача: при построении {{KeyGenParameterSpec}} в {{SecureRepositoryImpl.generateKey()}} ({{packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/repositories/SecureRepositoryImpl.kt}}, строки 38–44) явно задать размер ключа:

{code:kotlin}
val keyGenParameterSpecBuilder = KeyGenParameterSpec.Builder(
    keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
    .setRandomizedEncryptionRequired(true)
    .setKeySize(256) // ← добавить
{code}

По отчёту исправление — одна строка. Что важно учесть (секция 5 отчёта, «Пути модификации шифрования: Android»):
* Формат шифротекста не меняется; новые ключи станут 256-битными.
* Уже существующие ключи останутся 128-битными: достаточно разового пере-включения биометрии (выключить и включить) — мастер-ключ восстанавливается по парольной обёртке. Переимпорт кошельков *не требуется* (поправка отчёта к исходной идее AW-3303 про changelog-диалог: текст в нём должен просить о меньшем). С версионированным форматом хранилища (секция 4 отчёта) обновление можно позже сделать автоматическим при первом входе по паролю.

h3. Той же задачей (одним PR) — остальные быстрые правки секции 5

* *Сделать {{getTPMStatus()}} честным.* Сейчас он захардкожен — {{SecureServiceImpl.kt}}, строка 13: {{override fun getTPMStatus(): TPMStatus = TPMStatus.SUPPORTED}}. Но ключи AndroidKeyStore не обязаны быть аппаратными: на устройстве без TEE ключ будет софтверным, а плагин всё равно отрапортует «поддерживается» — и гейт в {{MFALocker.setupBiometry}}, который должен отсекать такие устройства, не сработает никогда. Фикс: {{KeyInfo.isInsideSecureHardware}} (API 23+) / {{getSecurityLevel()}} (API 31+).
* *Закрыть крэш на API 23–27.* Плагин объявляет {{minSdk 23}} ({{android/build.gradle}}, строка 68), но безусловно вызывает {{setIsStrongBoxBacked}} ({{SecureRepositoryImpl.kt}}, строка 44) — метод API 28 ({{@RequiresApi}} — только линтер-аннотация, в рантайме не защищает). На API 23–27 это {{NoSuchMethodError}} при генерации ключа. Фикс: гард по версии плюс либо поднять {{minSdk}} до 28, либо честно отвечать «не поддерживается» ниже 28 (правка про честный {{getTPMStatus()}} сделает это естественно).
* *Мелочи тем же PR:* удалить недостижимую ветку device-credential (ключ генерируется под {{AUTH_DEVICE_CREDENTIAL}}, но промпт жёстко требует {{BIOMETRIC_STRONG}}) и заменить {{setUserAuthenticationValidityDurationSeconds(0)}} на документированное {{-1}} для API < 30.

h2. AC

* В {{KeyGenParameterSpec.Builder}} ({{SecureRepositoryImpl.generateKey()}}) вызывается {{setKeySize(256)}}; для свежесозданного ключа {{KeyInfo.getKeySize()}} возвращает 256.
* Формат шифротекста не изменился: данные, зашифрованные существующим 128-битным ключом, продолжают расшифровываться; после пере-включения биометрии создаётся 256-битный ключ, encrypt/decrypt работают штатно.
* {{getTPMStatus()}} возвращает реальный статус аппаратной защиты ключей (через {{KeyInfo.isInsideSecureHardware}} на API 23+ / {{getSecurityLevel()}} на API 31+), а не константу {{TPMStatus.SUPPORTED}}: на устройстве/эмуляторе без TEE — «не поддерживается».
* Генерация ключа на API 23–27 не падает с {{NoSuchMethodError}}: {{setIsStrongBoxBacked}} вызывается только на API ≥ 28 (либо {{minSdk}} поднят до 28 — по решению из «Недостающих деталей»).
* Недостижимая ветка {{AUTH_DEVICE_CREDENTIAL}} удалена; для API < 30 используется {{setUserAuthenticationValidityDurationSeconds(-1)}} вместо {{0}}.
* Юнит-тесты пакета обновлены под новое поведение и проходят ({{SecureRepositoryTest}}, {{SecureServiceTest}}).

h2. Контекст

Задача покрывает правки №1–4 из списка «быстрые правки до аудита» в секции 5 («Пути модификации шифрования: Android») отчёта «AW-3303 Криптоотчёт». Android-бэкенд построен по каноническому паттерну (ключ в AndroidKeyStore / StrongBox, {{setUserAuthenticationRequired(true)}} с нулевым таймаутом, {{Cipher}} через {{BiometricPrompt.CryptoObject}}, IV генерирует Keystore) — база корректна, вопросы к деталям, которые и закрывает эта задача. Отчёт рекомендует выполнить все правки до внешнего аудита одним небольшим PR; по сводке отчёта ни одна из них не ломает формат, цена — от одной строки до «низкой», рекомендация — «делать».

h2. Недостающие детали

* Механика обновления существующих 128-битных ключей в рамках этой задачи не зафиксирована: ограничиться просьбой пере-включить биометрию (например, текстом в changelog-диалоге) или сразу закладывать автоматический re-wrap — по отчёту автоматика требует версионированного формата хранилища (секция 4) и в объём этой правки не входит.
* Для крэша на API 23–27 отчёт даёт развилку — поднять {{minSdk}} до 28 или честно отвечать «не поддерживается» ниже 28; выбор варианта за этой задачей не зафиксирован.

Источник: артефакт «AW-3303 Криптоотчёт», секция 5 «Пути модификации шифрования: Android» — https://claude.ai/code/artifact/a7f30a74-dfea-48bf-b9c2-0c9aa7899bea; код: packages/biometric_cipher/android

https://jira.int.agrd.dev/browse/AW-3333
