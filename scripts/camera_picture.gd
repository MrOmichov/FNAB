extends Sprite2D

@onready var layer1 = $layer1
@onready var layer2 = $layer2
@onready var layer3 = $layer3
@onready var layer4 = $layer4
@onready var layer5 = $layer5

@onready var tables_back = preload("res://assets/Ремейк игры/камера/комнаты/главный зал/декор/главный зал столы зад.png")
@onready var tables_front = preload("res://assets/Ремейк игры/камера/комнаты/главный зал/декор/главный зал столы.png")
@onready var berry_tex = preload("res://assets/Ремейк игры/камера/комнаты/главный зал/Роботы/Берри.png")
@onready var dog_tex = preload("res://assets/Ремейк игры/камера/комнаты/главный зал/Роботы/Пёс.png")
@onready var blacky_tex = preload("res://assets/Ремейк игры/камера/комнаты/главный зал/Роботы/Блеки.png")

func _make_all_null():
	layer1.texture = null
	layer2.texture = null
	layer3.texture = null
	layer4.texture = null
	layer5.texture = null
	
	scale = Vector2(0.8, 0.8)
	layer3.position.y = 0

# левая вентиляция
func set_left_vent():
	_make_all_null()
	if AnimatronicMgnt.get_blacky_pos() == AnimatronicMgnt.Rooms.LEFT_VENT:
		texture = load("res://assets/Ремейк игры/камера/комнаты/вентиляции/камера 8 Б.png")
	else:
		texture = load("res://assets/Ремейк игры/камера/комнаты/вентиляции/камера 8 .png")
	scale = Vector2(1920 * 0.8, 1080 * 0.8) / texture.get_size()
	if AnimatronicMgnt.get_dog_pos() == AnimatronicMgnt.Rooms.LEFT_VENT:
		layer1.texture = load("res://assets/Ремейк игры/камера/комнаты/вентиляции/камера 8  пёс.png")
	
# правая вентиляция
func set_right_vent():
	_make_all_null()
	if AnimatronicMgnt.get_blacky_pos() == AnimatronicMgnt.Rooms.RIGHT_VENT:
		texture = load("res://assets/Ремейк игры/камера/комнаты/вентиляции/камера 9 Б.png")
	else:
		texture = load("res://assets/Ремейк игры/камера/комнаты/вентиляции/камера 9 .png")
	scale = Vector2(1920 * 0.8, 1080 * 0.8) / texture.get_size()
	if AnimatronicMgnt.get_dog_pos() == AnimatronicMgnt.Rooms.RIGHT_VENT:
		layer1.texture = load("res://assets/Ремейк игры/камера/комнаты/вентиляции/камера 9  пёс.png")

# комната пса
func set_workshop():
	_make_all_null()
	if randi() % 1001 < 10:
		# это пасхалка TODO выдать ачивку за это
		texture = load("res://assets/Ремейк игры/камера/комнаты/комната с псом/комната с пасхалкой.png")
	else:
		texture = load("res://assets/Ремейк игры/камера/комнаты/комната с псом/комната.png")
	if AnimatronicMgnt.get_berry_pos() == AnimatronicMgnt.Rooms.WORKSHOP:
		layer1.texture = load("res://assets/Ремейк игры/камера/комнаты/комната с псом/Берри.png")
	if AnimatronicMgnt.get_dog_pos() == AnimatronicMgnt.Rooms.WORKSHOP:
		if Global.night_number < 4:
			layer2.texture = load("res://assets/Ремейк игры/камера/комнаты/комната с псом/пёс/%d ночь.png" % Global.night_number)
		else:
			layer2.texture = load("res://assets/Ремейк игры/камера/комнаты/комната с псом/пёс/4 и последующая.png")
	layer4.texture = load("res://assets/Ремейк игры/камера/комнаты/комната с псом/тёмка.png")

# коридор
func set_hallway():
	_make_all_null()
	texture = load("res://assets/Ремейк игры/камера/комнаты/коридор/коридор.png")
	if AnimatronicMgnt.get_blacky_pos() == AnimatronicMgnt.Rooms.HALLWAY_PASSAGE:
		layer1.texture = load("res://assets/Ремейк игры/камера/комнаты/коридор/коридор - Блеки.png")
	if AnimatronicMgnt.get_berry_pos() == AnimatronicMgnt.Rooms.HALLWAY:
		layer2.texture = load("res://assets/Ремейк игры/камера/комнаты/коридор/коридор - Берри.png")
	if AnimatronicMgnt.get_dog_pos() == AnimatronicMgnt.Rooms.HALLWAY:
		layer3.texture = load("res://assets/Ремейк игры/камера/комнаты/коридор/коридор - Пёс.png")
	layer4.texture = load("res://assets/Ремейк игры/камера/комнаты/коридор/тёмка.png")

# сцена
func set_stage():
	_make_all_null()
	if AnimatronicMgnt.get_berry_pos() == AnimatronicMgnt.Rooms.STAGE and AnimatronicMgnt.blacky_pos == AnimatronicMgnt.Rooms.STAGE:
		if AnimatronicMgnt.is_blacky_on() and AnimatronicMgnt.is_berry_on():
			texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/оба вкл.png")
		else:
			if AnimatronicMgnt.is_blacky_on():
				texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/Блеки вкл.png")
			elif AnimatronicMgnt.is_berry_on():
				texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/Берри вкл.png")
			else:
				texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/оба выкл.png")
	elif AnimatronicMgnt.get_berry_pos() == AnimatronicMgnt.Rooms.STAGE:
		texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/Берри один.png")
	elif AnimatronicMgnt.get_blacky_pos() == AnimatronicMgnt.Rooms.STAGE:
		texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/Блеки один.png")
	else:
		texture = load("res://assets/Ремейк игры/камера/комнаты/сцена/никого нет.png")

# главный зал
func set_main_hall():
	_make_all_null()
	if randi() % 1001 < 10:
		# это пасхалка TODO выдать ачивку за это
		texture = load("res://assets/Ремейк игры/камера/комнаты/главный зал/Главный зал пасхалка.png")
	else:
		texture = load("res://assets/Ремейк игры/камера/комнаты/главный зал/Главный зал.png")
	layer1.texture = tables_back
	layer2.texture = tables_front

	if AnimatronicMgnt.get_berry_pos() == AnimatronicMgnt.Rooms.MAIN_HALL:
		layer3.texture = berry_tex
		layer3.position.y= 45
	if AnimatronicMgnt.get_dog_pos() == AnimatronicMgnt.Rooms.MAIN_HALL:
		layer4.texture = dog_tex
	if AnimatronicMgnt.get_blacky_pos() == AnimatronicMgnt.Rooms.MAIN_HALL:
		layer5.texture = blacky_tex


func set_extra_workshop() -> void:
	_make_all_null()
	if AnimatronicMgnt.old_creeper_state == AnimatronicMgnt.Old_creeper_states.STATE1:
		texture = load("res://assets/Ремейк игры/камера/комнаты/комнатаок/комната ок 1 стадия.png")
	elif AnimatronicMgnt.old_creeper_state == AnimatronicMgnt.Old_creeper_states.STATE2:
		texture = load("res://assets/Ремейк игры/камера/комнаты/комнатаок/комната ок 2 стадия.png")
	elif AnimatronicMgnt.old_creeper_state == AnimatronicMgnt.Old_creeper_states.STATE3:
		texture = load("res://assets/Ремейк игры/камера/комнаты/комнатаок/комната ок 3 стадия.png")
	elif AnimatronicMgnt.old_creeper_state == AnimatronicMgnt.Old_creeper_states.STATE4_FINAL:
		texture = load("res://assets/Ремейк игры/камера/комнаты/комнатаок/комната ок 4 стадия фин.png")
	elif AnimatronicMgnt.old_creeper_state == AnimatronicMgnt.Old_creeper_states.OUT:
		texture = load("res://assets/Ремейк игры/камера/комнаты/комнатаок/комната без ок.png")
