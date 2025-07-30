extends Camera2D

@export var BASE_CAMERA_SPEED := 600
@export var BASE_EDGE_MARGIN := 250
var camera_speed: int
var edge_margin: int  # Зона, где камера начинает поворачиваться

@onready var office_bg: TextureRect = get_parent().get_node("Office/OfficeBackground")

@onready var viewport = get_viewport()
# Всегда использовать именно это, т. к. get_viewport().size возвращает размеры из настроек, а код ниже учитывет масштаб
@onready var viewport_rect = viewport.get_visible_rect()
@onready var viewport_size = viewport_rect.size
@onready var viewport_init_size = viewport.size

var left_limit_x: int
var right_limit_x: int

func _ready():
	#Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_calculate_parameters()
	viewport.size_changed.connect(_on_viewport_size_changed)
	
func _calculate_parameters():
	camera_speed = BASE_CAMERA_SPEED * (viewport_size.x / viewport_init_size.x)
	edge_margin = BASE_EDGE_MARGIN * (viewport_size.x / viewport_init_size.x)
	
	var left_edge = office_bg.global_position.x
	var _right_edge = office_bg.global_position.x - office_bg.size.x * office_bg.scale.x / 2
	
	left_limit_x = left_edge
	right_limit_x = get_parent().global_position.x - office_bg.global_position.x
	print("Camera speed calculated: ", camera_speed, " and edge_margin: ", edge_margin)
	print("Camera limits calculated: ", left_limit_x, " to ", right_limit_x)

func _process(delta):
	_calculate_parameters()
	var mouse_pos = viewport.get_mouse_position()
	
	var move_dir = 0
	
	# Проверка есть ли курсор внутри viewport
	if not viewport_rect.has_point(mouse_pos): return
	
	if (mouse_pos.x < edge_margin):
		move_dir = -1
	elif (mouse_pos.x > viewport_size.x - edge_margin):
		move_dir = 1
	
	if move_dir != 0:
		global_position.x += move_dir * camera_speed * delta
		
	global_position.x = clamp(global_position.x, left_limit_x, right_limit_x)
	
func _on_viewport_size_changed():
	viewport = get_viewport()
	viewport_rect = viewport.get_visible_rect()
	viewport_size = viewport_rect.size
	_calculate_parameters()
	global_position.x = clamp(global_position.x, left_limit_x, right_limit_x)
