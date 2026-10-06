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
	_death_timer = Timer.new()
	_death_timer.one_shot = true
	_death_timer.timeout.connect(_show_death_result)
	add_child(_death_timer)
	_jumpscare_timer = Timer.new()
	_jumpscare_timer.one_shot = true
	_jumpscare_timer.wait_time = 0.133
	_jumpscare_timer.timeout.connect(_advance_jumpscare)
	add_child(_jumpscare_timer)
	_on_phase_changed(int(night.get("phase")))

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

func _on_primary_pressed() -> void:
	match _visible_state:
		"intro":
			if night != null:
				night.begin_night()
		"won", "lost":
			if _visible_state == "won":
				get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
			else:
				get_tree().reload_current_scene()

func _on_secondary_pressed() -> void:
	if _visible_state in ["intro", "lost", "won"]:
		if _visible_state == "won":
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
