extends Node

enum Rooms {
	NONE = 0,
	WORKSHOP = 1,
	EXTRA_WORKSHOP = 2,
	STAGE = 3,
	ENTRANCE = 4,
	MAIN_HALL = 5,
	KITCHEN = 6,
	HALLWAY = 7,
	HALLWAY_PASSAGE = 8,
	LEFT_VENT = 9,
	RIGHT_VENT = 10,
	OFFICE = 11
}

enum Animatronics {
	OLD_CREEPER,
	DOG,
	BERRY,
	BLACKY
}

enum Old_creeper_states {
	STATE1,
	STATE2,
	STATE3,
	STATE4_FINAL,
	OUT
}

var old_creeper_path = [
	Rooms.EXTRA_WORKSHOP,
	Rooms.WORKSHOP,
	Rooms.MAIN_HALL, 
	Rooms.HALLWAY,
	Rooms.OFFICE # логично
]

var dog_path = [
	Rooms.WORKSHOP,
	Rooms.MAIN_HALL, 
	[Rooms.HALLWAY, Rooms.LEFT_VENT, Rooms.RIGHT_VENT],
	Rooms.OFFICE # логично
]

var berry_path = [
	Rooms.STAGE,
	Rooms.MAIN_HALL,
	Rooms.KITCHEN,
	Rooms.WORKSHOP,
	Rooms.HALLWAY,
	Rooms.OFFICE # логично
]

var blacky_path = [
	Rooms.STAGE,
	Rooms.MAIN_HALL,
	Rooms.ENTRANCE,
	Rooms.KITCHEN,
	Rooms.HALLWAY_PASSAGE,
	[Rooms.LEFT_VENT, Rooms.RIGHT_VENT],
	Rooms.OFFICE # логично
]

func test():
	set_berry_on(false)
	set_blacky_on(false)
	set_berry_pos(Rooms.MAIN_HALL)
	set_dog_pos(Rooms.RIGHT_VENT)
	set_old_creeper_pos(Rooms.EXTRA_WORKSHOP)
	set_blacky_pos(Rooms.RIGHT_VENT)

func _ready() -> void:
	reset_for_night()

func reset_for_night() -> void:
	old_creeper_path_index = 0
	dog_path_index = 0
	berry_path_index = 0
	blacky_path_index = 0
	old_creeper_pos = old_creeper_path[0]
	dog_pos = dog_path[0]
	berry_pos = berry_path[0]
	blacky_pos = blacky_path[0]
	old_creeper_state = Old_creeper_states.STATE1
	berry_on = false
	blacky_on = false

# path indices
var old_creeper_path_index = 0
var dog_path_index = 0
var berry_path_index = 0
var blacky_path_index = 0

# positions
var old_creeper_pos: Rooms = Rooms.NONE
var dog_pos: Rooms = Rooms.NONE
var berry_pos: Rooms = Rooms.NONE
var blacky_pos: Rooms = Rooms.NONE

var old_creeper_state = Old_creeper_states.STATE1

var blacky_on: bool
var berry_on: bool

# Передвинуть аниматроника
func next(animatronic: Animatronics, step: int = 1):
	if animatronic == Animatronics.OLD_CREEPER and old_creeper_pos < old_creeper_path.size() - 1:
		old_creeper_path_index += step
	elif animatronic == Animatronics.DOG and dog_pos < dog_path.size() - step:
		dog_path_index += step
	elif animatronic == Animatronics.BERRY and berry_pos < berry_path.size() - step:
		berry_path_index += step
	elif animatronic == Animatronics.BLACKY and blacky_pos < blacky_path.size() - step:
		blacky_path_index += step

# setters 
func set_old_creeper_pos(new_position: Rooms):
	var start = 0
	if old_creeper_path_index > 0:
		start = old_creeper_path_index
	old_creeper_path_index = old_creeper_path.find(new_position, start)
	if old_creeper_path_index != -1:
		old_creeper_pos = new_position
	else:
		old_creeper_pos = Rooms.NONE

func set_dog_pos(new_position: Rooms):
	var start = 0
	if dog_path_index > 0:
		start = dog_path_index
	dog_path_index = dog_path.find(new_position, start)
	if dog_path_index == -1 and (new_position in dog_path[dog_path.size() - 2]):
		dog_path_index = dog_path.size() - 2
	if dog_path_index != -1:
		dog_pos = new_position
	else:
		dog_pos = Rooms.NONE

func set_berry_pos(new_position: Rooms):
	var start = 0
	if berry_path_index > 0:
		start = berry_path_index
	berry_path_index = berry_path.find(new_position, start)
	if berry_path_index != -1:
		berry_pos = new_position
	else:
		berry_pos = Rooms.NONE

func set_blacky_pos(new_position: Rooms):
	var start = 0
	if blacky_path_index > 0:
		start = blacky_path_index
	blacky_path_index = blacky_path.find(new_position, start)
	if blacky_path_index == -1 and (new_position in blacky_path[blacky_path.size() - 2]):
		blacky_path_index = blacky_path.size() - 2
	if blacky_path_index != -1:
		blacky_pos = new_position
	else:
		blacky_pos = Rooms.NONE

func set_blacky_on(turned_on: bool):
	blacky_on = turned_on
	
func set_berry_on(turned_on: bool):
	berry_on = turned_on

# getters
func get_old_creeper_pos():
	return old_creeper_pos
	
func get_dog_pos():
	return dog_pos
	
func get_berry_pos():
	return berry_pos
	
func get_blacky_pos():
	return blacky_pos

func is_blacky_on():
	return blacky_on

func is_berry_on():
	return berry_on
