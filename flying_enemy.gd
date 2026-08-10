extends "res://base_enemy.gd"

@export var speed: float = 40.0
@export var chase_speed: float = 80.0
var hover_time: float = 0.0
var patrol_range: float = 100.0
var start_position: Vector2
var attack_zone_offset: float = 0.0

func _ready() -> void:
	super._ready()
	freeze_sprite_on_stun = false
	start_position = position
	attack_zone_offset = abs($AttackZone.position.x)
func _apply_gravity(delta: float) -> void:
	hover_time += delta

func _move(_delta: float) -> void:
	if target:
		velocity = (target.global_position - global_position).normalized() * chase_speed
		direction = 1 if target.global_position.x >= global_position.x else -1
	else:
		velocity.x = speed * direction
		velocity.y = sin(hover_time * 2.0) * 25.0
		if position.x > start_position.x + patrol_range:
			direction = -1
		elif position.x < start_position.x - patrol_range:
			direction = 1

func _update_zones() -> void:
	super._update_zones()
	$AttackZone.position.x = attack_zone_offset * direction
