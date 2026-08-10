extends "res://base_enemy.gd"

const PROJECTILE_SCENE = preload("res://projectile.tscn")

@export var enemy_kind: GameData.EnemyKind = GameData.EnemyKind.NORMAL
@export var speed: float = 30.0
@export var projectile_damage: int = 10
@export var fire_rate: float = 2.0
# Sets her initial idle facing before she's ever aggro'd (base_enemy.gd
# defaults direction = 1 / facing right). direction already drives both the
# sprite flip (_update_sprite) and the AggroZone's mirrored offset
# (_update_zones) every physics frame, so flipping it here correctly flips
# both together — no separate aggro-hitbox handling needed.
@export var flip_facing: bool = false

func _ready() -> void:
	super._ready()
	if flip_facing:
		direction = -1
		_update_zones()

func _move(_delta: float) -> void:
	if target:
		direction = sign(target.global_position.x - global_position.x)
		if deaggro_timer > 0:
			velocity.x = speed * direction
			if enemy_kind == GameData.EnemyKind.JUMPING and is_on_wall() and is_on_floor():
				velocity.y = JUMP_VELOCITY
		else:
			velocity.x = 0
			if attack_cooldown <= 0:
				_fire_projectile()
				attack_cooldown = fire_rate
	else:
		velocity.x = 0

func _fire_projectile() -> void:
	attack_anim_timer = _attack_anim_duration()
	var proj = PROJECTILE_SCENE.instantiate()
	var aim_dir = (target.global_position - global_position).normalized()
	proj.aim_direction = aim_dir
	proj.damage = projectile_damage
	proj.position = global_position + aim_dir * 20
	get_parent().call_deferred("add_child", proj)
