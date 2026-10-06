extends CanvasLayer

## Presentation layer for the first-night loop. Night owns phase, clock and
## outcome; this script only displays them and forwards explicit UI actions.
@export var night: Node

var _root: Control
var _card: PanelContainer
var _title: Label
var _body: Label
var _primary: Button
var _secondary: Button
var _fullscreen_art: TextureRect
var _blackout: ColorRect
var _death_timer: Timer
var _jumpscare_timer: Timer
var _jumpscare_frames: Array[Texture2D] = []
var _jumpscare_index := 0
var _visible_state := ""
var _pending_won := false
var _warning_hint: Label
var _jumpscare_death_path := ""
var _newspaper: Control
var _newspaper_dismissed := false
var _save_notice_panel: PanelContainer
var _save_notice_label: Label
var _progress_save_error := ""

const JUMPSCARE_FOLDERS = {"sann": "сан", "dog": "пес", "berry": "берри", "blacky": "блеки", "old_creeper": "ок"}
const JUMPSCARE_LAST_FRAME = {"sann": 10, "dog": 13, "berry": 10, "blacky": 10, "old_creeper": 12}
const DEATH_IMAGES = {
	"sann": "смерть от Санн.png",
	"dog": "смерть от Пса.png",
	"berry": "Смерть от Берри.png",
	"blacky": "смерть от Блеки.png",
	"old_creeper": "Смерть от ОК.png",
}

func _ready() -> void:
	_build_overlay()
	if night == null:
		push_error("NightPresentation requires the Night node.")
		return
	if night.has_signal("phase_changed"):
		night.phase_changed.connect(_on_phase_changed)
	if night.has_signal("time_changed"):
		night.time_changed.connect(_on_time_changed)
	if night.has_signal("outcome_reached"):
		night.outcome_reached.connect(_on_outcome_reached)
	if night.has_signal("progress_save_failed"):
		night.progress_save_failed.connect(_on_progress_save_failed)
	var ai := night.get("sann_ai") as Node
	if ai != null:
		if ai.has_signal("warning_started"):
			ai.warning_started.connect(_on_warning_started)
		if ai.has_signal("defended"):
			ai.defended.connect(_on_warning_ended)
	_fullscreen_art = TextureRect.new()
	_fullscreen_art.name = "OutcomeArt"
	_fullscreen_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fullscreen_art.stretch_mode = TextureRect.STRETCH_SCALE
	_fullscreen_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_art.visible = false
	add_child(_fullscreen_art)
	_blackout = ColorRect.new()
	_blackout.name = "PowerOutBlackout"
	_blackout.color = Color.BLACK
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.visible = false
	add_child(_blackout)
	_build_newspaper()
	_death_timer = Timer.new()
	_death_timer.one_shot = true
	_death_timer.timeout.connect(_show_death_result)
	add_child(_death_timer)
	_jumpscare_timer = Timer.new()
	_jumpscare_timer.one_shot = true
	_jumpscare_timer.wait_time = 0.133
	_jumpscare_timer.timeout.connect(_advance_jumpscare)
	add_child(_jumpscare_timer)
	_build_save_notice()
	_on_phase_changed(int(night.get("phase")))

func _build_newspaper() -> void:
	_newspaper = Control.new()
	_newspaper.name = "Newspaper"
	_newspaper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_newspaper.mouse_filter = Control.MOUSE_FILTER_STOP
	_newspaper.visible = false
	add_child(_newspaper)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_newspaper.add_child(background)
	var paper := TextureButton.new()
	paper.name = "Paper"
	paper.texture_normal = preload("res://assets/Ремейк игры/камера/газета.jpg")
	paper.ignore_texture_size = true
	paper.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.pressed.connect(_dismiss_newspaper)
	_newspaper.add_child(paper)
	var continue_button := Button.new()
	continue_button.name = "Continue"
	continue_button.text = "Продолжить"
	continue_button.anchor_left = 0.5
	continue_button.anchor_right = 0.5
	continue_button.anchor_top = 1.0
	continue_button.anchor_bottom = 1.0
	continue_button.offset_left = -160
	continue_button.offset_right = 160
	continue_button.offset_top = -88
	continue_button.offset_bottom = -26
	continue_button.add_theme_font_size_override("font_size", 26)
	continue_button.pressed.connect(_dismiss_newspaper)
	_newspaper.add_child(continue_button)

func _dismiss_newspaper() -> void:
	if _visible_state != "newspaper" or night == null or int(night.get("phase")) != 0:
		return
	_newspaper_dismissed = true
	_newspaper.visible = false
	_on_phase_changed(0)

func _build_save_notice() -> void:
	_save_notice_panel = PanelContainer.new()
	_save_notice_panel.name = "ProgressSaveNotice"
	_save_notice_panel.anchor_left = 0.5
	_save_notice_panel.anchor_right = 0.5
	_save_notice_panel.offset_left = -520
	_save_notice_panel.offset_top = 16
	_save_notice_panel.offset_right = 520
	_save_notice_panel.offset_bottom = 112
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.04, 0.025, 0.96)
	style.border_color = Color(1.0, 0.45, 0.28, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_save_notice_panel.add_theme_stylebox_override("panel", style)
	_save_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_notice_panel.visible = false
	add_child(_save_notice_panel)
	_save_notice_label = Label.new()
	_save_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_save_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_notice_label.add_theme_font_size_override("font_size", 20)
	_save_notice_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.76))
	_save_notice_label.text = "Не удалось записать прогресс кампании."
	_save_notice_panel.add_child(_save_notice_label)

func _on_progress_save_failed(message: String) -> void:
	_progress_save_error = message.strip_edges()
	if _visible_state in ["won", "lost"]:
		_show_progress_save_notice()

func _show_progress_save_notice() -> void:
	if _save_notice_panel == null:
		return
	var detail := _progress_save_error
	_save_notice_label.text = "Прогресс не сохранён. %s" % detail if not detail.is_empty() else "Прогресс не сохранён. Проверьте свободное место и права записи."
	_save_notice_panel.visible = true

func _build_overlay() -> void:
	_root = Control.new()
	_root.name = "PresentationOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.anchor_left = 0.5
	_card.anchor_top = 0.5
	_card.anchor_right = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -410
	_card.offset_top = -330
	_card.offset_right = 410
	_card.offset_bottom = 330
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.045, 0.96)
	style.border_color = Color(0.72, 0.16, 0.08, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	_card.add_theme_stylebox_override("panel", style)
	_root.add_child(_card)
	_warning_hint = Label.new()
	_warning_hint.name = "SannWarningHint"
	_warning_hint.anchor_left = 0.5
	_warning_hint.anchor_right = 0.5
	_warning_hint.offset_left = -580
	_warning_hint.offset_top = 28
	_warning_hint.offset_right = 580
	_warning_hint.offset_bottom = 100
	_warning_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_hint.add_theme_font_size_override("font_size", 26)
	_warning_hint.add_theme_color_override("font_color", Color(1.0, 0.83, 0.28))
	_warning_hint.text = "Санн слева: наведите курсор на левый край экрана и нажмите на нос. Закройте планшет перед защитой."
	_warning_hint.visible = false
	add_child(_warning_hint)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_card.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 42)
	column.add_child(_title)
	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 24)
	column.add_child(_body)
	_primary = Button.new()
	_primary.custom_minimum_size = Vector2(0, 62)
	_primary.add_theme_font_size_override("font_size", 26)
	column.add_child(_primary)
	_secondary = Button.new()
	_secondary.custom_minimum_size = Vector2(0, 52)
	_secondary.add_theme_font_size_override("font_size", 22)
	column.add_child(_secondary)
	_primary.pressed.connect(_on_primary_pressed)
	_secondary.pressed.connect(_on_secondary_pressed)

func _on_phase_changed(phase: int) -> void:
	# Core API phase values: INTRO=0, RUNNING=1, POWER_OUT=2, WON=3, LOST=4.
	match phase:
		0:
			var cfg = night.get("config")
			var night_number := int(cfg.get("night_number")) if cfg != null else 1
			if night_number == 1 and not _newspaper_dismissed:
				_hide_card()
				_visible_state = "newspaper"
				_newspaper.visible = true
				_newspaper.get_node("Continue").grab_focus()
				return
			_newspaper.visible = false
			var end_hour := int(cfg.get("end_hour")) if cfg != null else 7
			var instructions := "Смена длится до %02d:00.\nПланшет — кнопка внизу по центру. Пульт вентиляторов — слева внизу." % end_hour
			if cfg != null and cfg.sann_level > 0:
				instructions += "\nСанн раскачивается: закройте планшет, повернитесь влево и нажмите на нос."
			if cfg != null and (cfg.dog_level > 0 or cfg.berry_level > 0):
				instructions += "\nПёс и Берри у двери: закройте дверь и дождитесь ухода."
			if cfg != null and cfg.blacky_level > 0:
				instructions += "\nБлэки в вентиляции: включите вентилятор с той стороны, откуда он ползёт."
			if cfg != null and cfg.old_creeper_level > 0:
				instructions += "\nОК: следите за камерой 2 и используйте шокер. Он расходует энергию и имеет откат."
			_show_card("intro", "НОЧЬ %d" % night_number, instructions, "Начать смену", "В меню")
		1:
			_hide_card()
		2:
			_hide_card()
			_blackout.visible = true
		3:
			_hide_card()
		4:
			_hide_card()
		_:
			_hide_card()
	if phase != 1 and _warning_hint != null:
		_warning_hint.visible = false

func _on_time_changed(hours: int, minutes: int) -> void:
	if _visible_state == "won":
		_title.text = "%02d:%02d — НОЧЬ ПРОЙДЕНА" % [hours, minutes]

func _on_warning_started() -> void:
	if night != null and int(night.get("phase")) == 1:
		_warning_hint.visible = true

func _on_warning_ended() -> void:
	_warning_hint.visible = false

func _on_outcome_reached(won: bool, reason: String) -> void:
	_pending_won = won
	if won:
		_blackout.visible = false
		_fullscreen_art.visible = false
		var ending: CanvasLayer = night.get_node_or_null("NightEnd")
		if ending != null:
			ending.visible = true
			# The legacy sequence visibly counts 5 then 6, so show only its
			# truthful terminal "Ночь пройдена" frame for the 07:00 outcome.
			var player := ending.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if player != null:
				player.stop()
			var end_art := ending.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if end_art != null and end_art.sprite_frames != null:
				end_art.animation = "default"
				end_art.stop()
				end_art.frame = end_art.sprite_frames.get_frame_count("default") - 1
		_death_timer.start(4.0)
		return
	if JUMPSCARE_FOLDERS.has(reason):
		_blackout.visible = false
		_show_character_jumpscare(reason)
	else:
		_blackout.visible = false
		_fullscreen_art.texture = load("res://assets/Ремейк игры/аниматроники и смерти/после смерти/ру/смерть от  конца энергии.png")
		_fullscreen_art.modulate = Color.WHITE
		_fullscreen_art.visible = true
		_death_timer.start(2.0)

func _show_sann_jumpscare() -> void:
	_show_character_jumpscare("sann")

func _show_character_jumpscare(reason: String) -> void:
	_jumpscare_frames.clear()
	_jumpscare_death_path = "res://assets/Ремейк игры/аниматроники и смерти/после смерти/ру/" + DEATH_IMAGES[reason]
	for i in range(1, int(JUMPSCARE_LAST_FRAME[reason]) + 1):
		var frame_path := "res://assets/Ремейк игры/аниматроники и смерти/скримеры/%s/%d.png" % [JUMPSCARE_FOLDERS[reason], i]
		# Original OC artwork has no frame 3; do not load a nonexistent asset.
		if ResourceLoader.exists(frame_path):
			_jumpscare_frames.append(load(frame_path) as Texture2D)
	if _jumpscare_frames.is_empty():
		_fullscreen_art.texture = load(_jumpscare_death_path)
		_fullscreen_art.visible = true
		_death_timer.start(2.0)
		return
	_jumpscare_index = 0
	_fullscreen_art.texture = _jumpscare_frames[0]
	_fullscreen_art.modulate = Color.WHITE
	_fullscreen_art.visible = true
	_jumpscare_timer.start()

func _advance_jumpscare() -> void:
	_jumpscare_index += 1
	if _jumpscare_index < _jumpscare_frames.size():
		_fullscreen_art.texture = _jumpscare_frames[_jumpscare_index]
		_jumpscare_timer.start()
		return
	_fullscreen_art.texture = load(_jumpscare_death_path)
	_death_timer.start(2.0)

func _exit_tree() -> void:
	if _death_timer != null:
		_death_timer.stop()
	if _jumpscare_timer != null:
		_jumpscare_timer.stop()

func _show_death_result() -> void:
	_fullscreen_art.visible = false
	var ending: CanvasLayer = night.get_node_or_null("NightEnd")
	if ending != null:
		ending.visible = false
	if not _pending_won:
		_show_card("lost", "СМЕНА НЕ ЗАВЕРШЕНА", "Ночь окончена.", "Повторить", "В меню")
	else:
		var cfg = night.get("config")
		var end_hour := int(cfg.get("end_hour")) if cfg != null else 7
		var current_minutes := int(night.get("minutes"))
		_show_card("won", "%02d:%02d — НОЧЬ ПРОЙДЕНА" % [end_hour, current_minutes], "Смена завершена.", "В меню", "Сыграть ещё раз")
	if not _progress_save_error.is_empty():
		_show_progress_save_notice()

func _show_card(state: String, title: String, body: String, primary: String, secondary: String) -> void:
	_visible_state = state
	_root.visible = true
	_card.visible = true
	_title.text = title
	_body.text = body
	_body.visible = not body.is_empty()
	_primary.text = primary
	_primary.visible = not primary.is_empty()
	_secondary.text = secondary
	_secondary.visible = not secondary.is_empty()

func _hide_card() -> void:
	_visible_state = ""
	_root.visible = false
	if _newspaper != null:
		_newspaper.visible = false

func _on_primary_pressed() -> void:
	match _visible_state:
		"intro":
			if night != null:
				night.begin_night()
		"won", "lost":
			if _visible_state == "won":
				get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
			else:
				_replay_night()

func _on_secondary_pressed() -> void:
	if _visible_state in ["intro", "lost", "won"]:
		if _visible_state == "won":
			_replay_night()
		else:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _replay_night() -> void:
	var campaign_run: bool = night != null and night.is_campaign_run()
	if campaign_run:
		var cfg = night.get("config")
		var night_number := int(cfg.get("night_number")) if cfg != null else 1
		if not SaveGame.prepare_night(night_number):
			_progress_save_error = str(SaveGame.last_error)
			_show_progress_save_notice()
			return
	var error := get_tree().reload_current_scene()
	if error != OK:
		if campaign_run:
			SaveGame.consume_night_request()
		_progress_save_error = "Не удалось перезапустить ночь. Код ошибки: %d" % error
		_show_progress_save_notice()
