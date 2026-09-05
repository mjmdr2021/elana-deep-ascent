extends CharacterBody2D

@export var max_hp: int = 30
@export var xp_reward: int = 60
@export var defense: int = 0
@export var hp_regen: float = 0.0
@export var deaggro_time: float = 2.0
@export var freeze_sprite_on_stun: bool = true
var skip_removed_check: bool = false

# Elemental damage multipliers — 1.0 = normal, >1.0 = weak (takes more),
# <1.0 = resistant (takes less), 0.0 = fully immune. Read by
# hit_handler.gd's on_elemental_hit(); default 1.0 leaves every existing
# enemy unaffected unless overridden per-instance.
@export_group("Elemental Resistance")
@export var fire_resist: float = 1.0
@export var frost_resist: float = 1.0
@export var elec_resist: float = 1.0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var hp: float
var direction: int = 1
var original_color: Color
var target = null
var is_stunned: bool = false
var is_frozen: bool = false
var stun_timer: float = 0.0
var freeze_immune_timer: float = 0.0
var burn_damage: int = 0
var burn_ticks_remaining: int = 0
var burn_tick_timer: float = 0.0
var slow_timer: float = 0.0
var slow_factor: float = 1.0
var poison_damage: int = 0
var poison_ticks_remaining: int = 0
var poison_tick_timer: float = 0.0
var _pending_knockback: Vector2 = Vector2.ZERO
var deaggro_timer: float = 0.0
var regen_delay_timer: float = 0.0
var aggro_zone_offset: float = 0.0
var attack_cooldown: float = 0.0
const JUMP_VELOCITY = -280.0
@export var attack_damage: int = 10
@export var attack_cooldown_time: float = 1.0
@export var attack_windup_time: float = 0.25
# 1.0 = normal pace, <1.0 = slower attacks (cooldown stretches), >1.0 =
# faster (cooldown shrinks) — same "higher number is stronger/faster"
# convention as Elana's own attack_speed_stat, unlike attack_cooldown_time
# itself where a bigger number means slower. get_effective_attack_cooldown()
# below is what actually applies it; every place that used to hard-code
# "attack_cooldown = attack_cooldown_time" (this file, lava_golem.gd,
# elemental_golem.gd) now goes through that instead, so a single per-enemy
# stat controls pace everywhere instead of only wherever someone remembers
# to read attack_cooldown_time directly.
@export var attack_speed_mult: float = 1.0

func get_effective_attack_cooldown() -> float:
	return attack_cooldown_time / max(0.01, attack_speed_mult)
var elana_in_attack_zone: bool = false
var attack_windup_timer: float = 0.0
var attack_anim_timer: float = 0.0  # generic "show attack anim" window — ranged enemies set this on fire

@onready var hp_bar = $HPBar
@onready var hp_fill = $HPBar/Fill
@onready var hp_bg = $HPBar/Background
@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
var _was_stunned_sprite: bool = false

# EyeGlow — optional PointLight2D placed by hand to match the sprite's eye
# while facing right (direction = 1). When she flips to face left, shift it
# left by a flat amount rather than a true mirror (the eye isn't necessarily
# centered on the sprite, so mirroring around x=0 wouldn't line up).
@onready var _eye_glow = get_node_or_null("EyeGlow")
var _eye_glow_base_x: float = 0.0
const EYE_GLOW_FLIP_SHIFT: float = 12.0

# Proximity activation — AI/movement (_physics_process) only runs near the
# player; far enemies just sit idle instead of ticking pathing/attacks for
# someone who isn't there. Checked on a cheap timer, not every frame, and via
# a lightweight _process() that stays on even while _physics_process is off.
# Hitting/killing a dormant enemy still works — on_hit() is a direct call
# from Elana's swing, not dependent on this node's own processing.
# Two separate bands: visible-but-frozen between ACTIVATION_RADIUS and
# VISIBILITY_RADIUS (pops into view before it starts moving, instead of
# appearing already active), fully active once inside ACTIVATION_RADIUS.
const ACTIVATION_RADIUS: float = 700.0
const VISIBILITY_RADIUS: float = 900.0
const ACTIVATION_CHECK_INTERVAL: float = 0.3
var _activation_check_timer: float = 0.0

func _process(delta: float) -> void:
	_activation_check_timer -= delta
	if _activation_check_timer > 0.0:
		return
	_activation_check_timer = ACTIVATION_CHECK_INTERVAL
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var dist = global_position.distance_to(player.global_position)
	var should_be_visible = dist <= VISIBILITY_RADIUS
	var should_be_active = dist <= ACTIVATION_RADIUS
	if should_be_visible != visible:
		visible = should_be_visible
	if should_be_active != is_physics_processing():
		set_physics_process(should_be_active)
		# Same "only while actually damaged" rule _update_hp_bar() enforces
		# — this only needs to additionally handle should_be_active turning
		# false (that function won't run again to hide it once physics
		# processing stops), since re-activating just lets that function's
		# own check take back over next tick anyway.
		hp_bar.visible = should_be_active and GameData.show_hp_bars and hp < max_hp

func _ready() -> void:
	# skip_removed_check exempts dynamically-spawned enemies (Splitter's
	# split copies, Seed Mortar's hatched Swarmers, etc.) from the
	# is_removed lookup below, which is meant for statically-placed level
	# enemies ("you already killed the one at this spot, don't respawn it").
	# A dynamic spawn's auto-generated node name can coincidentally collide
	# with an unrelated already-killed enemy's name, silently self-freeing
	# it here before it ever renders.
	if not skip_removed_check and GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	add_to_group("enemies")
	hp = max_hp
	# 2026-09-06, real bug found (Voltangler's placeholder ColorRect replaced
	# with real sprite art, error: "Invalid access to property or key
	# 'color' on a base object of type 'null instance'") -- this hardcoded
	# $ColorRect unconditionally, assuming every enemy has one. Every other
	# sprite-converted enemy so far (Mantrap, Spark Jelly/Eel/Flies) survived
	# by coincidence -- flying_enemy.tscn/enemy.tscn both still keep a
	# leftover ColorRect around, hidden but present. Voltangler's scene is
	# the first to actually remove the node instead of leaving a dead
	# placeholder, so this finally surfaced. Null-safe lookup instead,
	# falling back to white (a sprite's natural resting modulate) for
	# sprite-only enemies -- same ColorRect-or-sprite branch hit_handler.gd's
	# own _set_flash_color() already uses, just applied to the capture side
	# too now.
	var visual_rect = get_node_or_null("ColorRect")
	original_color = visual_rect.color if visual_rect else Color.WHITE
	aggro_zone_offset = abs($AggroZone.position.x)
	if _eye_glow:
		_eye_glow_base_x = _eye_glow.position.x
	$Hurtbox.input_pickable = false
	$AggroZone.body_entered.connect(_on_aggro_zone_body_entered)
	$AggroZone.body_exited.connect(_on_aggro_zone_body_exited)
	var attack_zone = get_node_or_null("AttackZone")
	if attack_zone:
		attack_zone.body_entered.connect(_on_attack_zone_body_entered)
		attack_zone.body_exited.connect(_on_attack_zone_body_exited)

func _on_aggro_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		target = body
		deaggro_timer = 0.0

func _on_aggro_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		deaggro_timer = deaggro_time

func _physics_process(delta: float) -> void:
	if _pending_knockback != Vector2.ZERO:
		velocity = _pending_knockback
		stun_timer = max(stun_timer, 0.5)
		is_stunned = true
		_pending_knockback = Vector2.ZERO
	_apply_gravity(delta)
	_tick_attack(delta)
	# Pause horizontal movement for the whole attacking state (windup through
	# the swing's animation tail) — mirrors the sprite already showing the
	# "attack" anim for this exact window, so the visual and the motion agree.
	var is_attacking_now = attack_windup_timer > 0.0 or attack_anim_timer > 0.0
	if not is_stunned and not is_attacking_now:
		_move(delta)
		if slow_timer > 0.0:
			velocity.x *= slow_factor
	elif not is_stunned:
		velocity.x = 0.0
	_update_zones()
	_update_hp_bar()
	_update_sprite()
	_tick_timers(delta)
	move_and_slide()

# Walk/attack/idle — shared by every enemy type. "Attack" covers both the
# melee windup (attack_windup_timer) and a ranged enemy's brief post-fire
# flash (attack_anim_timer), so both subclasses get correct animations for free.
func _update_sprite() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	_sprite.flip_h = direction > 0
	# Stunned enemies freeze on whatever frame they were on the instant the
	# stun landed, instead of continuing to play through their animation —
	# except types that opt out (flying_enemy keeps idling mid-air).
	if is_stunned and freeze_sprite_on_stun:
		if _sprite.is_playing():
			_sprite.pause()
		_was_stunned_sprite = true
		return
	if _was_stunned_sprite:
		_was_stunned_sprite = false
		_sprite.play()
	var frames = _sprite.sprite_frames
	var anim: String = ""
	if (attack_windup_timer > 0.0 or attack_anim_timer > 0.0) and frames.has_animation("attack"):
		anim = "attack"
	elif abs(velocity.x) > 5.0 and frames.has_animation("walk"):
		anim = "walk"
	elif frames.has_animation("idle"):
		anim = "idle"
	if anim != "" and _sprite.animation != anim:
		_sprite.play(anim)

# How long the "attack" animation actually takes to play through once —
# read from the SpriteFrames data instead of guessing a constant, so it
# stays correct if the animation's frame count/speed ever changes.
func _attack_anim_duration() -> float:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("attack"):
		return 0.0
	var frame_count = _sprite.sprite_frames.get_frame_count("attack")
	var speed = _sprite.sprite_frames.get_animation_speed("attack")
	return float(frame_count) / speed if speed > 0.0 else 0.0

# Time to reach the 5th frame (index 4) of the attack animation — the hit
# lands there instead of on a flat generic windup, syncing damage to the swing.
func _attack_hit_delay() -> float:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("attack"):
		return attack_windup_time
	var speed = _sprite.sprite_frames.get_animation_speed("attack")
	return 4.0 / speed if speed > 0.0 else attack_windup_time

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

func _on_attack_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		elana_in_attack_zone = true

func _on_attack_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		elana_in_attack_zone = false
		attack_windup_timer = 0.0

# Repeating windup → hit → cooldown cycle. A fresh windup (and its animation)
# starts every time the cooldown clears, not just on the first entry, so
# standing in front of the enemy continuously still shows the swing each time.
func _tick_attack(delta: float) -> void:
	if is_stunned or not elana_in_attack_zone or attack_cooldown > 0:
		return
	if attack_windup_timer > 0:
		attack_windup_timer -= delta * slow_factor
		if attack_windup_timer <= 0:
			_perform_attack()
		return
	attack_windup_timer = _attack_hit_delay()
	attack_anim_timer = max(attack_anim_timer, _attack_anim_duration())

func _perform_attack() -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana:
		$WallCheck.target_position = to_local(elana.global_position)
		$WallCheck.force_raycast_update()
		if not $WallCheck.is_colliding():
			elana.take_damage(attack_damage, false, self)
	attack_cooldown = get_effective_attack_cooldown()

func _move(_delta: float) -> void:
	pass

func _update_zones() -> void:
	$AggroZone.position.x = aggro_zone_offset * direction
	if _eye_glow:
		_eye_glow.position.x = _eye_glow_base_x - EYE_GLOW_FLIP_SHIFT if direction < 0 else _eye_glow_base_x

func _update_hp_bar() -> void:
	# Only shown while actually damaged — hides again once hp regenerates
	# (or gets healed) back to full, rather than sitting on screen
	# permanently at max. Still fully gated behind the dev toggle either way.
	hp_bar.visible = GameData.show_hp_bars and hp < max_hp
	hp_fill.size.x = clamp(float(hp) / float(max_hp), 0.0, 1.0) * hp_bg.size.x

func apply_burn(damage_per_tick: int, ticks: int = 5) -> void:
	burn_damage = max(burn_damage, damage_per_tick)
	burn_ticks_remaining = max(burn_ticks_remaining, ticks)
	burn_tick_timer = 1.0

func apply_slow(factor: float, duration: float) -> void:
	slow_factor = min(slow_factor, factor)
	slow_timer = max(slow_timer, duration)
	modulate = Color(0.75, 0.88, 1.0)

func apply_poison(damage_per_tick: int, ticks: int = 8) -> void:
	poison_damage = max(poison_damage, damage_per_tick)
	poison_ticks_remaining = max(poison_ticks_remaining, ticks)
	poison_tick_timer = 1.0

func _tick_timers(delta: float) -> void:
	if not is_stunned:
		attack_cooldown -= delta * slow_factor
		if attack_anim_timer > 0.0:
			attack_anim_timer -= delta
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
			if is_frozen:
				is_frozen = false
				# Same ColorRect-or-sprite generalization as original_color's
				# own capture above -- this used to hardcode $ColorRect too.
				var visual_rect = get_node_or_null("ColorRect")
				if visual_rect:
					visual_rect.color = original_color
				elif _sprite:
					_sprite.modulate = original_color
	if freeze_immune_timer > 0.0:
		freeze_immune_timer -= delta
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			modulate = Color.WHITE
	if burn_ticks_remaining > 0:
		burn_tick_timer -= delta
		if burn_tick_timer <= 0.0:
			burn_tick_timer = 1.0
			burn_ticks_remaining -= 1
			hp -= burn_damage
			regen_delay_timer = 3.0
			GameData.spawn_damage_number(burn_damage, global_position, Color(1.0, 0.45, 0.05))
			if hp <= 0:
				burn_ticks_remaining = 0
				$HitHandler._die()
	if poison_ticks_remaining > 0:
		poison_tick_timer -= delta
		if poison_tick_timer <= 0.0:
			poison_tick_timer = 1.0
			poison_ticks_remaining -= 1
			hp -= poison_damage
			regen_delay_timer = 3.0
			GameData.spawn_damage_number(poison_damage, global_position, Color(0.4, 0.9, 0.3))
			if hp <= 0:
				poison_ticks_remaining = 0
				$HitHandler._die()
	if deaggro_timer > 0:
		deaggro_timer -= delta
		if deaggro_timer <= 0:
			target = null
	if regen_delay_timer > 0.0:
		regen_delay_timer -= delta
	elif hp_regen > 0.0 and hp > 0 and hp < max_hp:
		hp = min(max_hp, hp + hp_regen * delta)

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	$HitHandler.on_elemental_hit(element, hit_direction, damage, attacker)

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	$HitHandler.on_hit(hit_direction, damage, is_magic, attacker)
