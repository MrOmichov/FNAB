extends CanvasLayer

signal monitor_changed(open: bool)
signal remote_changed(open: bool)
signal camera_selected(index: int)

@export var Night: Node

# Visual interaction state only. Night remains authoritative for monitor access.
var isPadUp := false
var isRemoteControllerUp := false
var _closing_monitor := false
var _closing_remote := false

@onready var camera_pad: AnimatedSprite2D = $camera_pad
@onready var remote_controller: AnimatedSprite2D = $remote_controller
@onready var picture: Sprite2D = $picture

const CAMERA_METHODS: Array[StringName] = [
	&"set_workshop", &"set_extra_workshop", &"set_stage", &"set_main_hall",
	&"set_hallway", &"set_right_vent", &"set_left_vent",
]

func _ready() -> void:
	if Night == null:
		push_error("CameraSystem requires the Night node.")
		return
	Night.power_changed.connect(update_battery)
	Night.consumption_changed.connect(update_energy_consumption)
	Night.time_changed.connect(update_time)
	Night.phase_changed.connect(_on_phase_changed)
	Night.night_started.connect(_on_night_started)
	update_battery(float(Night.get("power_left")))
	update_energy_consumption(Night.get_total_energy_consumption())
	update_time(int(Night.get("hours")), int(Night.get("minutes")))
	_select_camera(3, false)

func _on_phase_changed(phase: int) -> void:
	if phase == 1:
		return
	_force_close()

func _on_night_started() -> void:
	# Refresh after Night has reset the autoloaded animatronic positions.
	_select_camera(3, false)

func _on_open_button_mouse_entered() -> void:
	if not _can_interact():
		return
	if isRemoteControllerUp:
		_close_remote()
	if isPadUp:
		_close_monitor()
	else:
		_open_monitor()

func _open_monitor() -> void:
	if not _can_interact():
		return
	isPadUp = true
	_closing_monitor = false
	Night.set_monitor_open(true)
	camera_pad.play("default")
	picture.get_node("camera_noise").play("default")
	camera_pad_visibility_change()
	monitor_changed.emit(true)

func _close_monitor() -> void:
	if not isPadUp:
		return
	isPadUp = false
	_closing_monitor = true
	_sync_input_guard()
	camera_pad.play_backwards("default")
	picture.get_node("camera_noise").stop()
	# Keep the screen input guard active until the tablet has visually closed.
	monitor_changed.emit(false)

func _on_camera_pad_animation_finished() -> void:
	if _closing_monitor:
		_closing_monitor = false
		_sync_input_guard()
	camera_pad_visibility_change()

func camera_pad_visibility_change() -> void:
	var shown := isPadUp or _closing_monitor
	picture.visible = shown
	camera_pad.get_node("camera_screen").visible = shown
	camera_pad.get_node("battery").visible = shown
	camera_pad.get_node("time").visible = shown
	camera_pad.get_node("camera_buttons").visible = shown
	camera_pad.get_node("energy_consumption").visible = shown
	for button in camera_pad.get_node("camera_buttons").get_children():
		if button is BaseButton:
			button.disabled = not isPadUp

func _on_remote_controller_button_mouse_entered() -> void:
	if not _can_interact():
		return
	if isPadUp:
		_close_monitor()
	if isRemoteControllerUp:
		_close_remote()
	else:
		isRemoteControllerUp = true
		_closing_remote = false
		_sync_input_guard()
		remote_controller.play_backwards("default")
		remote_controller.visible = true
		remote_changed.emit(true)

func _close_remote() -> void:
	if not isRemoteControllerUp:
		return
	isRemoteControllerUp = false
	_closing_remote = true
	_sync_input_guard()
	remote_controller.play("default")
	remote_changed.emit(false)

func _on_remote_controller_animation_finished() -> void:
	_closing_remote = false
	_sync_input_guard()
	remote_controller.visible = isRemoteControllerUp

func _can_interact() -> bool:
	return Night != null and Night.is_player_input_allowed()

func _force_close() -> void:
	if isPadUp:
		isPadUp = false
		monitor_changed.emit(false)
	_closing_remote = false
	if Night != null:
		Night.set_monitor_open(false)
	if camera_pad.is_playing():
		camera_pad.stop()
	if picture.get_node("camera_noise").is_playing():
		picture.get_node("camera_noise").stop()
	_closing_monitor = false
	camera_pad_visibility_change()
	if isRemoteControllerUp:
		isRemoteControllerUp = false
		remote_changed.emit(false)
	remote_controller.stop()
	remote_controller.visible = false

func _select_camera(index: int, emit_signal := true) -> void:
	if index < 0 or index >= CAMERA_METHODS.size() or (not isPadUp and emit_signal):
		return
	picture.call(CAMERA_METHODS[index])
	if emit_signal:
		camera_selected.emit(index + 1)

func select_camera_1() -> void: _select_camera(0)
func select_camera_2() -> void: _select_camera(1)
func select_camera_3() -> void: _select_camera(2)
func select_camera_4() -> void: _select_camera(3)
func select_camera_5() -> void: _select_camera(4)
func select_camera_6() -> void: _select_camera(5)
func select_camera_7() -> void: _select_camera(6)

func update_energy_consumption(energy_consumption: int) -> void:
	var icon := camera_pad.get_node("energy_consumption") as Sprite2D
	icon.visible = energy_consumption > 0
	if energy_consumption > 0:
		var frame := clampi(energy_consumption, 1, 3)
		icon.texture = load("res://assets/Ремейк игры/камера/планшет/расход/%d.png" % frame)

func update_battery(power_left: float) -> void:
	var capacity := maxf(float(Night.config.power_capacity), 1.0)
	var percentage := clampi(int(ceil(power_left / capacity * 10.0)) * 10, 0, 100)
	camera_pad.get_node("battery").texture = load("res://assets/Ремейк игры/камера/планшет/батарейка/%d.png" % percentage)

func update_time(hours: int, minutes: int) -> void:
	camera_pad.get_node("time").text = "%02d:%02d" % [hours, minutes]

func _sync_input_guard() -> void:
	if Night != null:
		Night.set_monitor_open(isPadUp or _closing_monitor or isRemoteControllerUp or _closing_remote)
