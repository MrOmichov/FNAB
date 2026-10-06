extends Node

signal warning_started(character: int, room: int)
signal warning_ended(character: int)
signal attack_requested(character: int)
signal defended(character: int, room: int)
var _config: NightConfig
var _night: Node
var _states: Array[Dictionary] = []
var _running: bool = false
var _rng := RandomNumberGenerator.new()

func reset(config: NightConfig, night: Node) -> void:
	stop()
	_config = config
	_night = night
	_rng.randomize()
	_states.clear()
	var levels: Array = [config.old_creeper_level, config.dog_level, config.berry_level, config.blacky_level]
	for level in levels:
		_states.append({"level": clampi(int(level), 0, 20), "grace": maxf(config.route_initial_grace_seconds, 0.0), "elapsed": 0.0, "moves": 0, "warning": false, "remaining": 0.0, "hold": 0.0, "room": AnimatronicMgnt.Rooms.NONE})
	_running = true

func advance(delta: float) -> void:
	if not _running or delta <= 0.0:
		return
	for character in range(_states.size()):
		if not _running or not _night.is_player_input_allowed():
			return
		var state: Dictionary = _states[character]
		if state.level <= 0:
			continue
		if state.warning:
			_advance_warning(character, state, delta)
			continue
		var available: float = delta
		if state.grace > 0.0:
			var consumed: float = minf(available, state.grace)
			state.grace -= consumed
			available -= consumed
		state.elapsed += available
		var interval: float = maxf(_config.route_check_interval_seconds, 0.001)
		if character == AnimatronicMgnt.Animatronics.DOG:
			interval = maxf(maxf(_config.dog_min_check_interval_seconds, 0.001), interval - state.moves * maxf(_config.dog_move_acceleration_seconds, 0.0))
		while state.elapsed + 0.000001 >= interval and _running and not state.warning:
			state.elapsed = maxf(0.0, state.elapsed - interval)
			if _rng.randf() < float(state.level) / 20.0:
				_move(character, state)
			if not _night.is_player_input_allowed():
				return

func _move(character: int, state: Dictionary) -> void:
	if AnimatronicMgnt.get_position(character) == AnimatronicMgnt.Rooms.STAGE:
		if character == AnimatronicMgnt.Animatronics.BERRY and not AnimatronicMgnt.is_berry_on():
			AnimatronicMgnt.set_berry_on(true)
			return
		if character == AnimatronicMgnt.Animatronics.BLACKY and not AnimatronicMgnt.is_blacky_on():
			AnimatronicMgnt.set_blacky_on(true)
			return
	if character == AnimatronicMgnt.Animatronics.OLD_CREEPER and AnimatronicMgnt.get_position(character) == AnimatronicMgnt.Rooms.EXTRA_WORKSHOP:
		if AnimatronicMgnt.old_creeper_state < AnimatronicMgnt.Old_creeper_states.STATE4_FINAL:
			AnimatronicMgnt.set_old_creeper_state(AnimatronicMgnt.old_creeper_state + 1)
			return
		AnimatronicMgnt.set_old_creeper_state(AnimatronicMgnt.Old_creeper_states.OUT)
	if not _running or not _night.is_player_input_allowed():
		return
	if not AnimatronicMgnt.advance_character(character, _rng):
		return
	if not _running or not _night.is_player_input_allowed():
		return
	state.moves += 1
	var room: int = AnimatronicMgnt.get_position(character)
	# A departing stage resident also wakes the other active resident.
	if character == AnimatronicMgnt.Animatronics.BERRY and _states[3].level > 0 and AnimatronicMgnt.get_blacky_pos() == AnimatronicMgnt.Rooms.STAGE:
		AnimatronicMgnt.set_blacky_on(true)
	elif character == AnimatronicMgnt.Animatronics.BLACKY and _states[2].level > 0 and AnimatronicMgnt.get_berry_pos() == AnimatronicMgnt.Rooms.STAGE:
		AnimatronicMgnt.set_berry_on(true)
	if not _running or not _night.is_player_input_allowed():
		return
	var precursor: bool = room == AnimatronicMgnt.Rooms.HALLWAY if character != AnimatronicMgnt.Animatronics.BLACKY else room in [AnimatronicMgnt.Rooms.LEFT_VENT, AnimatronicMgnt.Rooms.RIGHT_VENT]
	if precursor and _running:
		state.warning = true
		state.remaining = _warning_duration(character)
		state.hold = 0.0
		state.room = room
		warning_started.emit(character, room)

func _advance_warning(character: int, state: Dictionary, delta: float) -> void:
	var step: float = minf(delta, maxf(state.remaining, 0.0))
	if _is_protected(character, state.room):
		state.hold += step
	else:
		state.hold = 0.0
	# Completed defense wins a tie with the attack deadline.
	if state.hold + 0.000001 >= maxf(_config.route_defense_hold_seconds, 0.0) and _is_protected(character, state.room):
		_defend(character, state)
		return
	state.remaining = maxf(0.0, state.remaining - delta)
	if state.remaining <= 0.000001:
		state.warning = false
		warning_ended.emit(character)
		if not _running or not _night.is_player_input_allowed():
			return
		AnimatronicMgnt.advance_character(character, _rng)
		if _running and _night.is_player_input_allowed():
			attack_requested.emit(character)

func _is_protected(character: int, room: int) -> bool:
	if character in [AnimatronicMgnt.Animatronics.DOG, AnimatronicMgnt.Animatronics.BERRY]:
		return _night.is_door_closed
	if character == AnimatronicMgnt.Animatronics.BLACKY:
		return _night.is_left_fan_enabled if room == AnimatronicMgnt.Rooms.LEFT_VENT else _night.is_right_fan_enabled
	return false

func _defend(character: int, state: Dictionary) -> void:
	var room: int = state.room
	var was_warning: bool = state.warning
	state.warning = false
	state.remaining = 0.0
	state.hold = 0.0
	state.room = AnimatronicMgnt.Rooms.NONE
	state.grace = maxf(_config.route_success_grace_seconds, 0.0)
	state.elapsed = 0.0
	state.moves = 0
	AnimatronicMgnt.reset_character(character)
	if was_warning:
		warning_ended.emit(character)
	if _running:
		defended.emit(character, room)

func shock_old_creeper() -> bool:
	if not _running or _states.is_empty() or _states[0].level <= 0 or not _night.is_player_input_allowed():
		return false
	_defend(AnimatronicMgnt.Animatronics.OLD_CREEPER, _states[0])
	return true

func get_warning_room(character: int) -> int:
	if character < 0 or character >= _states.size() or not _states[character].warning:
		return AnimatronicMgnt.Rooms.NONE
	return int(_states[character].room)

func get_warning_remaining(character: int) -> float:
	if character < 0 or character >= _states.size() or not _states[character].warning:
		return 0.0
	return float(_states[character].remaining)

func _warning_duration(character: int) -> float:
	var durations: Array = [_config.old_creeper_warning_seconds, _config.dog_warning_seconds, _config.berry_warning_seconds, _config.blacky_warning_seconds]
	return maxf(float(durations[character]), 0.001)

func stop() -> void:
	_running = false
	for character in range(_states.size()):
		var state: Dictionary = _states[character]
		var was_warning: bool = state.warning
		state.warning = false
		state.remaining = 0.0
		state.hold = 0.0
		state.room = AnimatronicMgnt.Rooms.NONE
		if was_warning:
			warning_ended.emit(character)
