extends CanvasLayer

signal monitor_changed(open: bool)
signal remote_changed(open: bool)
signal camera_selected(index: int)

@export var Night: Node

# Visual state only. Night owns gameplay availability and selected camera.
var isPadUp := false
var isRemoteControllerUp := false
var _closing_monitor := false
var _closing_remote := false
var _monitor_animation_complete := false
var _remote_animation_complete := false
var _shock_cooldown := 0.0

@onready var camera_pad: AnimatedSprite2D = $camera_pad
@onready var remote_controller: AnimatedSprite2D = $remote_controller
@onready var picture: Sprite2D = $picture
@onready var shock_button: TextureButton = $ShockButton
@onready var fan_left_button: TextureButton = $FanLeftButton
@onready var fan_right_button: TextureButton = $FanRightButton
@onready var fan_left_lit: Polygon2D = $FanLeftLit
@onready var fan_right_lit: Polygon2D = $FanRightLit

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
	Night.fan_changed.connect(_on_fan_changed)
	Night.shock_cooldown_changed.connect(_on_shock_cooldown_changed)
	Night.power_changed.connect(_refresh_shock_button)
	AnimatronicMgnt.location_changed.connect(_on_location_changed)
	AnimatronicMgnt.old_creeper_state_changed.connect(_on_old_creeper_state_changed)
	AnimatronicMgnt.posture_changed.connect(_on_posture_changed)
	update_battery(float(Night.get("power_left")))
	update_energy_consumption(Night.get_total_energy_consumption())
	update_time(int(Night.get("hours")), int(Night.get("minutes")))
	_select_camera(3, false)
	_on_fan_changed(0, Night.is_left_fan_enabled)
	_on_fan_changed(1, Night.is_right_fan_enabled)
	_on_shock_cooldown_changed(float(Night.shock_cooldown_remaining))
	_refresh_shock_button()
	_sync_input_guard()

func _on_phase_changed(phase: int) -> void:
	if phase == Night.Phase.RUNNING:
		_refresh_shock_button()
		return
	_force_close()

func _on_night_started() -> void:
	# Start on camera 4 after the manager has reset all animatronic positions.
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
	_monitor_animation_complete = false
	_closing_monitor = false
	Night.set_monitor_open(true)
	Night.set_surveillance_open(false)
	camera_pad.play("default")
	picture.get_node("camera_noise").play("default")
	camera_pad_visibility_change()
	_refresh_shock_button()
	monitor_changed.emit(true)

func _close_monitor() -> void:
	if not isPadUp:
		return
	isPadUp = false
	_monitor_animation_complete = false
	_closing_monitor = true
	_sync_input_guard()
	camera_pad.play_backwards("default")
	picture.get_node("camera_noise").stop()
	_refresh_shock_button()
	monitor_changed.emit(false)

func _on_camera_pad_animation_finished() -> void:
	if _closing_monitor:
		_closing_monitor = false
	elif isPadUp:
		_monitor_animation_complete = true
	_sync_input_guard()
	_refresh_shock_button()
	camera_pad_visibility_change()

func camera_pad_visibility_change() -> void:
	var shown := isPadUp or _closing_monitor
	picture.visible = shown
	camera_pad.get_node("camera_screen").visible = shown
	camera_pad.get_node("battery").visible = shown
	camera_pad.get_node("time").visible = shown
	camera_pad.get_node("camera_buttons").visible = shown
	camera_pad.get_node("energy_consumption").visible = shown
	camera_pad.get_node("consumption_count").visible = shown and Night.get_total_energy_consumption() >= 4
	for button in camera_pad.get_node("camera_buttons").get_children():
		if button is BaseButton:
			button.disabled = not (isPadUp and _monitor_animation_complete)

func _on_remote_controller_button_mouse_entered() -> void:
	if not _can_interact():
		return
	if isPadUp:
		_close_monitor()
	if isRemoteControllerUp:
		_close_remote()
	else:
		isRemoteControllerUp = true
		_remote_animation_complete = false
		_closing_remote = false
		_sync_input_guard()
		remote_controller.play_backwards("default")
		remote_controller.visible = true
		_refresh_fan_controls()
		remote_changed.emit(true)

func _close_remote() -> void:
	if not isRemoteControllerUp:
		return
	isRemoteControllerUp = false
	_remote_animation_complete = false
	_closing_remote = true
	_sync_input_guard()
	remote_controller.play("default")
	_refresh_fan_controls()
	remote_changed.emit(false)

func _on_remote_controller_animation_finished() -> void:
	if _closing_remote:
		_closing_remote = false
	elif isRemoteControllerUp:
		_remote_animation_complete = true
	_sync_input_guard()
	_refresh_fan_controls()
	remote_controller.visible = isRemoteControllerUp

func _can_interact() -> bool:
	return Night != null and Night.is_player_input_allowed()

func _force_close() -> void:
	if isPadUp:
		isPadUp = false
		monitor_changed.emit(false)
	if isRemoteControllerUp:
		isRemoteControllerUp = false
		remote_changed.emit(false)
	_monitor_animation_complete = false
	_remote_animation_complete = false
	_closing_remote = false
	if Night != null:
		Night.set_monitor_open(false)
		Night.set_surveillance_open(false)
	if camera_pad.is_playing():
		camera_pad.stop()
	if picture.get_node("camera_noise").is_playing():
		picture.get_node("camera_noise").stop()
	_closing_monitor = false
	_camera_pad_hide()
	remote_controller.stop()
	remote_controller.visible = false
	_refresh_fan_controls()
	_refresh_shock_button()

func _camera_pad_hide() -> void:
	camera_pad_visibility_change()

func _select_camera(index: int, emit_signal := true) -> void:
	if index < 0 or index >= CAMERA_METHODS.size() or (emit_signal and (not isPadUp or not Night.surveillance_open)):
		return
	if emit_signal and not Night.select_surveillance_camera(index + 1):
		return
	if emit_signal:
		picture.clear_background_for_camera(index + 1)
	Night.set_surveillance_open(false)
	picture.call(CAMERA_METHODS[index])
	_sync_input_guard()
	_refresh_shock_button()
	if emit_signal:
		camera_selected.emit(index + 1)
	if not emit_signal:
		Night.select_surveillance_camera(index + 1)

func select_camera_1() -> void: _select_camera(0)
func select_camera_2() -> void: _select_camera(1)
func select_camera_3() -> void: _select_camera(2)
func select_camera_4() -> void: _select_camera(3)
func select_camera_5() -> void: _select_camera(4)
func select_camera_6() -> void: _select_camera(5)
func select_camera_7() -> void: _select_camera(6)

func _on_location_changed(_character: int, _room: int) -> void:
	_refresh_selected_camera()

func _on_old_creeper_state_changed(_state: int) -> void:
	_refresh_selected_camera()
	_refresh_shock_button()

func _on_posture_changed(_character: int, _on: bool) -> void:
	_refresh_selected_camera()

func _refresh_selected_camera() -> void:
	var index := int(Night.current_camera_index) - 1
	if index >= 0 and index < CAMERA_METHODS.size():
		picture.call(CAMERA_METHODS[index])

func _on_fan_changed(side: int, enabled: bool) -> void:
	if side == 0:
		fan_left_lit.visible = enabled
	elif side == 1:
		fan_right_lit.visible = enabled
	_refresh_fan_controls()

func _refresh_fan_controls() -> void:
	var enabled := _can_interact() and isRemoteControllerUp and _remote_animation_complete
	fan_left_button.visible = isRemoteControllerUp or _closing_remote
	fan_right_button.visible = isRemoteControllerUp or _closing_remote
	fan_left_button.disabled = not enabled
	fan_right_button.disabled = not enabled
	fan_left_lit.visible = enabled and Night.is_left_fan_enabled
	fan_right_lit.visible = enabled and Night.is_right_fan_enabled

func _on_fan_left_pressed() -> void:
	if _can_interact() and isRemoteControllerUp and _remote_animation_complete:
		Night.request_fan_toggle(0)

func _on_fan_right_pressed() -> void:
	if _can_interact() and isRemoteControllerUp and _remote_animation_complete:
		Night.request_fan_toggle(1)

func _on_shock_pressed() -> void:
	if _shock_available():
		Night.request_shock()
	_refresh_shock_button()

func _on_shock_cooldown_changed(seconds: float) -> void:
	_shock_cooldown = seconds
	_refresh_shock_button()

func _shock_available() -> bool:
	return _can_interact() and isPadUp and _monitor_animation_complete \
		and bool(Night.surveillance_open) \
		and not isRemoteControllerUp and not _closing_remote \
		and int(Night.current_camera_index) == 2 \
		and int(Night.config.old_creeper_level) > 0 \
		and _shock_cooldown <= 0.0 \
		and float(Night.power_left) >= float(Night.config.shock_cost)

func _refresh_shock_button(_unused: Variant = null) -> void:
	if shock_button == null:
		return
	var camera_two_selected := int(Night.current_camera_index) == 2
	shock_button.visible = isPadUp and camera_two_selected
	var cooldown_label := get_node("ShockCooldown") as Label
	cooldown_label.visible = shock_button.visible and _shock_cooldown > 0.0
	cooldown_label.text = str(ceili(_shock_cooldown))
	var ready := _shock_available()
	shock_button.disabled = not ready
	shock_button.texture_normal = load("res://assets/Ремейк игры/камера/кнопки/кнопка шокер ОК %s.png" % ("вкл" if ready else "выкл"))

func update_energy_consumption(energy_consumption: int) -> void:
	var icon := camera_pad.get_node("energy_consumption") as Sprite2D
	icon.visible = energy_consumption > 0
	if energy_consumption > 0:
		var frame := clampi(energy_consumption, 1, 3)
		icon.texture = load("res://assets/Ремейк игры/камера/планшет/расход/%d.png" % frame)
	var count := camera_pad.get_node("consumption_count") as Label
	count.visible = (isPadUp or _closing_monitor) and energy_consumption >= 4
	count.text = str(energy_consumption)

func update_battery(power_left: float) -> void:
	var capacity := maxf(float(Night.config.power_capacity), 1.0)
	var percentage := clampi(int(ceil(power_left / capacity * 10.0)) * 10, 0, 100)
	camera_pad.get_node("battery").texture = load("res://assets/Ремейк игры/камера/планшет/батарейка/%d.png" % percentage)
	_refresh_shock_button()

func update_time(hours: int, minutes: int) -> void:
	camera_pad.get_node("time").text = "%02d:%02d" % [hours, minutes]

func _sync_input_guard() -> void:
	if Night == null:
		return
	var guarded := isPadUp or _closing_monitor or isRemoteControllerUp or _closing_remote
	Night.set_monitor_open(guarded)
	Night.set_surveillance_open(isPadUp and _monitor_animation_complete and not _closing_monitor and not isRemoteControllerUp and not _closing_remote)
