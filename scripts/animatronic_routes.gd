class_name AnimatronicRoutes
extends Resource

# Room IDs match AnimatronicMgnt.Rooms. Branch entries are selected uniformly.
@export var old_creeper_path: Array = [2, 1, 5, 7, 11]
@export var dog_path: Array = [1, 5, 7, 11]
@export var berry_path: Array = [3, 5, 6, 1, 7, 11]
@export var blacky_path: Array = [3, 5, 4, 6, 8, [9, 10], 11]

func get_character_path(character: int) -> Array:
	match character:
		0: return old_creeper_path
		1: return dog_path
		2: return berry_path
		3: return blacky_path
	return []
