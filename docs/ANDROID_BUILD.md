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

`dist/` и `.appdata/` исключены из Git. APK — проверочный debug-артефакт,
не опубликованный release.
