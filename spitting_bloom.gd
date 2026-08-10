extends "res://ranged_enemy.gd"

# Stationary spore turret — never moves at all (fully overrides _move(),
# no chase/patrol). No sprite art yet — visualized with a plain ColorRect.
const VISUAL_COLOR: Color = Color(0.35, 0.65, 0.3, 1.0)
const VISUAL_SIZE: float = 24.0

func _ready() -> void:
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
