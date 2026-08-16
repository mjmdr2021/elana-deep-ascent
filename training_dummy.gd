extends CharacterBody2D

const MAX_HP: float = 1000.0
const HP_REGEN: float = 80.0

var hp: float = MAX_HP
var defense: int = 0
var is_stunned: bool = false
var is_frozen: bool = false
var stun_timer: float = 0.0
var freeze_immune_timer: float = 0.0
var burn_damage: int = 0
var burn_ticks_remaining: int = 0
var burn_tick_timer: float = 0.0
var poison_damage: int = 0
var poison_ticks_remaining: int = 0
var poison_tick_timer: float = 0.0
var _pending_knockback: Vector2 = Vector2.ZERO
var direction: int = 1
var regen_delay_timer: float = 0.0
var xp_reward: int = 0
var immortal: bool = true
var original_color := Color.WHITE

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

var _hp_fill: ColorRect
var _hp_bg: ColorRect

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1

	$AnimatedSprite2D.play("idle")

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(20, 40)
	shape.position = Vector2(0, -20)
	shape.shape = rect
	add_child(shape)

	var hurtbox = Area2D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	var hb_shape = CollisionShape2D.new()
	var hb_rect = RectangleShape2D.new()
	hb_rect.size = Vector2(20, 40)
	hb_shape.position = Vector2(0, -20)
	hb_shape.shape = hb_rect
	hurtbox.input_pickable = false
	hurtbox.add_child(hb_shape)
	add_child(hurtbox)

	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0.2, 0.2, 0.2)
	_hp_bg.size = Vector2(36, 5)
	_hp_bg.position = Vector2(-18, -50)
	add_child(_hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.2, 0.75, 0.2)
	_hp_fill.size = Vector2(36, 5)
	_hp_fill.position = Vector2(-18, -50)
	add_child(_hp_fill)

	var label = Label.new()
	label.text = "DUMMY"
	label.position = Vector2(-18, -63)
	label.add_theme_font_size_override("font_size", 10)
	add_child(label)

	var hit_handler = load("res://hit_handler.gd").new()
	hit_handler.name = "HitHandler"
	add_child(hit_handler)

func _physics_process(delta: float) -> void:
	if _pending_knockback != Vector2.ZERO:
		velocity = _pending_knockback
		stun_timer = max(stun_timer, 0.5)
		is_stunned = true
		_pending_knockback = Vector2.ZERO
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
			if is_frozen:
				is_frozen = false
				$AnimatedSprite2D.modulate = original_color
	if freeze_immune_timer > 0.0:
		freeze_immune_timer -= delta
	if burn_ticks_remaining > 0:
		burn_tick_timer -= delta
		if burn_tick_timer <= 0.0:
			burn_tick_timer = 1.0
			burn_ticks_remaining -= 1
			hp -= burn_damage
			hp = max(0.0, hp)
			regen_delay_timer = 3.0
			GameData.spawn_damage_number(burn_damage, global_position, Color(1.0, 0.45, 0.05))
	if poison_ticks_remaining > 0:
		poison_tick_timer -= delta
		if poison_tick_timer <= 0.0:
			poison_tick_timer = 1.0
			poison_ticks_remaining -= 1
			hp -= poison_damage
			hp = max(0.0, hp)
			regen_delay_timer = 3.0
			GameData.spawn_damage_number(poison_damage, global_position, Color(0.4, 0.9, 0.3))
	if not is_on_floor():
		velocity.y += gravity * delta
	if not is_stunned:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if regen_delay_timer > 0.0:
		regen_delay_timer -= delta
	elif hp < MAX_HP:
		hp = min(MAX_HP, hp + HP_REGEN * delta)
	_hp_fill.size.x = (hp / MAX_HP) * _hp_bg.size.x
	move_and_slide()

func apply_burn(damage_per_tick: int, ticks: int = 5) -> void:
	burn_damage = max(burn_damage, damage_per_tick)
	burn_ticks_remaining = max(burn_ticks_remaining, ticks)
	burn_tick_timer = 1.0

func apply_poison(damage_per_tick: int, ticks: int = 8) -> void:
	poison_damage = max(poison_damage, damage_per_tick)
	poison_ticks_remaining = max(poison_ticks_remaining, ticks)
	poison_tick_timer = 1.0

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	$HitHandler.on_hit(hit_direction, damage, is_magic, attacker)

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	$HitHandler.on_elemental_hit(element, hit_direction, damage, attacker)
