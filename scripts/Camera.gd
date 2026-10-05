extends Camera2D

@export var BASE_CAMERA_SPEED = 650
@export var BASE_EDGE_MARGIN := 250
@onready var officeBackgroundSprite: Sprite2D = get_parent().get_node("Office/OfficeBackground")

var camera_speed: int
var edge_margin: int  # Зона, где камера начинает поворачиваться

@onready var viewport = get_viewport()
# Всегда использовать именно это, т. к. get_viewport().size возвращает размеры из настроек, а код ниже учитывет масштаб
@onready var viewport_rect = viewport.get_visible_rect()
@onready var viewport_size = viewport_rect.size
@onready var viewport_init_size = viewport.size

var left_limit_x: int
var right_limit_x: int

func _ready():
	viewport.size_changed.connect(_on_viewport_size_changed)
	if officeBackgroundSprite:
		# Слишком длинно, вызовы функций дублируют друг дргуа .get_width(), например
		# TODO Вынести в переменные
		position.x = (officeBackgroundSprite.texture.get_width() - viewport_rect.size.x) / 2
	
func _calculate_parameters():
	camera_speed = BASE_CAMERA_SPEED * (viewport_size.x / viewport_init_size.x)
	edge_margin = BASE_EDGE_MARGIN * (viewport_size.x / viewport_init_size.x)
	
	var left_edge = officeBackgroundSprite.global_position.x
	var _right_edge = officeBackgroundSprite.global_position.x - officeBackgroundSprite.size.x * officeBackgroundSprite.scale.x / 2
	
	left_limit_x = left_edge
	right_limit_x = get_parent().global_position.x - officeBackgroundSprite.global_position.x
	print("Camera speed calculated: ", camera_speed, " and edge_margin: ", edge_margin)
	print("Camera limits calculated: ", left_limit_x, " to ", right_limit_x)

func _process(delta):
	var night = get_parent()
	if not night.is_player_input_allowed():
		return
	var visible_size := get_viewport().get_visible_rect().size
	var mouse_pos_x := get_viewport().get_mouse_position().x
	var direction = 0
	if mouse_pos_x < minf(BASE_EDGE_MARGIN, visible_size.x * 0.25):
		direction = -1
	elif mouse_pos_x > visible_size.x - minf(BASE_EDGE_MARGIN, visible_size.x * 0.25):
		direction = 1

	var background_width := officeBackgroundSprite.texture.get_width() * officeBackgroundSprite.scale.x
	position.x = clampf(position.x + direction * BASE_CAMERA_SPEED * delta, 0.0, maxf(0.0, background_width - visible_size.x))
	
func _on_viewport_size_changed():
	pass
