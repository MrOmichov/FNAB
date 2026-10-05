extends Node

@onready var timer: Timer = $DogTimer

func _ready() -> void:
	# Dog has no implemented AI and is inactive in the first night.
	timer.stop()
	
