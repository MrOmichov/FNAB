extends AnimatedSprite2D

@export var Night: Node
var _last_closed := false

func _ready() -> void:
	if Night == null:
		push_error("Door requires the Night node.")
		return
	if Night.has_signal("door_changed"):
		Night.door_changed.connect(_on_door_changed)
	_last_closed = bool(Night.get("is_door_closed"))
	frame = 0 if not _last_closed else sprite_frames.get_frame_count("default") - 1
	stop()

func _on_door_changed(closed: bool) -> void:
	if closed == _last_closed:
		return
	_last_closed = closed
	if closed:
		play("default")
	else:
		play_backwards("default")
