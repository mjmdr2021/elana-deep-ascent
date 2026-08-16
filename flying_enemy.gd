extends "res://base_enemy.gd"

@export var speed: float = 40.0
@export var chase_speed: float = 80.0
# How far ahead $WallCheck probes during patrol — see _patrol_wall_ahead().
@export var patrol_wall_check_dist: float = 24.0
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
		if _patrol_wall_ahead():
			direction *= -1
		velocity.x = speed * direction
		velocity.y = sin(hover_time * 2.0) * 25.0
		if position.x > start_position.x + patrol_range:
			direction = -1
		elif position.x < start_position.x - patrol_range:
			direction = 1

# Reuses $WallCheck (already on every flying_enemy.tscn-based scene, same
# node _perform_attack() points at Elana) rather than adding a second
# RayCast2D — the two never run in the same frame anyway (this only fires
# while patrolling with no target; the attack check only fires once there
# IS one). Straight-ahead probe in whichever direction she's currently
# flying, terrain layer only, so patrol turns around at a real wall instead
# of just flying through it (the old fixed patrol_range distance check below
# still runs too, as a plain "don't wander too far" leash independent of
# this).
func _patrol_wall_ahead() -> bool:
	$WallCheck.target_position = Vector2(patrol_wall_check_dist * direction, 0)
	$WallCheck.force_raycast_update()
	return $WallCheck.is_colliding()

func _update_zones() -> void:
	super._update_zones()
	$AttackZone.position.x = attack_zone_offset * direction
