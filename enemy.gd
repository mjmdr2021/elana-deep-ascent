extends "res://base_enemy.gd"

@export var enemy_type: GameData.EnemyType = GameData.EnemyType.PATROL
@export var enemy_kind: GameData.EnemyKind = GameData.EnemyKind.NORMAL
@export var speed: float = 30.0
@export var chase_speed: float = 50.0
var patrol_range: float = 100.0
var start_position: Vector2
var wall_flip_timer: float = 0.0
var stop_distance: float = 20.0

func _ready() -> void:
	super._ready()
	start_position = position
func _move(_delta: float) -> void:
	if target:
		var dist = abs(target.position.x - position.x)
		if dist > stop_distance:
			direction = sign(target.position.x - position.x)
			velocity.x = chase_speed * direction
		else:
			velocity.x = 0
		if enemy_kind == GameData.EnemyKind.JUMPING and is_on_wall() and is_on_floor():
			velocity.y = JUMP_VELOCITY
	elif enemy_type == GameData.EnemyType.PATROL:
		velocity.x = speed * direction
		if position.x > start_position.x + patrol_range:
			direction = -1
		elif position.x < start_position.x - patrol_range:
			direction = 1
		if is_on_wall() and wall_flip_timer <= 0:
			direction *= -1
			wall_flip_timer = 0.5
	elif enemy_type == GameData.EnemyType.STATIONARY:
		velocity.x = 0

func _update_zones() -> void:
	super._update_zones()
	$AttackZone.position.x = 12.0 * direction

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	wall_flip_timer -= delta
