extends Node

signal presentation_changed(stage: int)
signal warning_started()
signal warning_urgent()
signal defended()
signal attack_requested()

var active: bool = false
var warning_active: bool = false
var warning_remaining: float = 0.0
var stage: int = 1
var _config: NightConfig
var _grace_remaining: float = 0.0
var _check_elapsed: float = 0.0
var _urgent_emitted: bool = false
var _rng := RandomNumberGenerator.new()

func reset(config: NightConfig) -> void:
	_config = config
	_rng.randomize()
	active = config.sann_level > 0
	warning_active = false
	warning_remaining = 0.0
	_grace_remaining = maxf(config.sann_initial_grace_seconds, 0.0)
	_check_elapsed = 0.0
	_urgent_emitted = false
	_set_stage(1, true)

func advance(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	if warning_active:
		warning_remaining = maxf(0.0, warning_remaining - delta)
		if not _urgent_emitted and warning_remaining <= _config.sann_warning_urgent_seconds:
			_urgent_emitted = true
			warning_urgent.emit()
		if warning_remaining <= 0.000001:
			stop()
			attack_requested.emit()
		return
	var remaining: float = delta
	if _grace_remaining > 0.0:
		var grace_step: float = minf(remaining, _grace_remaining)
		_grace_remaining -= grace_step
		remaining -= grace_step
		if remaining <= 0.000001:
			return
	_check_elapsed += remaining
	var interval: float = maxf(_config.sann_check_interval_seconds, 0.001)
	_set_stage(1 + mini(3, int(_check_elapsed / interval * 4.0)))
	while _check_elapsed + 0.000001 >= interval:
		_check_elapsed = maxf(0.0, _check_elapsed - interval)
		if _rng.randf() < float(clampi(_config.sann_level, 0, 20)) / 20.0:
			warning_active = true
			warning_remaining = maxf(_config.sann_warning_seconds, 0.001)
			_urgent_emitted = false
			_set_stage(5)
			warning_started.emit()
			return
		_set_stage(1)

func defend() -> bool:
	if not active or not warning_active:
		return false
	warning_active = false
	warning_remaining = 0.0
	_grace_remaining = maxf(_config.sann_success_grace_seconds, 0.0)
	_check_elapsed = 0.0
	_urgent_emitted = false
	_set_stage(1)
	defended.emit()
	return true

func stop() -> void:
	active = false
	warning_active = false

func is_warning_active() -> bool:
	return warning_active

func _set_stage(value: int, force: bool = false) -> void:
	if stage != value or force:
		stage = value
		presentation_changed.emit(stage)
