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

func _ready():
	continue_button.connect("pressed", _on_continue_button_pressed)
	new_game_button.connect("pressed", _on_new_game_button_pressed)
	exit_button.connect("pressed", _on_exit_button_pressed)
	
	computer.texture = load(computer_list.pick_random())
	$Timer.start()


func _on_continue_button_pressed():
	print("continue_button pressed") # TODO Запуск сохранения
	
func _on_new_game_button_pressed():
	Global.night_number = 1
	get_tree().change_scene_to_file("res://scenes/Night.tscn")

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
