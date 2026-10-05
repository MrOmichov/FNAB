extends Node2D

enum Phase { INTRO, RUNNING, POWER_OUT, WON, LOST }
signal phase_changed(phase: int)
signal time_changed(hours: int, minutes: int)
signal power_changed(power: float)
signal consumption_changed(consumption: int)
signal door_changed(closed: bool)
signal night_started()
signal sann_nose_clicked()
signal outcome_reached(won: bool, reason: String)

const MAX_POWER = 1000
const BASE_ENERGY_CONSUMPTION = 1
@export var config: NightConfig
@export var sann_ai: Node
@export var time_speed_modifier: float = 1.0
var phase: Phase = Phase.INTRO
var hours: int = 0
var minutes: int = 0
var power_left: float = MAX_POWER
var is_door_closed: bool = false
var is_left_fan_enabled: bool = false
var is_right_fan_enabled: bool = false
var monitor_open: bool = false
var _clock_elapsed: float = 0.0
var _power_elapsed: float = 0.0
var _power_out_elapsed: float = 0.0

func _ready() -> void:
	if config == null:
		config = preload("res://resources/night_1.tres")
	var legacy_timer := get_node_or_null("Timer") as Timer
	if legacy_timer != null:
		legacy_timer.stop()
	Global.night_number = config.night_number
	AnimatronicMgnt.reset_for_night()
	power_left = config.power_capacity
	if sann_ai != null:
		sann_ai.reset(config)
		sann_ai.attack_requested.connect(_on_sann_attack_requested)
	phase_changed.emit(phase)
	time_changed.emit(hours, minutes)
	_emit_power()
	_emit_consumption()
	door_changed.emit(false)

func _process(delta: float) -> void:
	advance(delta)

func begin_night() -> bool:
	if phase != Phase.INTRO:
		return false
	phase = Phase.RUNNING
	phase_changed.emit(phase)
	night_started.emit()
	return true

# Clock is resolved before attacks or exhaustion on every simulation step.
func advance(delta: float) -> void:
	var remaining: float = maxf(delta, 0.0)
	while remaining > 0.000001 and phase in [Phase.RUNNING, Phase.POWER_OUT]:
		var step: float = minf(remaining, 0.05)
		remaining -= step
		_clock_elapsed += step * maxf(time_speed_modifier, 0.0)
		var minute_seconds: float = maxf(config.seconds_per_minute, 0.001)
		while _clock_elapsed + 0.000001 >= minute_seconds:
			_clock_elapsed = maxf(0.0, _clock_elapsed - minute_seconds)
			minutes += 1
			if minutes >= 60:
				minutes = 0
				hours += 1
			time_changed.emit(hours, minutes)
			if hours >= config.end_hour:
				_finish(true, "time")
				return
		if phase == Phase.POWER_OUT:
			_power_out_elapsed += step
			if _power_out_elapsed + 0.000001 >= config.power_out_grace_seconds:
				_finish(false, "power")
			continue
		_power_elapsed += step
		while _power_elapsed + 0.000001 >= 1.0:
			_power_elapsed = maxf(0.0, _power_elapsed - 1.0)
			power_left = maxf(0.0, power_left - get_total_energy_consumption())
			_emit_power()
			if power_left <= 0.0:
				_enter_power_out()
				break
		if phase == Phase.RUNNING and sann_ai != null:
			sann_ai.advance(step)

func is_player_input_allowed() -> bool:
	return phase == Phase.RUNNING

func request_door_toggle() -> bool:
	if not is_player_input_allowed():
		return false
	is_door_closed = not is_door_closed
	door_changed.emit(is_door_closed)
	_emit_consumption()
	return true

func set_monitor_open(open: bool) -> void:
	monitor_open = open and is_player_input_allowed()

func request_sann_nose_click() -> bool:
	if not is_player_input_allowed() or monitor_open or sann_ai == null:
		return false
	var success: bool = sann_ai.defend()
	if success:
		sann_nose_clicked.emit()
	return success

func get_total_energy_consumption() -> int:
	if phase in [Phase.POWER_OUT, Phase.WON, Phase.LOST]:
		return 0
	var result: int = config.base_consumption if config != null else BASE_ENERGY_CONSUMPTION
	if is_door_closed:
		result += config.door_extra_consumption
	if is_left_fan_enabled:
		result += config.fan_extra_consumption
	if is_right_fan_enabled:
		result += config.fan_extra_consumption
	return result

func _enter_power_out() -> void:
	phase = Phase.POWER_OUT
	monitor_open = false
	is_door_closed = false
	is_left_fan_enabled = false
	is_right_fan_enabled = false
	if sann_ai != null:
		sann_ai.stop()
	door_changed.emit(false)
	_emit_consumption()
	phase_changed.emit(phase)

func _finish(won: bool, reason: String) -> void:
	if phase in [Phase.WON, Phase.LOST]:
		return
	phase = Phase.WON if won else Phase.LOST
	monitor_open = false
	if sann_ai != null:
		sann_ai.stop()
	_emit_consumption()
	phase_changed.emit(phase)
	outcome_reached.emit(won, reason)

func _on_sann_attack_requested() -> void:
	if phase == Phase.RUNNING:
		_finish(false, "sann")

func _emit_power() -> void:
	power_changed.emit(power_left)
	Global.power_left_changed.emit(power_left)

func _emit_consumption() -> void:
	var consumption := get_total_energy_consumption()
	consumption_changed.emit(consumption)
	Global.energy_consumption_changed.emit(consumption)

# Existing scene connection retained; gameplay does not advance from this timer.
func _on_timer_timeout() -> void:
	pass
