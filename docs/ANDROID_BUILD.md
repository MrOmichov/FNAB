# Android: текущая debug-сборка

**VERIFIED:** Godot 4.4.1 экспортирует проект через preset `Android` в
`dist/FNAB-debug.apk`. Сборка содержит ARMv7 и ARM64, запускается в альбомной
ориентации и подписана debug-ключом. Gradle не используется.

**VERIFIED:** доступны Android SDK `C:/Android/Sdk`, build-tools `35.0.1`,
Java 21 из `C:/Program Files/Android/Android Studio/jbr` и официальные Android
export templates Godot `4.4.1.stable`. В обычном редакторе эти SDK/Java paths
задаются в Editor Settings → Export → Android. Templates устанавливаются через
Manage Export Templates. Не хранить debug/release keystore и пароли в Git.

`export_presets.cfg` содержит временные `package/unique_name="org.mromichov.fnab"`,
`version/code=1`, `version/name="0.1"`. `project.godot` разрешает импорт ETC2/ASTC;
экспорт Android требует эту настройку даже при наличии текстур без VRAM compression.
Для публикации package/version и release-подпись нужно определить отдельно.

## Повторение сборки

После импорта проекта и настройки SDK/Java/templates:

```powershell
New-Item -ItemType Directory -Force dist | Out-Null
& 'C:/Godot_v4.4.1/Godot_v4.4.1-stable_win64_console.exe' `
    --headless --path . --export-debug Android 'dist/FNAB-debug.apk'
```

**VERIFIED:** в текущей sandbox-сессии Godot мог читать отдельные SDK-файлы,
но не открывать SDK-каталоги. Для сборки были скопированы только `platform-tools`
и `build-tools/35.0.1` в игнорируемую `.appdata/apk-sdk`; исходный SDK не изменялся.
Editor settings и Android templates размещены в `.appdata/apk/Godot`.
Системный temporary directory также вызвал ошибки сохранения и подписи; рабочий
запуск использовал локальный временный каталог:

```powershell
$env:APPDATA = Join-Path (Get-Location) '.appdata/apk'
$env:LOCALAPPDATA = $env:APPDATA
$env:TEMP = Join-Path (Get-Location) '.appdata/apk-tmp'
$env:TMP = $env:TEMP
$env:JAVA_HOME = 'C:/Program Files/Android/Android Studio/jbr'
$env:JAVA_TOOL_OPTIONS = '-Djava.io.tmpdir="' + $env:TEMP + '"'
& 'C:/Godot_v4.4.1/Godot_v4.4.1-stable_win64_console.exe' `
    --headless --path . --export-debug Android 'dist/FNAB-debug.apk'
```

Эти переменные действуют только в текущем PowerShell-процессе. SDK/Java settings
не входят в preset и остаются локальной настройкой машины.

## Проверка результата и ограничения

**VERIFIED (2026-10-06):** APK собран без `ERROR`/`WARNING` в финальном export log;
`apksigner verify --verbose` подтвердил подписи v1/v2/v3. Архив содержит
`AndroidManifest.xml`, `assets/project.binary`, библиотеки обоих ARM ABI.
Проверено отсутствие `.validation-tmp`, `.appdata`, `tests/`, `docs/` в APK.
Выбор build-tools `35.0.1` вместо соответствующих target SDK 34 сопровождается
информационным сообщением экспортера; экспорт и проверка подписи успешны.

**UNKNOWN:** запуск на Android-устройстве, производительность, звук и удобство
touch-управления. APK не устанавливался. `scripts/camera_system.gd` открывает
планшет и пульт по `mouse_entered`; `scripts/Camera.gd` двигает вид по положению
мыши. Это существующее управление требует ручной проверки на телефоне.

## Release APK и подпись

**VERIFIED (2026-10-06):** дополнительно собран `dist/FNAB-release.apk` через
`--export-release Android`. Размер — 154 504 012 байт. Подписи v1/v2/v3 подтверждены,
`assets/project.binary` присутствует. `aapt2 dump badging` подтвердил package
`org.mromichov.fnab`, version `0.1` / code `1`, оба ARM ABI и отсутствие
`application-debuggable`. Ключи, credentials, tests и cache в APK отсутствуют.
Финальный export log не содержит `ERROR`/`WARNING`.

Отдельный release-ключ создан в `.appdata/signing/fnab-release.keystore`, alias
`fnab-release`. Случайный пароль сохранён в локальном
`.appdata/signing/release-signing.json`. Оба файла исключены из Git, не находятся
в APK и не публикуются. Для следующих обновлений сохранить резервную копию
**обоих файлов** в личном защищённом хранилище: новый ключ не заменяет этот ключ
для обновления уже установленной release-сборки. Debug APK подписан другим ключом;
установка release поверх него потребует удаления debug-приложения.

Release export использует официальные [переменные окружения Godot 4.4.1](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/android/export/export_plugin.h#L39-L46)
для credentials; пароль не записывается в `export_presets.cfg`:

```powershell
# Сначала настроить SDK/templates и локальные TEMP/Java как выше.
$signing = Get-Content '.appdata/signing/release-signing.json' -Raw | ConvertFrom-Json
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = Join-Path (Get-Location) $signing.keystore
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $signing.alias
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $signing.password
try {
    & 'C:/Godot_v4.4.1/Godot_v4.4.1-stable_win64_console.exe' `
        --headless --path . --export-release Android 'dist/FNAB-release.apk'
} finally {
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_USER
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    $signing = $null
}
```

**VERIFIED:** `aapt2` сообщает о ссылке на отсутствующий `themed_icon.xml` в
Android template; подпись и APK export проходят. **UNKNOWN:** влияние этого
предупреждения на themed launcher icon; запуск release на устройстве ещё не проверен.

`dist/`, `.appdata/` и типовые signing-key файлы исключены из Git.
Release APK создан локально; в магазин или на сервер не публиковался.
