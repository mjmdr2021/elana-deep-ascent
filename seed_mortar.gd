extends "res://ranged_enemy.gd"

# Stationary, like Spitting Bloom — never moves. Fires a real arced,
# gravity-affected seed_projectile.tscn aimed at Elana's position — small
# direct damage if it connects mid-flight, or hatches into a Swarmer where
# it lands if it doesn't.
const SEED_PROJECTILE_SCENE = preload("res://seed_projectile.tscn")
@export var seed_damage: int = 6
@export var seed_flight_time: float = 0.8
const VISUAL_COLOR: Color = Color(0.5, 0.35, 0.15, 1.0)
const VISUAL_SIZE: float = 24.0

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

# Overrides ranged_enemy.gd's projectile-firing entirely — launches a real
# arced seed instead of ranged_enemy.gd's straight-line projectile.tscn.
func _fire_projectile() -> void:
	attack_anim_timer = _attack_anim_duration()
	var seed = SEED_PROJECTILE_SCENE.instantiate()
	seed.damage = seed_damage
	seed.setup_launch(global_position, target.global_position, seed_flight_time)
	get_parent().call_deferred("add_child", seed)
