class_name NightConfig
extends Resource

@export var night_number: int = 1
@export var end_hour: int = 7
@export var seconds_per_minute: float = 1.0
@export var power_capacity: float = 1000.0
@export var base_consumption: int = 1
@export var door_extra_consumption: int = 1
@export var fan_extra_consumption: int = 1
@export var power_out_grace_seconds: float = 10.0
@export_range(0, 20) var sann_level: int = 1
@export_range(0, 20) var dog_level: int = 0
@export_range(0, 20) var berry_level: int = 0
@export_range(0, 20) var blacky_level: int = 0
@export_range(0, 20) var old_creeper_level: int = 0
@export var sann_initial_grace_seconds: float = 60.0
@export var sann_check_interval_seconds: float = 5.0
@export var sann_warning_seconds: float = 3.65
@export var sann_success_grace_seconds: float = 15.0
@export var sann_warning_urgent_seconds: float = 1.0
@export var route_initial_grace_seconds: float = 30.0
@export var route_check_interval_seconds: float = 5.0
@export var route_success_grace_seconds: float = 15.0
@export var route_defense_hold_seconds: float = 1.0
@export var berry_warning_seconds: float = 4.01
@export var dog_warning_seconds: float = 2.97
@export var blacky_warning_seconds: float = 4.03
@export var old_creeper_warning_seconds: float = 4.65
@export var dog_move_acceleration_seconds: float = 0.5
@export var dog_min_check_interval_seconds: float = 1.0
@export var shock_cost: float = 20.0
@export var shock_cooldown_seconds: float = 8.0
