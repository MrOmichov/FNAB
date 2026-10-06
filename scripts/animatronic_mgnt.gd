extends Node

enum Rooms { NONE, WORKSHOP, EXTRA_WORKSHOP, STAGE, ENTRANCE, MAIN_HALL, KITCHEN, HALLWAY, HALLWAY_PASSAGE, LEFT_VENT, RIGHT_VENT, OFFICE }
enum Animatronics { OLD_CREEPER, DOG, BERRY, BLACKY }
enum Old_creeper_states { STATE1, STATE2, STATE3, STATE4_FINAL, OUT }
signal location_changed(character: int, room: int)
signal old_creeper_state_changed(state: int)
signal posture_changed(character: int, on: bool)
@export var routes: AnimatronicRoutes = preload("res://resources/animatronic_routes.tres")
var old_creeper_path: Array:
	get: return routes.old_creeper_path
var dog_path: Array:
	get: return routes.dog_path
var berry_path: Array:
	get: return routes.berry_path
var blacky_path: Array:
	get: return routes.blacky_path
var old_creeper_path_index: int = 0
var dog_path_index: int = 0
var berry_path_index: int = 0
var blacky_path_index: int = 0
var old_creeper_pos: int = Rooms.NONE
var dog_pos: int = Rooms.NONE
var berry_pos: int = Rooms.NONE
var blacky_pos: int = Rooms.NONE
var old_creeper_state: int = Old_creeper_states.STATE1
var blacky_on: bool = false
var berry_on: bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	reset_for_night()

func reset_for_night() -> void:
	for character in Animatronics.values():
		reset_character(character)

func reset_character(character: int) -> void:
	var path: Array = routes.get_character_path(character)
	var room: int = int(path[0]) if not path.is_empty() and not path[0] is Array else Rooms.NONE
	_assign(character, 0 if not path.is_empty() else -1, room)
	if character == Animatronics.OLD_CREEPER:
		set_old_creeper_state(Old_creeper_states.STATE1)
	elif character == Animatronics.BERRY:
		set_berry_on(false)
	elif character == Animatronics.BLACKY:
		set_blacky_on(false)

func advance_character(character: int, rng: RandomNumberGenerator) -> bool:
	var path: Array = routes.get_character_path(character)
	var index: int = get_route_index(character) + 1
	if index < 0 or index >= path.size():
		return false
	var entry = path[index]
	var room: int
	if entry is Array:
		if entry.is_empty():
			return false
		room = int(entry[rng.randi_range(0, entry.size() - 1)])
	else:
		room = int(entry)
	if room < Rooms.WORKSHOP or room > Rooms.OFFICE:
		return false
	_assign(character, index, room)
	return true

func next(character: int, step: int = 1) -> void:
	for _i in range(maxi(step, 0)):
		if not advance_character(character, _rng):
			break

func _assign(character: int, index: int, room: int) -> void:
	match character:
		Animatronics.OLD_CREEPER:
			old_creeper_path_index = index
			old_creeper_pos = room
		Animatronics.DOG:
			dog_path_index = index
			dog_pos = room
		Animatronics.BERRY:
			berry_path_index = index
			berry_pos = room
		Animatronics.BLACKY:
			blacky_path_index = index
			blacky_pos = room
		_: return
	location_changed.emit(character, room)

func _set_position(character: int, room: int) -> void:
	var path: Array = routes.get_character_path(character)
	for index in range(path.size()):
		var entry = path[index]
		if (entry is Array and room in entry) or (not entry is Array and entry == room):
			_assign(character, index, room)
			return
	_assign(character, -1, Rooms.NONE)

func get_position(character: int) -> int:
	match character:
		0: return old_creeper_pos
		1: return dog_pos
		2: return berry_pos
		3: return blacky_pos
	return Rooms.NONE

func get_route_index(character: int) -> int:
	match character:
		0: return old_creeper_path_index
		1: return dog_path_index
		2: return berry_path_index
		3: return blacky_path_index
	return -1

func set_old_creeper_state(state: int) -> void:
	state = clampi(state, Old_creeper_states.STATE1, Old_creeper_states.OUT)
	if old_creeper_state != state:
		old_creeper_state = state
		old_creeper_state_changed.emit(state)

func set_old_creeper_pos(room: int) -> void: _set_position(0, room)
func set_dog_pos(room: int) -> void: _set_position(1, room)
func set_berry_pos(room: int) -> void: _set_position(2, room)
func set_blacky_pos(room: int) -> void: _set_position(3, room)
func set_blacky_on(on: bool) -> void:
	if blacky_on != on:
		blacky_on = on
		posture_changed.emit(3, on)
func set_berry_on(on: bool) -> void:
	if berry_on != on:
		berry_on = on
		posture_changed.emit(2, on)
func get_old_creeper_pos() -> int: return old_creeper_pos
func get_dog_pos() -> int: return dog_pos
func get_berry_pos() -> int: return berry_pos
func get_blacky_pos() -> int: return blacky_pos
func is_blacky_on() -> bool: return blacky_on
func is_berry_on() -> bool: return berry_on

# Manual camera inspection helper; never called by night initialization.
func test() -> void:
	set_berry_on(false)
	set_blacky_on(false)
	set_berry_pos(Rooms.MAIN_HALL)
	set_dog_pos(Rooms.HALLWAY)
	set_old_creeper_pos(Rooms.EXTRA_WORKSHOP)
	set_blacky_pos(Rooms.RIGHT_VENT)
