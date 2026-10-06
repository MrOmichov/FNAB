extends Node

## Presentation-only audio: observes accepted gameplay and monitor events.
@export var night: Node
@export var sann_ai: Node
@export var camera_system: Node
@export var route_ai: Node

@export_group("Players")
@export var ambience_player: AudioStreamPlayer
@export var control_player: AudioStreamPlayer
@export var door_player: AudioStreamPlayer
@export var warning_player: AudioStreamPlayer
@export var nose_player: AudioStreamPlayer
@export var outcome_player: AudioStreamPlayer
@export var left_fan_player: AudioStreamPlayer
@export var right_fan_player: AudioStreamPlayer
@export var dog_player: AudioStreamPlayer
@export var berry_player: AudioStreamPlayer
@export var blacky_player: AudioStreamPlayer

const LEFT_FAN_STREAM = preload("res://assets/Ремейк игры/звуки/офис/вертушки/левый вентилятор.wav")
const RIGHT_FAN_STREAM = preload("res://assets/Ремейк игры/звуки/офис/вертушки/правый вентилятор.wav")
const SHOCK_STREAM = preload("res://assets/Ремейк игры/звуки/офис/планшет/удар тока.wav")
const DOG_ATTACK_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/пес/нападение(при окончание смерть).wav")
const BERRY_ARRIVAL_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/берри/приходит.wav")
const BERRY_DEPARTURE_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/берри/уход.wav")
const BLACKY_LEFT_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/блеки/приход слева.wav")
const BLACKY_RIGHT_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/блеки/приход справа.wav")
const BLACKY_LEAVE_LEFT_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/блеки/уход влево.wav")
const BLACKY_LEAVE_RIGHT_STREAM = preload("res://assets/Ремейк игры/звуки/роботы у офиса/блеки/уход вправо.wav")
const ROUTE_JUMPSCARES = {
	"dog": preload("res://assets/Ремейк игры/звуки/скримеры/скример пса.wav"),
	"berry": preload("res://assets/Ремейк игры/звуки/скримеры/скример берри.wav"),
	"blacky": preload("res://assets/Ремейк игры/звуки/скримеры/скример блеки.mp3"),
	"old_creeper": preload("res://assets/Ремейк игры/звуки/скримеры/скример ок.wav"),
}

@export_group("Streams")
@export var ambience_stream: AudioStream
@export var start_stream: AudioStream
@export var door_button_stream: AudioStream
@export var door_motion_stream: AudioStream
@export var tablet_up_stream: AudioStream
@export var tablet_down_stream: AudioStream
@export var camera_switch_stream: AudioStream
@export var sann_warning_stream: AudioStream
@export var sann_urgent_stream: AudioStream
@export var sann_nose_stream: AudioStream
@export var sann_jumpscare_stream: AudioStream
@export var power_out_stream: AudioStream
@export var won_stream: AudioStream
@export var lost_stream: AudioStream

@export_group("Mix")
@export var ambience_volume_db: float = -24.0
@export var control_volume_db: float = -8.0
@export var warning_volume_db: float = -8.0
@export var outcome_volume_db: float = -12.0

var _looping_ambience: AudioStream
var _defeat_pending := false
var _fan_loops: Array[AudioStream] = []


func _ready() -> void:
	_looping_ambience = _make_loop(ambience_stream)
	ambience_player.volume_db = ambience_volume_db
	control_player.volume_db = control_volume_db
	door_player.volume_db = control_volume_db
	warning_player.volume_db = warning_volume_db
	nose_player.volume_db = control_volume_db
	outcome_player.volume_db = outcome_volume_db
	_fan_loops = [_make_loop(LEFT_FAN_STREAM), _make_loop(RIGHT_FAN_STREAM)]
	for player in [left_fan_player, right_fan_player]:
		if player != null:
			player.volume_db = -18.0
	for player in [dog_player, berry_player, blacky_player]:
		if player != null:
			player.volume_db = warning_volume_db
	night.night_started.connect(_on_night_started)
	night.phase_changed.connect(_on_phase_changed)
	night.door_changed.connect(_on_door_changed)
	night.sann_nose_clicked.connect(_on_nose_clicked)
	night.outcome_reached.connect(_on_outcome_reached)
	night.fan_changed.connect(_on_fan_changed)
	night.shock_used.connect(_on_shock_used)
	if route_ai != null:
		route_ai.warning_started.connect(_on_route_warning_started)
		route_ai.defended.connect(_on_route_defended)
	sann_ai.warning_started.connect(_on_warning_started)
	sann_ai.warning_urgent.connect(_on_warning_urgent)
	camera_system.monitor_changed.connect(_on_monitor_changed)
	camera_system.remote_changed.connect(_on_remote_changed)
	camera_system.camera_selected.connect(_on_camera_selected)
	outcome_player.finished.connect(_on_outcome_sound_finished)


func _make_loop(source: AudioStream) -> AudioStream:
	if source == null:
		return null
	# Do not mutate the imported Resource shared with another scene/player.
	var copy := source.duplicate() as AudioStream
	if copy is AudioStreamWAV:
		copy.loop_begin = 0
		copy.loop_end = int(round(copy.get_length() * copy.mix_rate))
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif copy is AudioStreamMP3:
		copy.loop = true
	return copy


func _play(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream == null or player == null:
		return
	player.stream = stream
	player.play()


func _is_running() -> bool:
	return night.phase == night.Phase.RUNNING


func _on_night_started() -> void:
	_play(control_player, start_stream)
	_play(ambience_player, _looping_ambience)


func _on_phase_changed(phase: int) -> void:
	if phase == night.Phase.POWER_OUT:
		_stop_active_sounds()
		_play(outcome_player, power_out_stream)
	elif phase == night.Phase.WON or phase == night.Phase.LOST:
		_stop_active_sounds()


func _on_door_changed(_closed: bool) -> void:
	if not _is_running():
		return
	_play(control_player, door_button_stream)
	_play(door_player, door_motion_stream)


func _on_monitor_changed(open: bool) -> void:
	if _is_running():
		_play(control_player, tablet_up_stream if open else tablet_down_stream)


func _on_remote_changed(open: bool) -> void:
	if _is_running():
		_play(control_player, tablet_up_stream if open else tablet_down_stream)


func _on_camera_selected(_index: int) -> void:
	if _is_running():
		_play(control_player, camera_switch_stream)


func _on_warning_started() -> void:
	if _is_running():
		_play(warning_player, sann_warning_stream)


func _on_warning_urgent() -> void:
	if _is_running():
		_play(warning_player, sann_urgent_stream)


func _on_nose_clicked() -> void:
	warning_player.stop()
	_play(nose_player, sann_nose_stream)


func _on_fan_changed(side: int, enabled: bool) -> void:
	if side not in [0, 1]:
		return
	var player := left_fan_player if side == 0 else right_fan_player
	if player == null:
		return
	if enabled and _is_running():
		_play(player, _fan_loops[side])
	else:
		player.stop()


func _on_shock_used() -> void:
	if _is_running():
		_play(control_player, SHOCK_STREAM)


func _on_route_warning_started(character: int, room: int) -> void:
	if not _is_running():
		return
	match character:
		AnimatronicMgnt.Animatronics.DOG:
			_play(dog_player, DOG_ATTACK_STREAM)
		AnimatronicMgnt.Animatronics.BERRY:
			_play(berry_player, BERRY_ARRIVAL_STREAM)
		AnimatronicMgnt.Animatronics.BLACKY:
			_play(blacky_player, BLACKY_LEFT_STREAM if room == AnimatronicMgnt.Rooms.LEFT_VENT else BLACKY_RIGHT_STREAM)


func _on_route_defended(character: int, room: int) -> void:
	if not _is_running():
		return
	match character:
		AnimatronicMgnt.Animatronics.DOG:
			if dog_player != null:
				dog_player.stop()
		AnimatronicMgnt.Animatronics.BERRY:
			_play(berry_player, BERRY_DEPARTURE_STREAM)
		AnimatronicMgnt.Animatronics.BLACKY:
			_play(blacky_player, BLACKY_LEAVE_LEFT_STREAM if room == AnimatronicMgnt.Rooms.LEFT_VENT else BLACKY_LEAVE_RIGHT_STREAM)


func _on_outcome_reached(won: bool, reason: String) -> void:
	_defeat_pending = false
	outcome_player.stop()
	if won:
		_play(outcome_player, won_stream)
	elif reason == "sann":
		_defeat_pending = true
		_play(outcome_player, sann_jumpscare_stream)
	elif ROUTE_JUMPSCARES.has(reason):
		_defeat_pending = true
		_play(outcome_player, ROUTE_JUMPSCARES[reason])
	else:
		_play(outcome_player, lost_stream)


func _on_outcome_sound_finished() -> void:
	if _defeat_pending and night.phase == night.Phase.LOST:
		_defeat_pending = false
		_play(outcome_player, lost_stream)


func _stop_active_sounds() -> void:
	ambience_player.stop()
	control_player.stop()
	door_player.stop()
	warning_player.stop()
	nose_player.stop()
	for player in [left_fan_player, right_fan_player, dog_player, berry_player, blacky_player]:
		if player != null:
			player.stop()


func _exit_tree() -> void:
	_defeat_pending = false
	_stop_active_sounds()
	outcome_player.stop()
