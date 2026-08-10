extends "res://ranged_enemy.gd"

# Stationary, same skeleton as Spitting Bloom / Fire Plant Spitter — fires
# frost_bolt.tscn (slow + freeze chance) instead of a damage-only shot.
const FROST_BOLT_SCENE = preload("res://frost_bolt.tscn")
const VISUAL_COLOR: Color = Color(0.35, 0.65, 0.9, 1.0)
const VISUAL_SIZE: float = 22.0

func _ready() -> void:
	# ColorRect's color must be set BEFORE super._ready() — base_enemy.gd
	# captures it as original_color for the hit-flash system at that point.
	$AnimatedSprite2D.visible = false
	$ColorRect.color = VISUAL_COLOR
	$ColorRect.offset_left = -VISUAL_SIZE / 2.0
	$ColorRect.offset_top = -VISUAL_SIZE / 2.0
	$ColorRect.offset_right = VISUAL_SIZE / 2.0
	$ColorRect.offset_bottom = VISUAL_SIZE / 2.0
	$ColorRect.visible = true
	super._ready()

func _move(_delta: float) -> void:
	velocity.x = 0
	if target:
		direction = sign(target.global_position.x - global_position.x)
		if attack_cooldown <= 0:
			_fire_projectile()
			attack_cooldown = fire_rate

func _fire_projectile() -> void:
	attack_anim_timer = _attack_anim_duration()
	var bolt = FROST_BOLT_SCENE.instantiate()
	var aim_dir = (target.global_position - global_position).normalized()
	bolt.aim_direction = aim_dir
	bolt.position = position + aim_dir * 20.0
	get_parent().call_deferred("add_child", bolt)
