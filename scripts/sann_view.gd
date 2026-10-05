extends Sprite2D

## Art and clickable nose target for Sann. AI stage is authoritative; this
## node only changes sprites and forwards the mouse click to Night.
signal nose_pressed

@export var night: Node
@export var sann_ai: Node
@export var nose_center := Vector2(315.0, 657.0)
@export var nose_hitbox_size := Vector2(110.0, 78.0)

const STAGE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/Ремейк игры/аниматроники и смерти/Роботы/Санн/Санн 1 степень.png"),
	preload("res://assets/Ремейк игры/аниматроники и смерти/Роботы/Санн/Санн 2 степень.png"),
	preload("res://assets/Ремейк игры/аниматроники и смерти/Роботы/Санн/Санн 3 степень.png"),
	preload("res://assets/Ремейк игры/аниматроники и смерти/Роботы/Санн/Санн 4 степень.png"),
]
const WARNING_TEXTURES: Array[Texture2D] = [
	preload("res://assets/Ремейк игры/аниматроники и смерти/Роботы/Санн/Санн 5.1 степень.png"),
	preload("res://assets/Ремейк игры/аниматроники и смерти/Роботы/Санн/Санн 5.2 степень.png"),
]
const WARNING_NOSE_CENTERS := [Vector2(312.0, 675.0), Vector2(330.0, 640.0)]

var _stage := 1
var _warning_pose := 0
var _pose_timer: Timer
var _nose_area: Area2D
var _nose_shape: CollisionShape2D
var _warning := false

func _ready() -> void:
	centered = false
	texture = STAGE_TEXTURES[0]
	_pose_timer = Timer.new()
	_pose_timer.name = "WarningPoseTimer"
	_pose_timer.wait_time = 0.18
	_pose_timer.timeout.connect(_advance_warning_pose)
	add_child(_pose_timer)
	_nose_area = $NoseHitArea
	_nose_area.input_pickable = true
	_nose_area.input_event.connect(_on_nose_input_event)
	_nose_shape = $NoseHitArea/CollisionShape2D
	_nose_shape.position = nose_center
	(_nose_shape.shape as RectangleShape2D).size = nose_hitbox_size
	_nose_area.input_pickable = true
	set_stage(1)
	if sann_ai != null and sann_ai.has_signal("presentation_changed"):
		sann_ai.presentation_changed.connect(set_stage)
	if sann_ai != null and sann_ai.has_signal("defended"):
		sann_ai.defended.connect(_end_warning)
	if sann_ai != null and sann_ai.has_signal("attack_requested"):
		sann_ai.attack_requested.connect(_end_warning)
	if night != null and night.has_signal("phase_changed"):
		night.phase_changed.connect(_on_phase_changed)
	
func set_stage(stage: int) -> void:
	_stage = stage
	if stage >= 1 and stage <= 4:
		_warning = false
		_pose_timer.stop()
		texture = STAGE_TEXTURES[stage - 1]
		visible = true
	elif stage == 5:
		_begin_warning()
	elif stage == 6 or stage <= 0:
		_warning = false
		_pose_timer.stop()
		visible = false

func _begin_warning() -> void:
	_warning = true
	_warning_pose = 0
	texture = WARNING_TEXTURES[_warning_pose]
	_nose_shape.position = WARNING_NOSE_CENTERS[_warning_pose]
	visible = true
	_pose_timer.start()

func _end_warning() -> void:
	_warning = false
	_pose_timer.stop()
	if _stage >= 1 and _stage <= 4:
		texture = STAGE_TEXTURES[_stage - 1]

func _advance_warning_pose() -> void:
	if not _warning:
		return
	_warning_pose = 1 - _warning_pose
	texture = WARNING_TEXTURES[_warning_pose]
	_nose_shape.position = WARNING_NOSE_CENTERS[_warning_pose]

func _on_phase_changed(phase: int) -> void:
	if phase != 1:
		_warning = false
		_pose_timer.stop()
		_nose_area.input_pickable = false
		if phase in [3, 4]:
			visible = false
	else:
		_nose_area.input_pickable = true

func _on_nose_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if not _warning or night == null or not night.is_player_input_allowed():
		return
	if night.request_sann_nose_click():
		nose_pressed.emit()
