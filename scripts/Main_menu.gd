extends CanvasLayer

var computer_list = [
		"res://assets/Ремейк игры/Меню/Комп(нахер Берри))/комп выкл.png",
		"res://assets/Ремейк игры/Меню/Комп(нахер Берри))/комп ерорр.png",
		"res://assets/Ремейк игры/Меню/Комп(нахер Берри))/комп л.png",
		"res://assets/Ремейк игры/Меню/Комп(нахер Берри))/комп ок.png", 
		"res://assets/Ремейк игры/Меню/Комп(нахер Берри))/комп я.png",
	]

# TODO Выбор ночи
@onready var new_game_button = $Buttons/VBoxContainer/NewGameButton
@onready var continue_button = $Buttons/VBoxContainer/ContinueButton
@onready var extra_button = $Buttons/VBoxContainer/ExtraButton
@onready var exit_button = $Buttons/ExitButton
@onready var computer = $"Computer"

const NIGHT_SCENE := "res://scenes/Night.tscn"
var _save_error_label: Label

func _ready():
	continue_button.connect("pressed", _on_continue_button_pressed)
	new_game_button.connect("pressed", _on_new_game_button_pressed)
	exit_button.connect("pressed", _on_exit_button_pressed)
	if not SaveGame.save_changed.is_connected(_refresh_save_ui):
		SaveGame.save_changed.connect(_refresh_save_ui)
	if not SaveGame.save_error.is_connected(_on_save_error):
		SaveGame.save_error.connect(_on_save_error)
	_build_save_error_label()
	_refresh_save_ui()
	if not str(SaveGame.last_error).strip_edges().is_empty():
		_show_save_error(str(SaveGame.last_error))
	
	computer.texture = load(computer_list.pick_random())
	$Timer.start()


func _on_continue_button_pressed():
	if not SaveGame.can_continue():
		_refresh_save_ui()
		return
	var night_number := SaveGame.get_checkpoint_night()
	if not SaveGame.prepare_night(night_number):
		_show_save_error(str(SaveGame.last_error))
		return
	_open_night(night_number)
	
func _on_new_game_button_pressed():
	if not SaveGame.start_new_campaign():
		_show_save_error(str(SaveGame.last_error))
		return
	if not SaveGame.prepare_night(1):
		_show_save_error(str(SaveGame.last_error))
		return
	_open_night(1)

func _open_night(night_number: int) -> void:
	Global.night_number = night_number
	var error := get_tree().change_scene_to_file(NIGHT_SCENE)
	if error != OK:
		SaveGame.consume_night_request()
		_show_save_error("Не удалось открыть сцену ночи. Код ошибки: %d" % error)

func _refresh_save_ui() -> void:
	var available := SaveGame.can_continue()
	continue_button.disabled = not available
	if available:
		continue_button.tooltip_text = "Продолжить с ночи %d" % SaveGame.get_checkpoint_night()
	else:
		continue_button.tooltip_text = "Нет сохранённой кампании"

func _on_save_error(message: String) -> void:
	_show_save_error(message)

func _build_save_error_label() -> void:
	_save_error_label = Label.new()
	_save_error_label.name = "SaveErrorLabel"
	_save_error_label.anchor_left = 0.04
	_save_error_label.anchor_top = 0.86
	_save_error_label.anchor_right = 0.62
	_save_error_label.anchor_bottom = 0.97
	_save_error_label.offset_left = 12
	_save_error_label.offset_top = 0
	_save_error_label.offset_right = 0
	_save_error_label.offset_bottom = 0
	_save_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_error_label.add_theme_font_size_override("font_size", 22)
	_save_error_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.65))
	_save_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_error_label.visible = false
	add_child(_save_error_label)

func _show_save_error(message: String) -> void:
	if _save_error_label == null:
		return
	var detail := message.strip_edges()
	_save_error_label.text = "Ошибка сохранения: %s" % detail if not detail.is_empty() else "Не удалось выполнить операцию с сохранением."
	_save_error_label.visible = true

func _on_exit_button_pressed():
	get_tree().quit()


func _on_computer_mouse_entered() -> void:
	$Timer.stop()
	computer.texture = load("res://assets/Ремейк игры/Меню/Комп(нахер Берри))/комп достижения.png")

func _on_computer_mouse_exited() -> void:
	computer.texture = load(computer_list.pick_random())
	$Timer.start()

func timeout() -> void:
	var random_int = randi_range(1, 100)
	if random_int > 25:
		computer.texture = load(computer_list.pick_random())
	$Timer.start()
