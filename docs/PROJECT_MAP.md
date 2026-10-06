# Карта существующего проекта FNAB

Документ описывает текущие исходники после подключения маршрутных AI, вентиляторов и шокера. Историческая расстановка из `test()` и старые сборки в `dist/` не считаются текущей игрой.

- **VERIFIED** — проверено по файлам, символам или указанному тесту.
- **LIKELY** — временная трактовка замысла/баланс, разрешённая автором.
- **UNKNOWN** — неизвестно или не проверено. Подключение в коде не означает слухового или визуального плейтеста.

Связанные документы: [ARCHITECTURE.md](ARCHITECTURE.md), [GAMEPLAY.md](GAMEPLAY.md), [GAMEPLAY_PARAMETERS.md](GAMEPLAY_PARAMETERS.md), [AUDIO_MAP.md](AUDIO_MAP.md), [VISUAL_TESTING.md](VISUAL_TESTING.md) (запуск, снимки, эталоны и задание визуальному тестировщику). Читать по теме задачи.

## Точка входа и переходы

**VERIFIED:** `project.godot::run/main_scene` с UID `uid://c0cdkekkale33` соответствует `scenes/MainMenu.tscn`. Godot 4.4.1; проект задаёт функции 4.4/Mobile, viewport 1920×1080 и растяжение viewport.

`Main_menu.gd::_on_new_game_button_pressed()` устанавливает N1 и загружает Night. Новая ночь сначала INTRO, ждёт явного старта. В N1 `NightPresentation._build_newspaper()` показывает газету; `_dismiss_newspaper()` переводит только UI к инструкции. N2–N6 пропускают газету. Затем RUNNING → WON либо LOST; POWER_OUT — промежуточная фаза перед проигрышем или победой. Экран результата позволяет повторить сцену или вернуться в меню. `SaveGame` записывает контрольные точки между ночами; Continue загружает сохранённый профиль. Победа открывает следующий профиль вплоть до N6. Extra не подключён; Exit завершает процесс.

## Сцены и скрипты

Все строки **VERIFIED** по исходникам; новые узлы и экспортированные ссылки следует проверять непосредственно в сценах.

| Сцена | Состав / прикреплённые скрипты |
|---|---|
| `scenes/MainMenu.tscn` | CanvasLayer + `scripts/Main_menu.gd`; кнопки, Computer/Area2D, Timer |
| `scenes/Night.tscn` | Node2D + `scripts/Night.gd`; конфигурация N1, Office, CameraSystem, Camera2D, Animatronics/SannAI и RouteAI, NightEnd, NightPresentation, NightAudio |
| `scenes/Office.tscn` | Офисный фон, постер, дверной проём, Door + `door.gd`, DoorButton + `door_button.gd`, представление Санна |
| `scenes/CameraSystem.tscn` | CanvasLayer + `camera_system.gd`; планшет, пульт, семь кнопок камер, две кнопки вентиляторов, шокер/откат, HUD, экземпляр CameraPicture |
| `scenes/CameraPicture.tscn` | Sprite2D + `camera_picture.gd`; фон, layer1–layer5 и camera_noise |

Дополнительные скрипты:
- `scripts/sann_ai.gd`: цикл атаки без собственной обработки кадров.
- `scripts/sann_view.gd`: изображения, позы предупреждения, область носа и запрос защиты.
- `scripts/night_presentation.gd`: инструкции, исходы, показ скримера/результата и действия кнопок.
- `scripts/night_audio.gd`: сигналы → AudioStreamPlayers.
- `scripts/Camera.gd`: панорамирование офиса, не камеры наблюдения.
- `scripts/route_ai.gd`: движение и предупреждения ОК, Пса, Берри и Блэки; `reset()`, `advance()`, `shock_old_creeper()`, `stop()`.
- `scripts/dog_ai.gd`, `old_creeper_ai.gd`: исторические заготовки; рабочий AI находится в RouteAI.

## Resources и ассеты

**VERIFIED:** `scripts/night_config.gd::NightConfig` — Resource конфигурации; `resources/night_1.tres` использует его значения по умолчанию. Значения включают номер/конец ночи, темп, энергию, уровни, тайминги всех AI и шокер. `resources/night_2.tres`–`night_6.tres` задают уровни из таблицы DOCX и выбираются одноразовым запросом SaveGame при продолжении кампании. `scripts/animatronic_routes.gd::AnimatronicRoutes`, `resources/animatronic_routes.tres` задают четыре маршрута; manager предоставляет прежние имена через getters. Runtime-состояние хранится в узлах, не в Resource.

Существующие встроенные ресурсы сцен: SpriteFrames двери/планшета/пульта/шума/окончания; AnimationLibrary и метод-трек `night_end`; AtlasTexture кнопок; RectangleShape2D для областей ввода. Изображения и звуки находятся в `assets/Ремейк игры/`.

**VERIFIED:** 33 прежние ссылки камер исправлены на существующие изображения с UID из целевых `.import`. Текущие семейства под `assets/Ремейк игры/камера/`: `планшет/планшет/`, `планшет/батарейка/`, `планшет/расход/`, `кнопки/кнопки переключения камер/`, `помехи фон/`. Ссылок на отсутствующие `assets/camera_system/` и `assets/camera_noise/` больше нет.

## Autoload и модель комнат

**VERIFIED:** `project.godot::[autoload]` подключает Global (`global.gd`), AnimatronicMgnt (`animatronic_mgnt.gd`) и SaveGame (`save_game.gd`). SaveGame владеет общеприложенческим прогрессом и JSON в `user://progress.json`; подробности и источники будущих полей — в [SAVE_SYSTEM.md](SAVE_SYSTEM.md).

Global содержит номер ночи и прежние сигналы энергии. AnimatronicMgnt содержит `Rooms`, четыре позиции/индекса/маршрута, стадии ОК и флаги Берри/Блэки. `reset_for_night()` сбрасывает индексы и позиции к началу маршрутов при каждом входе в Night. `reset_character()` применяется после защиты; `advance_character()` меняет индекс и позицию, выбирая вложенную ветку равновероятно. Сигналы `location_changed`, `posture_changed`, `old_creeper_state_changed` обновляют открытый вид камеры.

Rooms — enum ID, а не комнатные сцены или граф:
`NONE=0, WORKSHOP=1, EXTRA_WORKSHOP=2, STAGE=3, ENTRANCE=4, MAIN_HALL=5, KITCHEN=6, HALLWAY=7, HALLWAY_PASSAGE=8, LEFT_VENT=9, RIGHT_VENT=10, OFFICE=11`.

Санн — отдельный офисный AI; его состояния принадлежат SannAI, он не добавляет фиктивный маршрут в старый менеджер. Общего базового класса аниматроника нет. Блэки — медведь, Берри — заяц (подтверждение автора).

## Таймеры и время

**VERIFIED:**
- `MainMenu/Timer`: 0,7 с, случайное изображение компьютера, остановка на hover.
- `Night/Timer`: старый узел остановлен; `_on_timer_timeout()` оставлен для существующего соединения и не двигает игру.
- `DogTimer`: остановлен; обработчика AI нет.
- `OldCreeperTimer`: не запускается.
- `Night._process()` → `advance(delta)`: единственный источник времени для часов, энергии, отката шокера, SannAI и RouteAI. RouteAI не запускает собственный Timer.
- Таймеры представления используются для смены предупреждающих поз/показа результата, а не для решений о победе/атаке.

Точные переходы и сигналы: [ARCHITECTURE.md](ARCHITECTURE.md). Маршруты и виды камер: [GAMEPLAY.md](GAMEPLAY.md).

## Незавершённый и неиспользуемый код

**VERIFIED:** `AnimatronicMgnt.next()` теперь совместимая обёртка `advance_character()`, а не прежний неисправный метод. Исторические Dog/Old Creeper скрипты не управляют действующими AI. `Camera.gd::_calculate_parameters()` не вызывается и содержит исторический расчёт с недействительным `Sprite2D.size`; обработчик изменения viewport оставлен пустым, текущий `_process()` читает размеры напрямую. Сохранения и открытие следующих профилей через Continue реализованы; нет автоматического перехода к следующей ночи, сюжетной цепочки мини-игр/концовок, Phone Guy и случайных ночных звуков. Вентиляторы и шокер реализованы, но исходный баланс неполон.

Встроенный `GDScript_3gt48` в CameraSystem содержит пустой обработчик; он не является игровым контроллером. `Office/Area2D` не имеет реализованной роли. Старая анимация `NightEnd/night_end` содержит переход 5→6 (визуально проверены кадры 1 и 7), поэтому для победы в 07:00 не используется. **UNKNOWN:** назначение исторических заготовок и соответствие экспортов `dist/` текущему коду.

**VERIFIED:** найденный review баг `consumption_count` исправлен: видимость учитывает открытие/закрытие планшета. Три regression-проверки покрывают скрытый планшет, открытый планшет и обновление расхода после закрытия.

## Материалы о замысле

**VERIFIED:** `assets/Ремейк игры/мегапомятка.docx` содержит описания ночей и таблицу уровней; `помятка*.txt` в подпапках — частные правила; `FNAB.md` — идеи/TODO. `сделано или нет.xlsx` по заголовку учитывает незавершённое «из нарисованного», а не готовность кода.

Таблица N1: Берри/Блэки/Пёс/Санн/ОК = 0/0/0/1/0. **LIKELY:** уровень 0 отключает соответствующий SannAI/маршрутный AI; это временная реализация разрешённого баланса. Правило 07:00 и старты из маршрутов прямо подтверждены автором. Остальные допущения перечислены в GAMEPLAY_PARAMETERS.

## Проверка

**VERIFIED:** текущие исходники проверены в изолированной копии Godot 4.4.1: `tests/test_night.gd` — 175 проверок, 0 ошибок assertions; `tests/test_route_ai.gd` — 78 проверок, 0 ошибок assertions. Night загружался настоящей сценой с экспортированными ссылками. `git diff --check` чист. Read-only review подтвердил исправление счётчика. При завершении N1 тестового процесса остаются предупреждения ObjectDB/resources still in use; маршрутный набор завершился без этих предупреждений. Причина N1 warnings не установлена. Редакторский scan не сообщил ошибок GDScript, но сообщил Unrecognized UID для существующего `project.godot::config/icon` (`uid://dpuigcs8heeq1`); устаревший UID заменён существующим путём PNG в настройках проекта для Android-экспорта.

После импорта: `Godot_v4.4.1-stable_win64_console.exe --headless --path <project> --script res://tests/test_night.gd`, затем `res://tests/test_route_ai.gd`. Тесты вызывают обработчики и проверяют состояние; это не физические клики и не прослушивание. **UNKNOWN:** ручное прохождение, звуковой микс, обычный рендеринг результатов и баланс следующих ночей.

**VERIFIED (2026-10-07, газета):** актуальные project/scenes/scripts/resources/tests совпали с изолированной копией по SHA-256 (53 файла). Godot 4.4.1 editor scan — exit 0; `test_night.gd` — 182/182, `test_route_ai.gd` — 78/78, оба exit 0. Проверены N1, повтор, двойной Continue, отсутствие газеты в N2 и замороженный INTRO. При завершении остаются диагностические warnings ObjectDB/resources; причина не установлена. Визуально проверен переход газета → инструкция → офис; см. VISUAL_TESTING.md.
