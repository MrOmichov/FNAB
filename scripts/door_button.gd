extends Sprite2D

@export var Night: Node

@onready var open_button: Sprite2D = $DoorOpenButton

func _ready() -> void:
	if Night != null and Night.has_signal("door_changed"):
		Night.door_changed.connect(_on_door_changed)
		_on_door_changed(bool(Night.get("is_door_closed")))

func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if Night == null or not Night.is_player_input_allowed():
		return
	Night.request_door_toggle()

func _on_door_changed(closed: bool) -> void:
	# The overlay artwork depicts the open/unpressed control state.
	open_button.visible = not closed

