extends CanvasLayer

# TODO Выбор ночи
@onready var continue_button = $Buttons/ContinueButton
@onready var new_game_button = $Buttons/NewGameButton
@onready var exit_button = $Buttons/ExitButton

func _ready():
	continue_button.connect("pressed", _on_continue_button_pressed)
	new_game_button.connect("pressed", _on_new_game_button_pressed)
	exit_button.connect("pressed", _on_exit_button_pressed)
	


func _on_continue_button_pressed():
	print("continue_button pressed") # TODO Запуск сохранения
	
func _on_new_game_button_pressed():
	get_tree().change_scene_to_file("res://scenes/Night.tscn")

func _on_exit_button_pressed():
	get_tree().quit()
