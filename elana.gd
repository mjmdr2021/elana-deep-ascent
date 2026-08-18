extends CharacterBody2D

@export var flip_offset_x: float = 0.0  # nudges the sprite when facing left, to compensate for off-center art
var _sprite_base_x: float = 0.0
const MOVE_SPEED = 100.0
const JUMP_VELOCITY = -300.0
const WALL_SLIDE_MAX_SPEED = 40.0
const WALL_CLIMB_SPEED: float = 80.0
const FLOAT_FALL_SPEED: float = 15.0
const SWIM_SPEED: float = 55.0
const SWIM_ACCEL: float = 220.0
const SWIM_DRIFT_SPEED: float = 12.0
const WATER_ENTRY_DAMPING: float = 0.2
const SURFACE_JUMP_MULT: float = 0.55
const SURFACE_JUMP_TERRAIN_RANGE: float = 24.0
var _in_water: bool = false
var _was_in_water: bool = false
var _at_water_surface: bool = false
var _knockback_timer: float = 0.0
var _knockback_ignores_gravity: bool = false
var _last_valid_position: Vector2 = Vector2.ZERO
var _nan_recovery_streak: int = 0
var _last_recovery_position: Vector2 = Vector2.INF
const NAN_RECOVERY_SAFE_DISTANCE: float = 30.0
var _default_floor_snap_length: float = 0.0
const WALL_JUMP_PUSH = 240.0
const GRAPPLE_PULL_SPEED: float = 325.0
const DialogueData = preload("res://dialogue_data.gd")
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var is_attacking = false
var spawn_point = Vector2(30, 0)
var facing = 1
var is_wall_sliding = false
var _wall_jump_input_locked = false
var _wall_jump_lock_timer = 0.0
const WALL_JUMP_LOCK_DURATION: float = 0.4
var _auto_stick_timer = 0.0
const AUTO_STICK_DURATION: float = 1.0
var can_double_jump = false
var is_dodging = false
var _is_dead = false
var is_stunned: bool = false
var is_frozen: bool = false
# Distinct from is_frozen — both block input the same way (is_stunned
# gates that), but freeze also hard-stops her (velocity = Vector2.ZERO in
# apply_freeze()) while shocked deliberately leaves velocity untouched, so
# whatever momentum she had carries through the stun instead of snapping to
# a dead stop. Cleared alongside is_frozen when stun_timer expires.
var is_shocked: bool = false
# Position pinned to _trap_anchor every physics frame (see the early-return
# block near the top of _physics_process) — e.g. Ceiling Grabber's tongue
# hold. Not merged into is_frozen/is_shocked's shared stun_timer countdown;
# released explicitly by whatever trapped her (release_trap()), not on a
# timer, since how long it lasts is up to that source (breaking the tongue,
# killing the grabber, etc.), not a fixed duration.
var is_trapped: bool = false
var _trap_anchor: Node = null
var _trap_offset: Vector2 = Vector2.ZERO
var stun_timer: float = 0.0
var slow_timer: float = 0.0
var slow_factor: float = 1.0
var jump_weight_timer: float = 0.0
var jump_weight_factor: float = 1.0
var burn_damage: int = 0
var burn_ticks_remaining: int = 0
var burn_tick_timer: float = 0.0
var poison_damage: int = 0
var poison_ticks_remaining: int = 0
var poison_tick_timer: float = 0.0
var on_slippery_tile: bool = false
const SLIPPERY_ACCEL: float = 120.0
var dodge_timer = 0.0
var dodge_cooldown = 0.0
var is_air_dashing = false
var air_dash_timer = 0.0
var can_air_dash = true
var _dash_dir: int = 1
var elemental_cooldown_timer: float = 0.0
var _hit_this_swing: Array = []
var _elec_was_active: bool = false
var jump_buffer_timer: float = 0.0
var is_charging: bool = false
var charge_timer: float = 0.0
var is_heavy_attack: bool = false
var is_plunge_attacking: bool = false
var is_blocking: bool = false
var _is_spinning: bool = false
var _spear_dash_timer: float = 0.0
var _spear_dash_speed: float = 0.0
var _grapple_direction: Vector2 = Vector2.ZERO
var _grapple_timer: float = 0.0
var _story_glow_active: bool = false
var _story_glow_elapsed: float = 0.0
const STORY_GLOW_PULSE_SPEED: float = 8.0
var _override_hitbox_size: Vector2 = Vector2.ZERO
var _sprite: AnimatedSprite2D = null
var _was_attacking_anim: bool = false
var _fist_attack_anim: String = "attack_fist"
var _idle_timer: float = 0.0
var _idle_normal_active: bool = false
const IDLE_NORMAL_THRESHOLD: float = 5.0
var _zoom_target: Vector2 = Vector2(4.0, 4.0)
var _zoom_return_timer: float = 0.0
var _zoom_lerp_speed: float = 5.0
# Screen shake — trauma-based (Camera2D.offset = camera_offset_base + shake,
# shake amount = trauma², so it's calm most of the time with sharp spikes on
# hard hits instead of a constant jitter). camera_offset_base is public
# because dialog_marker.gd's boss-arena pan tweens it directly instead of
# Camera.offset, so the two never fight over the same property.
var camera_offset_base: Vector2 = Vector2.ZERO
# Godot's own "effectively unlimited" defaults, captured in _ready() —
# _update_camera_lock() swaps $Camera's limit_left/top/right/bottom
# between these and a boss's actual bounds.
var _default_camera_limit_left: int
var _default_camera_limit_top: int
var _default_camera_limit_right: int
var _default_camera_limit_bottom: int
var _shake_trauma: float = 0.0
const SHAKE_DECAY: float = 2.5
const SHAKE_MAX_OFFSET: float = 5.0
var _suppress_gravity: bool = false
var is_herb_charging: bool = false
var herb_charge_timer: float = 0.0
var _herb_skill_pending: bool = false
var _casting_herb_skill: bool = false
var _cast_lock_timer: float = 0.0
const HERB_CAST_LOCK_DURATION: float = 0.3
var _storm_active: bool = false
var _blood_fury_active: bool = false
var _life_barrier_active: bool = false
var _iron_body_timer: float = 0.0
var _last_stand_triggered: bool = false
var _overheal_shield_hp: float = 0.0
var _iron_body_shield_hp: float = 0.0
var _life_barrier_visual: Sprite2D = null
var _blood_fury_visual: Sprite2D = null
var _sprite_effects_material: ShaderMaterial = null
const ATTACK_WINDUP: float = 0.1
const CHARGE_THRESHOLD = 0.3
const HERB_CHARGE_THRESHOLD: float = 0.4
const DODGE_SPEED = 200.0
const DODGE_DURATION = 0.18
const DODGE_COOLDOWN = 0.8
const AIR_DASH_SPEED = 280.0
const AIR_DASH_DURATION = 0.22
const ELEMENTAL_COOLDOWN = 0.5
const JUMP_BUFFER_WINDOW = 0.15
const PLUNGE_SPEED: float = 325.0
const PLUNGE_SPEED_CHAIN: float = 525.0
const PLUNGE_DESCENT_MULT: float = 0.3
const PLUNGE_LAND_MULT: float = 0.85
const ATTACK_SPEED_R_MAX: float = 0.40
const ATTACK_SPEED_P: float = 0.75

func _ready():
	_default_floor_snap_length = floor_snap_length
	_build_oxygen_bar()
	_life_barrier_visual = Sprite2D.new()
	_life_barrier_visual.texture = _make_ring_texture()
	_life_barrier_visual.position = Vector2(0, -4)
	_life_barrier_visual.modulate = Color(0.4, 0.8, 1.0, 0.85)
	_life_barrier_visual.z_index = 3
	_life_barrier_visual.visible = false
	add_child(_life_barrier_visual)
	_blood_fury_visual = Sprite2D.new()
	_blood_fury_visual.texture = _make_barrier_circle_texture()
	_blood_fury_visual.position = Vector2(0, -4)
	_blood_fury_visual.scale = Vector2(0.85, 1.3)
	_blood_fury_visual.modulate = Color(0.65, 0.15, 0.9, 0.5)
	_blood_fury_visual.z_index = 3
	_blood_fury_visual.visible = false
	add_child(_blood_fury_visual)
	_sprite = get_node_or_null("AnimatedSprite2D")
	if _sprite:
		_sprite.z_index = 2
		_sprite_base_x = _sprite.position.x
		_sprite_effects_material = ShaderMaterial.new()
		_sprite_effects_material.shader = preload("res://elana_sprite_effects.gdshader")
		_sprite.material = _sprite_effects_material
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	$Camera.position_smoothing_enabled = false
	$Camera.drag_vertical_enabled = true
	$Camera.drag_top_margin = 0.2
	$Camera.drag_bottom_margin = 0.2
	# Captured so _update_camera_lock() can restore them exactly once a boss
	# fight's bounds are no longer active, rather than hardcoding Godot's
	# "effectively unlimited" sentinel values.
	_default_camera_limit_left = $Camera.limit_left
	_default_camera_limit_top = $Camera.limit_top
	_default_camera_limit_right = $Camera.limit_right
	_default_camera_limit_bottom = $Camera.limit_bottom
	if GameData.use_default_spawn:
		GameData.use_default_spawn = false
		var spawn = get_tree().current_scene.get_node_or_null(GameData.default_spawn_id)
		if spawn:
			position = spawn.global_position
		else:
			position = spawn_point
	elif GameData.just_died:
		GameData.just_died = false
		position = GameData.respawn_position
	else:
		var spawn = get_tree().current_scene.get_node_or_null(GameData.spawn_point_id)
		if spawn:
			position = spawn.global_position
		else:
			position = spawn_point
	if GameData.pending_intro:
		GameData.pending_intro = false
		call_deferred("_start_intro_cutscene")

const OXYGEN_DRAIN_RATE: float = 12.0
const OXYGEN_REGEN_RATE: float = 30.0
const OXYGEN_DAMAGE_TICK: int = 3
const OXYGEN_DAMAGE_INTERVAL: float = 1.0
const OXYGEN_BAR_WIDTH: float = 30.0
const OXYGEN_BAR_HEIGHT: float = 4.0
var _oxygen_bar_root: Node2D
var _oxygen_bar_fill: ColorRect
var _oxygen_damage_timer: float = 0.0

# Same ColorRect Background+Fill bar pattern enemy HPBars already use,
# built the same "construct it in code" way as the other buff visuals above
# — just floating above Elana's head instead of over an enemy. Hidden by
# default; only shown while actually relevant (see _tick_oxygen()).
func _build_oxygen_bar() -> void:
	_oxygen_bar_root = Node2D.new()
	_oxygen_bar_root.position = Vector2(-15, -30)
	_oxygen_bar_root.z_index = 5
	_oxygen_bar_root.visible = false
	var bg = ColorRect.new()
	bg.size = Vector2(OXYGEN_BAR_WIDTH, OXYGEN_BAR_HEIGHT)
	bg.color = Color(0.1, 0.15, 0.2, 0.85)
	_oxygen_bar_root.add_child(bg)
	var fill = ColorRect.new()
	fill.size = Vector2(OXYGEN_BAR_WIDTH, OXYGEN_BAR_HEIGHT)
	fill.color = Color(0.35, 0.75, 1.0, 1.0)
	_oxygen_bar_root.add_child(fill)
	_oxygen_bar_fill = fill
	add_child(_oxygen_bar_root)

# Drains only while genuinely submerged (in water, not at the surface —
# treading at the surface still lets her breathe); regenerates otherwise.
# Deals periodic damage once fully depleted, same drowning-DOT shape as
# apply_player_burn/apply_player_poison.
func _tick_oxygen(delta: float) -> void:
	var submerged = _in_water and not _at_water_surface
	if submerged:
		GameData.oxygen = max(0.0, GameData.oxygen - OXYGEN_DRAIN_RATE * delta)
	else:
		GameData.oxygen = min(GameData.max_oxygen, GameData.oxygen + OXYGEN_REGEN_RATE * delta)
	_oxygen_bar_root.visible = submerged or GameData.oxygen < GameData.max_oxygen
	_oxygen_bar_fill.size.x = OXYGEN_BAR_WIDTH * (GameData.oxygen / GameData.max_oxygen)
	if GameData.oxygen <= 0.0:
		_oxygen_damage_timer -= delta
		if _oxygen_damage_timer <= 0.0:
			_oxygen_damage_timer = OXYGEN_DAMAGE_INTERVAL
			take_damage(OXYGEN_DAMAGE_TICK, false, null)
	else:
		_oxygen_damage_timer = 0.0

func _start_intro_cutscene() -> void:
	GameData.in_cutscene = true
	facing = 1
	GameData.glint_position_locked = true
	GameData.glint_lock_follows_facing = true
	HUD.show_skip_button()

	HUD.show_dialogue(DialogueData.INTRO_PART1, false)
	await HUD.dialogue_finished
	if HUD.skip_requested:
		_finish_intro_cutscene()
		return

	# Scripted walk left for 1.5s — Glint (still dynamically locked) follows
	# the facing change and ends up on Elana's right, behind her.
	facing = -1
	GameData.cutscene_scripted_move = true
	var walk_time = 1.5
	while walk_time > 0.0 and not HUD.skip_requested:
		velocity.x = -MOVE_SPEED
		walk_time -= get_physics_process_delta_time()
		await get_tree().physics_frame
	velocity.x = 0.0
	GameData.cutscene_scripted_move = false
	if HUD.skip_requested:
		_finish_intro_cutscene()
		return

	HUD.show_dialogue(DialogueData.INTRO_PART2, false)
	await HUD.dialogue_finished
	if HUD.skip_requested:
		_finish_intro_cutscene()
		return

	# Looks back — turns to face right. Glint's lock switches to frozen, so
	# she doesn't slide along with the turn; the turn reveals her instead,
	# face to face. Held through the whole reaction dialogue below, not just
	# a brief pause on the turn, so the face-to-face pose is actually visible
	# while she's reading it — only releases once Elana turns to walk on.
	GameData.glint_lock_follows_facing = false
	facing = 1
	await get_tree().create_timer(0.3).timeout

	HUD.show_dialogue(DialogueData.INTRO_PART3A, false)
	await HUD.dialogue_finished
	if HUD.skip_requested:
		_finish_intro_cutscene()
		return

	HUD.show_dialogue(DialogueData.INTRO_PART3B, false, {"Glint": get_node("Glint")})
	await HUD.dialogue_finished

	_finish_intro_cutscene()

# Single end-state applier — reached either by playing every beat above to
# its natural end, or by the skip button cutting in partway through.
func _finish_intro_cutscene() -> void:
	HUD.hide_skip_button()
	velocity.x = 0.0
	GameData.cutscene_scripted_move = false
	facing = 1
	GameData.glint_lock_follows_facing = false
	GameData.glint_position_locked = false
	GameData.in_cutscene = false

func take_damage(amount = 10, is_elemental: bool = false, attacker: Node = null, element: String = ""):
	if _is_dead or is_dodging:
		return
	if GameData.dodge_chance > 0.0 and randf() < GameData.dodge_chance:
		GameData.spawn_float_text("DODGE", global_position, Color(0.7, 0.85, 1.0))
		return
	# Manual block — costs Glint HP same as landing a hit, whether or not the
	# weapon's actually been swung. No weapon (fist) or no HP left = no block.
	if is_blocking and GameData.current_weapon != "fist" and GameData.glint_hp > 0.0:
		GameData.glint_take_hit(GameData.get_weapon_hit_cost(false))
		GameData.check_weapon_depletion()
		GameData.spawn_float_text("BLOCKED", global_position, Color(0.55, 0.8, 1.0))
		return
	if GameData.hollowscale_unlocked and GameData.hollowscale_cooldown <= 0.0:
		GameData.hollowscale_cooldown = GameData.HOLLOWSCALE_RECHARGE
		GameData.spawn_float_text("BLOCKED", global_position, Color(0.85, 0.75, 0.35))
		return
	_iron_body_timer = 0.0
	_idle_timer = 0.0
	_idle_normal_active = false
	var reduced_amount = float(amount) * (1.0 - GameData.damage_reduction_skill)
	if is_elemental:
		var resist = GameData.get_elemental_resist_for(element) if element != "" else GameData.elemental_resist
		if resist > 0.0:
			reduced_amount *= (1.0 - resist)
	# Ant Queen's death reward — halves damage from anything tagged
	# "hazards" (spikes, vine thorns, Hollowfang's falling rocks, future
	# floor spikes), stacking multiplicatively with the elemental-resist
	# reduction above like every other reduction here does.
	if GameData.ant_queen_defeated and attacker != null and attacker.is_in_group("hazards"):
		reduced_amount *= (1.0 - GameData.HAZARD_DAMAGE_REDUCTION)
	var final_damage = GameData.calc_damage(reduced_amount, float(GameData.get_defense()))
	# Bulwark — reflect to actual attacking enemies only. Environmental hazards
	# (vine gates, spikes, magma tiles, ice geysers/walls) deal contact damage
	# too but aren't attackers, so they're excluded via the "enemies" group.
	if GameData.bulwark_pct > 0.0 and attacker != null and attacker.is_in_group("enemies"):
		var reflect_dmg: int = max(1, int(float(final_damage) * GameData.bulwark_pct))
		attacker.on_hit(-attacker.direction, reflect_dmg, true, self)
	# Life Barrier — 90% flat damage reduction while held (right-click + Heal
	# Herb), not an absorb pool, so it never depletes on its own.
	if _life_barrier_active:
		final_damage = max(1, int(ceil(float(final_damage) * 0.10)))
	# Passive shield (iron_body + overheal) absorbs next
	if GameData.passive_shield_hp > 0.0:
		var absorbed = min(GameData.passive_shield_hp, float(final_damage))
		var component_total = _overheal_shield_hp + _iron_body_shield_hp
		var component_drain = component_total - max(0.0, GameData.passive_shield_hp - absorbed)
		if component_total > 0.0:
			_iron_body_shield_hp = max(0.0, _iron_body_shield_hp - component_drain * (_iron_body_shield_hp / component_total))
			_overheal_shield_hp = max(0.0, _overheal_shield_hp - component_drain * (_overheal_shield_hp / component_total))
		GameData.passive_shield_hp = min(float(GameData.max_hp), _overheal_shield_hp + _iron_body_shield_hp)
		var remaining = final_damage - int(absorbed)
		GameData.spawn_damage_number(int(absorbed), global_position, Color(0.9, 0.85, 0.2))
		if remaining <= 0:
			return
		final_damage = remaining
	GameData.hp -= final_damage
	GameData.spawn_damage_number(final_damage, global_position, Color.RED)
	# Only "big" hits shake — chip damage stays quiet. Scales with how much
	# of her max HP it took, so a near-lethal hit shakes harder than one
	# that's merely above the threshold.
	if float(final_damage) >= float(GameData.max_hp) * 0.08:
		add_camera_trauma(clamp(float(final_damage) / float(GameData.max_hp), 0.3, 0.8))
	GameData.hitstop()
	# Last Stand — trigger at ≤30% HP if off cooldown
	if GameData.last_stand_heal_pct > 0.0 and GameData.last_stand_cd <= 0.0 and GameData.hp > 0 and GameData.hp <= GameData.max_hp * 0.30:
		var heal = int(GameData.max_hp * GameData.last_stand_heal_pct)
		GameData.hp = min(GameData.max_hp, GameData.hp + heal)
		GameData.last_stand_cd = 300.0
		GameData.spawn_damage_number(heal, global_position, Color(0.2, 1.0, 0.4))
	if GameData.hp <= 0:
		die()
		return
	if _sprite_effects_material != null:
		_sprite_effects_material.set_shader_parameter("flash_amount", 1.0)
	await get_tree().create_timer(0.3).timeout
	if _sprite_effects_material != null:
		_sprite_effects_material.set_shader_parameter("flash_amount", 0.0)
	if not _blood_fury_active and not _life_barrier_active:
		_update_status_tint()

func die():
	if _is_dead:
		return
	_is_dead = true
	Engine.time_scale = 1.0
	GameData.reset_boss_camera()
	# Freezes her (movement/input) for the wait — die() already clears this
	# as part of its normal cleanup right after, so nothing extra to reset.
	GameData.in_cutscene = true
	await HUD.show_death_screen()
	GameData.clear_combat_stacks()
	GameData.glint_scouting = false
	GameData.glint_scout_returning = false
	GameData.in_cutscene = false
	GameData.cutscene_scripted_move = false
	GameData.glint_position_locked = false
	HUD.hide_prompt()
	# Don't reveal the HUD on a mid-prologue death — she hasn't received the
	# Stone Being's power yet, so it should stay hidden through the respawn.
	if GameData.received_stone_being_power:
		HUD.set_hud_visible(true)
	is_stunned = false
	is_frozen = false
	is_shocked = false
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	burn_ticks_remaining = 0
	GameData.hollowscale_cooldown = 0.0
	GameData.danger_sense_cooldown = 0.0
	_update_status_tint()
	# Death now rolls everything back to the last Ritual Node save (XP,
	# inventory, room_state/kills, HP as it was at that save — not forced
	# to full) instead of just relocating with whatever live state she had
	# when she died. Same load path title_screen.gd's Continue uses.
	if GameData.load_game():
		HUD.refresh_slots()
		HUD.set_hud_visible(GameData.received_stone_being_power)
		var target_scene = GameData.default_scene
		if GameData.respawn_scene != "":
			target_scene = GameData.respawn_scene
			# reset() (called inside load_game()) leaves use_default_spawn
			# true — clear it so the next scene's spawn check falls through
			# to just_died instead, landing her at respawn_position.
			GameData.use_default_spawn = false
			GameData.just_died = true
		else:
			GameData.use_default_spawn = true
		# Routed through loading_screen.tscn instead of a direct
		# change_scene_to_file() — same reason title_screen.gd's Continue/New
		# Game do: that call is synchronous and blocks on the full_map.tscn
		# load+instantiate with zero feedback, the loading screen threads it.
		GameData.pending_scene_load = target_scene
		get_tree().change_scene_to_file.call_deferred("res://loading_screen.tscn")
	else:
		# No save yet (died before ever reaching a Ritual Node) — nothing to
		# roll back to, so fall back to the original live-state respawn.
		# (HUD visibility already handled by the check earlier in this function.)
		GameData.hp = GameData.max_hp
		if GameData.respawn_scene != "":
			GameData.just_died = true
			get_tree().change_scene_to_file.call_deferred(GameData.respawn_scene)
		else:
			GameData.use_default_spawn = true
			get_tree().change_scene_to_file.call_deferred(GameData.default_scene)

# Public interface for observers (Glint) — avoids them re-deriving attack state
func is_swinging() -> bool:
	return is_attacking or is_plunge_attacking

# ── Player status effects — mirrors base_enemy.gd's pattern ─────────────────
# Freeze is Stun with extras (velocity zeroed, tint, longer duration), same
# shared-flag relationship enemies already use. Dodge i-frames block all of
# these, same rule as incoming damage.

func apply_stun(duration: float) -> void:
	if is_dodging:
		return
	is_stunned = true
	stun_timer = max(stun_timer, duration)

# Not merged with apply_stun's min/max pattern — a fresh knockback should
# always take over cleanly (e.g. Charger's dash), not blend with whatever
# velocity/timer was already active.
func apply_knockback(vec: Vector2, duration: float = 0.3, ignore_gravity: bool = false) -> void:
	if is_dodging:
		return
	# Rejected here, not just cleaned up after the fact — every knockback
	# source in the game (hazards, boss attacks, drags) funnels through this
	# one function, so validating the vector right at the point it's about
	# to become real velocity stops a bad caller (e.g. a knockback direction
	# computed via .normalized() on a near-zero vector, or a degenerate
	# collision producing NaN/Inf) from ever reaching global_position at
	# all, instead of only detecting the damage afterward.
	if not (is_finite(vec.x) and is_finite(vec.y)):
		return
	# Set velocity directly, once, here — not every frame in _physics_process
	# — so gravity (added there each frame below) actually accumulates onto
	# it into a real parabola instead of being reset to the same constant
	# base every tick. ignore_gravity opts out of that entirely — for a
	# precise drag toward an exact target (apply_drag_stun()) rather than a
	# toss, any accumulated gravity corrupts the constant velocity the caller
	# deliberately computed to land exactly on target, cutting it short.
	velocity = vec
	_knockback_timer = duration
	_knockback_ignores_gravity = ignore_gravity

# Physically drags Elana toward target over drag_duration — reuses the same
# _knockback_timer-driven movement path apply_knockback() does, so
# move_and_slide()'s own wall-collision handling applies naturally (unlike a
# raw position tween, which has no collision awareness at all and would
# drag her straight through terrain). If she ends up pressed against a wall
# once the drag finishes, she's pinned fully in place (apply_freeze — no
# gravity, no sliding) for whatever's left of total_stun_duration instead of
# just falling through a normal stun — used by Hollowfang's Eject Spikes so
# getting dragged into a wall reads as an actual pin, not a stopped shove.
func apply_drag_stun(target: Vector2, drag_duration: float, total_stun_duration: float) -> void:
	if is_dodging:
		return
	is_stunned = true
	stun_timer = max(stun_timer, total_stun_duration)
	var drag_vec: Vector2 = (target - global_position) / drag_duration
	apply_knockback(drag_vec, drag_duration, true)
	await get_tree().create_timer(drag_duration).timeout
	if not is_instance_valid(self):
		return
	if is_on_wall():
		apply_freeze(max(0.0, total_stun_duration - drag_duration))

func apply_freeze(duration: float) -> void:
	if is_dodging:
		return
	is_stunned = true
	is_frozen = true
	stun_timer = max(stun_timer, duration)
	velocity = Vector2.ZERO
	_update_status_tint()

# Functionally identical to apply_stun() (is_stunned blocks direction/jump/
# attack the same way, which naturally hard-stops horizontal movement too —
# nothing needs to zero velocity.x separately) — is_shocked exists as its
# own tracked flag purely so this reads as a distinct status from a plain
# stun, and so it can be told apart from apply_freeze() specifically:
# freeze also zeros velocity outright (both axes), stopping a fall dead in
# midair, while shock leaves vertical velocity alone entirely — gravity
# keeps pulling her down mid-fall same as if nothing happened, only
# horizontal control is cut.
func apply_shock(duration: float) -> void:
	if is_dodging:
		return
	if _is_immune_to_status_element("elec"):
		return
	is_stunned = true
	is_shocked = true
	stun_timer = max(stun_timer, duration)

# Matching herb grants full immunity to its element's specific status effect
# (burn/frost-slow/shock) — damage itself is untouched by this, still
# reduced the same way it always was via GameData.get_elemental_resist_for()
# inside take_damage(); this only ever blocks the non-damage side effect.
# apply_slow() also carries plenty of non-frost callers (Danger Sense,
# Pollen Puffer, generic slow hazards) — those pass no element at all and
# are never affected by this.
func _is_immune_to_status_element(element: String) -> bool:
	if GameData.active_herb == null:
		return false
	match element:
		"fire":
			return GameData.active_herb.item_id == "herbElementalFire"
		"frost":
			return GameData.active_herb.item_id == "herbElementalFrost"
		"elec":
			return GameData.active_herb.item_id == "herbElementalElec"
	return false

# source: whatever's holding her (Ceiling Grabber, etc.) — her position gets
# pinned to source.global_position + offset every physics frame until
# release_trap() is called. Also sets is_stunned (blocks jump/dodge/normal
# movement input the same as any other stun) but attacking is untouched —
# escaping a trap by fighting back is the whole point, unlike a plain stun.
func apply_trap(source: Node, offset: Vector2 = Vector2.ZERO) -> void:
	if is_dodging:
		return
	is_stunned = true
	is_trapped = true
	_trap_anchor = source
	_trap_offset = offset

# Explicit release, not a timer — how long a trap lasts is entirely up to
# whatever's holding her (breaking free, or it dying), not a fixed duration
# like stun/freeze/shock.
func release_trap() -> void:
	is_trapped = false
	is_stunned = false
	_trap_anchor = null

func apply_slow(factor: float, duration: float, element: String = "") -> void:
	if is_dodging:
		return
	# element is only ever passed by genuinely frost-sourced callers (Frost
	# Beam, Ice Wisp, Ice Plant Spitter's frost_bolt, ice_trail_patch) — the
	# many non-elemental callers (Danger Sense, Pollen Puffer, generic slow
	# hazards) pass nothing, so they're never touched by frost immunity.
	if element != "" and _is_immune_to_status_element(element):
		return
	slow_factor = min(slow_factor, factor)
	slow_timer = max(slow_timer, duration)
	_update_status_tint()

# Same min-factor/max-duration merge as apply_slow — makes jumps weaker
# (multiplied into JUMP_VELOCITY alongside GameData.jump_mult at every jump
# site) instead of just horizontal movement, so a heavy-feeling effect like
# Pollen Puffer's cloud can drag down mobility in both axes.
func apply_jump_weight(factor: float, duration: float) -> void:
	if is_dodging:
		return
	jump_weight_factor = min(jump_weight_factor, factor)
	jump_weight_timer = max(jump_weight_timer, duration)

func apply_player_burn(damage_per_tick: int, ticks: int = 5) -> void:
	if is_dodging:
		return
	# Standing in water douses it before it ever catches — same "wet =
	# fireproof" logic Frost Beam's water-freeze interaction already relies
	# on WaterCheck for elsewhere.
	if _in_water:
		return
	if _is_immune_to_status_element("fire"):
		return
	burn_damage = max(burn_damage, damage_per_tick)
	burn_ticks_remaining = max(burn_ticks_remaining, ticks)
	# Only (re)start the tick countdown on a fresh application (nothing
	# already burning) — a source that reapplies every frame (e.g. an aura)
	# would otherwise reset this to 1.0 every single frame, and the
	# countdown could never actually reach 0 to deal damage.
	if burn_tick_timer <= 0.0:
		burn_tick_timer = 1.0

# Separate DOT track from burn (not merged) so an area effect like Pollen
# Puffer's cloud can reapply it every frame with a short tick count — it
# naturally decays out within ~1s of leaving the cloud instead of needing
# explicit removal code, same trick apply_slow already relies on.
func apply_player_poison(damage_per_tick: int, ticks: int = 5) -> void:
	if is_dodging:
		return
	poison_damage = max(poison_damage, damage_per_tick)
	poison_ticks_remaining = max(poison_ticks_remaining, ticks)
	# Same guard as apply_player_burn — only (re)start the countdown on a
	# fresh application, not every frame a continuously-reapplying source
	# (Pollen Puffer's cloud) calls this.
	if poison_tick_timer <= 0.0:
		poison_tick_timer = 1.0

func _update_status_tint() -> void:
	var color = Color.WHITE
	if _story_glow_active:
		color = Color(1.4, 1.2, 0.5)
	elif is_frozen:
		color = Color(0.4, 0.75, 1.0)
	elif slow_timer > 0.0:
		color = Color(0.75, 0.88, 1.0)
	elif GameData.passive_shield_hp > 0.0:
		color = Color(0.82, 0.82, 0.88)
	if _sprite:
		_sprite.modulate = color

# Public — cutscenes (e.g. the Stone Being's power grant) trigger a gold glow
# on Elana's sprite that persists until explicitly stopped (e.g. right before
# a flash-of-light beat), without fighting the per-frame status tint.
func trigger_story_glow() -> void:
	_story_glow_active = true
	_story_glow_elapsed = 0.0

func stop_story_glow() -> void:
	_story_glow_active = false
	_update_status_tint()
	if _sprite_effects_material != null:
		_sprite_effects_material.set_shader_parameter("glow_outline_alpha", 0.0)

func _tick_status_effects(delta: float) -> void:
	_update_status_tint()
	if _story_glow_active:
		_story_glow_elapsed += delta
		if _sprite_effects_material != null:
			var pulse = 0.5 + 0.5 * sin(_story_glow_elapsed * STORY_GLOW_PULSE_SPEED)
			_sprite_effects_material.set_shader_parameter("glow_outline_alpha", pulse)
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
			is_frozen = false
			is_shocked = false
			_update_status_tint()
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			_update_status_tint()
	if jump_weight_timer > 0.0:
		jump_weight_timer -= delta
		if jump_weight_timer <= 0.0:
			jump_weight_factor = 1.0
	if burn_ticks_remaining > 0:
		burn_tick_timer -= delta
		if burn_tick_timer <= 0.0:
			burn_tick_timer = 1.0
			burn_ticks_remaining -= 1
			GameData.hp -= burn_damage
			GameData.spawn_float_text(str(burn_damage), global_position, Color(1.0, 0.45, 0.05))
			if _sprite:
				_sprite.modulate = Color(1.5, 0.5, 0.3)
				await get_tree().create_timer(0.15).timeout
				if is_instance_valid(self):
					_update_status_tint()
			if GameData.hp <= 0:
				burn_ticks_remaining = 0
				die()
	if poison_ticks_remaining > 0:
		poison_tick_timer -= delta
		if poison_tick_timer <= 0.0:
			poison_tick_timer = 1.0
			poison_ticks_remaining -= 1
			GameData.hp -= poison_damage
			GameData.spawn_float_text(str(poison_damage), global_position, Color(0.6, 0.9, 0.3))
			if _sprite:
				_sprite.modulate = Color(0.6, 1.2, 0.4)
				await get_tree().create_timer(0.15).timeout
				if is_instance_valid(self):
					_update_status_tint()
			if GameData.hp <= 0:
				poison_ticks_remaining = 0
				die()
	# Blood Fury's ×2 damage isn't free — it burns her own HP while active
	if _blood_fury_active:
		GameData.hp -= GameData.max_hp * 0.015 * delta
		if GameData.hp <= 0:
			die()

func _on_hitbox_area_entered(area):
	if area.name == "Hurtbox" and (is_attacking or is_plunge_attacking):
		var enemy = area.get_parent()
		if enemy in _hit_this_swing:
			return
		_hit_this_swing.append(enemy)
		var dmg = _melee_base_damage()
		if is_heavy_attack:
			dmg = int(dmg * GameData.weapon_heavy_multiplier)
		if is_plunge_attacking:
			dmg = int(dmg * PLUNGE_DESCENT_MULT)
		if GameData.berserker_mult > 0.0 and GameData.hp <= GameData.max_hp * 0.40:
			dmg = int(float(dmg) * (1.0 + GameData.berserker_mult))
		dmg = _apply_glint_weapon_bonuses(dmg, enemy)
		enemy.on_hit(facing, dmg, false, self)
		if is_heavy_attack and GameData.current_weapon == "warhammer":
			add_camera_trauma(0.5)
		GameData.glint_register_hit()
		GameData.glint_take_hit(GameData.get_weapon_hit_cost(is_heavy_attack))
		var has_weapon = GameData.current_weapon != "fist"
		var herb_id = GameData.active_herb.item_id if GameData.active_herb != null else ""
		var total_lifesteal = GameData.lifesteal
		if has_weapon and herb_id == "herbPower":
			total_lifesteal += GameData.glint_herb_lifesteal
		if total_lifesteal > 0.0:
			GameData.hp = min(GameData.max_hp, GameData.hp + int(float(dmg) * total_lifesteal))
		if has_weapon and herb_id == "herbElementalFire" and GameData.glint_burn_bonus > 0.0 and enemy.has_method("apply_burn"):
			var tick_dmg = max(1, int(float(dmg) * (GameData.GLINT_BURN_BASE + GameData.glint_burn_bonus)))
			enemy.apply_burn(tick_dmg, GameData.GLINT_BURN_TICKS)
		if has_weapon and herb_id == "herbElementalFrost" and GameData.glint_slow_pct > 0.0 and enemy.has_method("apply_slow"):
			enemy.apply_slow(1.0 - GameData.glint_slow_pct, GameData.GLINT_SLOW_DURATION)
		if has_weapon and herb_id == "herbHeal" and GameData.glint_toxic_bonus > 0.0 and enemy.has_method("apply_poison"):
			var poison_tick = max(1, int(float(dmg) * (GameData.GLINT_POISON_BASE + GameData.glint_toxic_bonus)))
			enemy.apply_poison(poison_tick, GameData.GLINT_POISON_TICKS)
		if has_weapon and herb_id == "herbAgility" and GameData.glint_phantom_pct > 0.0 and randf() < GameData.glint_phantom_pct:
			_phantom_strike(enemy, dmg)
		if has_weapon and herb_id == "herbElementalElec" and GameData.get_glint_skill_level("g_chain") > 0:
			_glint_chain_arc(enemy)
		if is_heavy_attack and enemy.is_in_group("enemies"):
			_apply_heavy_knockback(enemy)

# Agility Herb Phantom Strike: a ghost echo repeats the hit at half damage,
# rolling its own crit
func _phantom_strike(enemy: Node, base_dmg: int) -> void:
	await get_tree().create_timer(0.15).timeout
	if not is_instance_valid(enemy):
		return
	var dmg = max(1, int(float(base_dmg) * GameData.GLINT_PHANTOM_DMG))
	GameData.last_hit_is_crit = randf() < GameData.glint_crit_chance
	if GameData.last_hit_is_crit:
		dmg = int(float(dmg) * GameData.glint_crit_dmg_mult)
	enemy.on_hit(facing, dmg, false, self)

# Elec Herb Chain: melee hits arc to nearby enemies. Arc count = node level,
# damage is magic-based (weapon-independent) with the chain-lightning falloff.
func _glint_chain_arc(source: Node) -> void:
	var arcs: int = GameData.get_glint_skill_level("g_chain")
	var arc_dmg: int = max(1, int(float(GameData.get_magic_damage()) * GameData.GLINT_CHAIN_DMG))
	var prev: Node = source
	for _i in arcs:
		var next: Node = _find_chain_target(prev)
		if next == null:
			break
		var chain_dir: int = 1 if next.global_position.x >= prev.global_position.x else -1
		next.on_elemental_hit("elec", chain_dir, arc_dmg, self)
		_draw_elec_bolt(_enemy_center(prev), _enemy_center(next))
		prev = next

# Single source for the melee damage formula — light/heavy/plunge/shockwave
# all derive from this with their own multiplier.
func _melee_base_damage(mult: float = 1.0) -> int:
	return int(float(GameData.get_attack_damage()) * GameData.get_weapon_power() * GameData.damage_multiplier * mult)

func _apply_glint_weapon_bonuses(dmg: int, enemy: Node) -> int:
	if GameData.current_weapon == "fist":
		# Every weapon bonus below (incl. the crit roll) is skipped for fist,
		# so explicitly clear rather than leaving whatever the last weapon
		# swing's roll happened to be — otherwise a fist hit right after a
		# crit could still render its damage number yellow.
		GameData.last_hit_is_crit = false
		return dmg
	if GameData.glint_weapon_dmg_bonus > 0.0:
		dmg = int(float(dmg) * (1.0 + GameData.glint_weapon_dmg_bonus))
	if GameData.glint_overcharge_stacks > 0:
		dmg = int(float(dmg) * (1.0 + 0.10 * GameData.glint_overcharge_stacks))
	if GameData.glint_combo_stacks > 0:
		dmg = int(float(dmg) * (1.0 + 0.04 * GameData.glint_combo_stacks))
	if GameData.glint_exec_stacks > 0:
		var per_stack = 0.05 * GameData.get_glint_skill_level("g_executioner")
		dmg = int(float(dmg) * (1.0 + per_stack * GameData.glint_exec_stacks))
	# Set explicitly either way (not just on a crit) so a later non-crit swing
	# can't inherit a stale true left over from an earlier crit — hit_handler.gd
	# reads this the instant it spawns the damage number below.
	GameData.last_hit_is_crit = randf() < GameData.glint_crit_chance
	if GameData.last_hit_is_crit:
		dmg = int(float(dmg) * GameData.glint_crit_dmg_mult)
	if randf() < GameData.glint_armor_ignore_chance:
		# pre-compensate so the enemy's defense reduction cancels out exactly
		var enemy_defense = enemy.get("defense")
		if enemy_defense != null:
			dmg = int(float(dmg) * (float(enemy_defense) + 100.0) / 100.0)
	return dmg

func _physics_process(delta):
	# Safety net — a NaN global_position (e.g. from a degenerate collision
	# shape producing NaN velocity in move_and_slide()) never self-corrects
	# on its own; every frame after just stays NaN forever, which renders as
	# a totally blank screen (Camera2D tracking a NaN position shows
	# nothing, while UI on its own CanvasLayer keeps working — exactly the
	# reported symptom). Recovers to the last known-good position instead
	# of leaving the run permanently broken, whatever actually caused it.
	if is_nan(global_position.x) or is_nan(global_position.y):
		_recover_from_nan()
	else:
		_last_valid_position = global_position
		# Only clears the streak once she's actually moved clear of where she
		# last got corrupted — a single frame reading "valid" right at the
		# same spot isn't real recovery, it's the oscillation itself
		# (confirmed: reported streak resetting to 1 every time even while
		# repeatedly recovering to the exact same coordinates).
		if _last_recovery_position == Vector2.INF or global_position.distance_to(_last_recovery_position) > NAN_RECOVERY_SAFE_DISTANCE:
			_nan_recovery_streak = 0
	# Computed first thing, before the dodge/air-dash checks further down —
	# those need this fresh, not last frame's value. Surface = on a water
	# tile but the tile directly above (one grid step, 16px) isn't water —
	# i.e. she's at the top edge, not submerged.
	_in_water = WaterCheck.is_water(global_position, get_tree())
	_at_water_surface = _in_water and not WaterCheck.is_water(global_position + Vector2(0, -16), get_tree())
	# One-time splash dampening right on entry — the gradual move_toward()
	# in the swim block below still needs a beat to bleed off a big fall
	# velocity, which read as plunging straight to the bottom before this.
	if _in_water and not _was_in_water:
		velocity.y *= WATER_ENTRY_DAMPING
	_was_in_water = _in_water
	_tick_oxygen(delta)
	# move_and_slide()'s own floor-snapping otherwise re-zeroes the swim
	# velocity set further down the instant she touches any real solid
	# collision underwater (e.g. a seabed) — this is what "sticking to the
	# water floor like it's ground" actually was. Disabling snap while in
	# water stops that; a genuine touch still collides/stops her, it just
	# doesn't get resolved as "standing on ground".
	floor_snap_length = 0.0 if _in_water else _default_floor_snap_length
	# Cleared by touching floor or a wall again, not on a timer, so the escape
	# velocity from a wall jump survives the flight to the opposite wall
	# (zig-zagging a gap) regardless of how long she's held a direction —
	# cleared by touching floor/wall again, or after WALL_JUMP_LOCK_DURATION
	# if she never touches anything, so open air always gives input back.
	if is_on_floor() or is_on_wall():
		_wall_jump_input_locked = false
	if _wall_jump_input_locked:
		_wall_jump_lock_timer -= delta
		if _wall_jump_lock_timer <= 0.0:
			_wall_jump_input_locked = false
	_auto_stick_timer = max(0.0, _auto_stick_timer - delta)
	dodge_cooldown = max(0.0, dodge_cooldown - delta)
	if GameData.hollowscale_cooldown > 0.0:
		GameData.hollowscale_cooldown = max(0.0, GameData.hollowscale_cooldown - delta)
	if GameData.danger_sense_cooldown > 0.0:
		GameData.danger_sense_cooldown = max(0.0, GameData.danger_sense_cooldown - delta)
	if GameData.danger_sense_active_timer > 0.0:
		GameData.danger_sense_active_timer = max(0.0, GameData.danger_sense_active_timer - delta)
	if GameData.danger_sense_unlocked and Input.is_action_just_pressed("danger_sense"):
		_trigger_danger_sense()
	elemental_cooldown_timer = max(0.0, elemental_cooldown_timer - delta)
	jump_buffer_timer = max(0.0, jump_buffer_timer - delta)
	if GameData.dev_no_cooldowns:
		dodge_cooldown = 0.0
		GameData.hollowscale_cooldown = 0.0
		GameData.danger_sense_cooldown = 0.0
		elemental_cooldown_timer = 0.0

	if is_on_floor():
		can_double_jump = false
		can_air_dash = true
		_auto_stick_timer = 0.0

	# Frozen — fully locked, matches enemy is_frozen (zeroed velocity, no input)
	if is_frozen:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Externally-applied knockback (e.g. Charger's dash) — a dedicated
	# early-return block, same shape as dodge/air-dash below. A naive
	# `velocity = knockback` write from outside this function would just
	# get overwritten the same frame by the normal horizontal-movement line
	# further down (it sets velocity.x = direction * speed unconditionally
	# whenever not wall-locked/sliding, regardless of is_stunned), so
	# knockback needs its own state that fully bypasses that, same reason
	# enemies consume _pending_knockback specially instead of just writing
	# to velocity directly.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		if not _knockback_ignores_gravity:
			velocity.y += gravity * delta
		move_and_slide()
		return

	# Glint is off scouting, or a cutscene/dialogue is playing — no input
	# reaches Elana, but she still falls naturally if left mid-air instead
	# of hanging frozen in place. cutscene_scripted_move lets a cutscene
	# drive velocity.x itself (a forced walk) without this zeroing it back.
	if GameData.glint_scouting or GameData.in_cutscene:
		if not GameData.cutscene_scripted_move:
			velocity.x = 0.0
		if _in_water:
			velocity.y = move_toward(velocity.y, SWIM_DRIFT_SPEED, SWIM_ACCEL * delta)
		elif not is_on_floor():
			velocity.y += gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		return

	# Active ground dodge — has i-frames
	if is_dodging:
		dodge_timer -= delta
		velocity.x = DODGE_SPEED * _dash_dir
		velocity.y += gravity * delta
		if dodge_timer <= 0:
			is_dodging = false
			dodge_cooldown = DODGE_COOLDOWN
		move_and_slide()
		return

	# Active air dash — no i-frames, gravity suppressed
	if is_air_dashing:
		air_dash_timer -= delta
		velocity.x = AIR_DASH_SPEED * _dash_dir
		velocity.y = 0.0
		if air_dash_timer <= 0:
			is_air_dashing = false
		move_and_slide()
		return

	# Ground dodge — Shift
	if is_on_floor() and not _in_water and GameData.dodge_enabled and dodge_cooldown <= 0 and Input.is_action_just_pressed("sprint"):
		var key_dir = Input.get_axis("move_left", "move_right")
		_dash_dir = int(sign(key_dir)) if key_dir != 0.0 else facing
		is_dodging = true
		dodge_timer = DODGE_DURATION
		velocity.x = DODGE_SPEED * _dash_dir
		velocity.y += gravity * delta
		move_and_slide()
		return

	# Air dash — Shift (one per airborne, resets on landing)
	if not is_on_floor() and not _in_water and GameData.air_dash_enabled and can_air_dash and Input.is_action_just_pressed("sprint"):
		var key_dir = Input.get_axis("move_left", "move_right")
		_dash_dir = int(sign(key_dir)) if key_dir != 0.0 else facing
		is_air_dashing = true
		can_air_dash = false
		air_dash_timer = AIR_DASH_DURATION
		velocity.x = AIR_DASH_SPEED * _dash_dir
		velocity.y = 0.0
		move_and_slide()
		HUD.hide_prompt("air_dash_tutorial")
		return

	# Spear heavy dash
	if _spear_dash_timer > 0:
		_spear_dash_timer -= delta
		velocity.x = _spear_dash_speed
		if not _suppress_gravity:
			velocity.y += gravity * delta
		if _spear_dash_timer <= 0:
			_spear_dash_speed = 0.0
		move_and_slide()
		return

	# Held by something (e.g. Ceiling Grabber's tongue) — position pinned
	# directly to the source each frame, overriding normal physics entirely.
	# Deliberately does NOT block the attack input path (that's read in
	# _input(), a separate callback this early return never touches) — the
	# whole point is she can still fight back while trapped, unlike a plain
	# stun/freeze which happens to also block movement via the same flag
	# this reuses (is_stunned) but isn't itself an attack-blocking measure.
	if is_trapped:
		velocity = Vector2.ZERO
		if is_instance_valid(_trap_anchor):
			global_position = _trap_anchor.global_position + _trap_offset
		move_and_slide()
		return

	# Chain grapple pull — locked to the direction the chain was thrown, not
	# steered toward the hook point each frame, so it drags her all the way
	# through it instead of braking to a stop the moment she's merely close.
	if _grapple_timer > 0:
		_grapple_timer -= delta
		if _grapple_timer <= 0:
			_grapple_timer = 0.0
			can_double_jump = true
		else:
			velocity = _grapple_direction * GRAPPLE_PULL_SPEED
		move_and_slide()
		return

	# Plunge attack — fixed fast descent. Cancelled (not landed — no AOE
	# burst) the instant it crosses into water, instead of continuing to
	# fall at full PLUNGE_SPEED straight to the bottom; falls through to
	# the rest of _physics_process below, which picks up the swim handling.
	if is_plunge_attacking:
		if _in_water:
			is_plunge_attacking = false
			$Hitbox.monitoring = false
			$Hitbox.position = Vector2(0, 0)
		else:
			var plunge_speed = PLUNGE_SPEED_CHAIN if GameData.current_weapon == "chain_claw" else PLUNGE_SPEED
			velocity.y = plunge_speed
			velocity.x = Input.get_axis("move_left", "move_right") * MOVE_SPEED * 0.3
			move_and_slide()
			if is_on_floor():
				$Hitbox.monitoring = false
				$Hitbox.position = Vector2(0, 0)
				is_plunge_attacking = false
				_on_plunge_land()
			return

	if Input.is_action_just_released("ui_accept") and velocity.y < 0.0:
		velocity.y *= 0.4

	# Swimming — water tiles have no collision at all (removed at the
	# TileSet level, not toggled per-frame), so this is purely a movement-
	# mode switch: no gravity, W/S (move_up/move_down, the same actions
	# Elemander's Pads already reuses for wall-climbing) drive vertical
	# movement directly with a soft accel for a floaty, non-snappy feel.
	# Horizontal movement/attacks/etc. below are untouched — dodge/air-dash
	# are fully disabled while in water, and jump only works at the surface
	# (one jump, no double-jump chaining — see the jump-buffer block below).
	# Without these gates, diving into water left stray ground/air physics
	# fighting the swim controls (dashing used to fall through to air-dash's
	# zero-gravity straight-line burst underwater, for example).
	if _in_water:
		var vertical_input := 0.0
		if Input.is_action_pressed("move_up"):
			vertical_input = -1.0
		elif Input.is_action_pressed("move_down"):
			vertical_input = 1.0
		var target_vy = vertical_input * SWIM_SPEED if vertical_input != 0.0 else SWIM_DRIFT_SPEED
		velocity.y = move_toward(velocity.y, target_vy, SWIM_ACCEL * delta)
	elif not is_on_floor() and not _suppress_gravity:
		velocity.y += gravity * delta

	if GameData.golden_cloak_unlocked and not is_on_floor() and velocity.y > 0.0 and Input.is_action_pressed("ui_accept"):
		velocity.y = min(velocity.y, FLOAT_FALL_SPEED)

	is_blocking = Input.is_action_pressed("block") and not is_stunned and not is_attacking \
			and not is_plunge_attacking and not is_charging and not (GameData.transform_delay_timer > 0.0)

	var direction = 0.0 if (is_stunned or is_blocking or _casting_herb_skill or is_heavy_attack) else Input.get_axis("move_left", "move_right")

	# not _in_water below — otherwise swimming up to any solid wall grants a
	# full-strength wall-jump, bypassing the shorter, terrain-gated surface
	# jump entirely (that elif comes after this block in the jump-buffer
	# chain, so wall-sliding would always win first).
	if GameData.wall_jump_enabled and is_on_wall() and not is_on_floor() and not _has_stair_corner() and not _in_water:
		var wall_normal = get_wall_normal()
		if not is_wall_sliding:
			# Not yet stuck — the auto-stick window (right after a wall jump)
			# sticks outright; otherwise she has to actively hold into the
			# wall while falling, same as before.
			var held_into_wall = direction != 0 and sign(direction) != sign(wall_normal.x)
			if _auto_stick_timer > 0.0 or (held_into_wall and velocity.y > 0):
				is_wall_sliding = true
		else:
			# Already stuck — stays stuck no matter what's held (a stale key
			# from before she grabbed on doesn't auto-release her); only a
			# fresh tap of the away-from-wall direction lets go.
			var away_action = "move_right" if wall_normal.x > 0 else "move_left"
			if Input.is_action_just_pressed(away_action):
				is_wall_sliding = false
		if is_wall_sliding:
			var slide_cap = 0.0 if GameData.elemander_pads_unlocked else WALL_SLIDE_MAX_SPEED
			velocity.y = min(velocity.y, slide_cap)
			# Elemander's Pads — actively climb the wall instead of just clinging
			if GameData.elemander_pads_unlocked:
				if Input.is_action_pressed("move_up"):
					velocity.y = -WALL_CLIMB_SPEED
				elif Input.is_action_pressed("move_down"):
					velocity.y = WALL_CLIMB_SPEED
	else:
		is_wall_sliding = false

	if jump_buffer_timer > 0.0 and not is_stunned:
		if is_on_floor() and not is_dodging and not _in_water:
			velocity.y = JUMP_VELOCITY * GameData.jump_mult * jump_weight_factor
			can_double_jump = true
			jump_buffer_timer = 0.0
		elif is_wall_sliding:
			velocity.y = JUMP_VELOCITY * GameData.jump_mult * jump_weight_factor
			if not _has_stair_corner():
				velocity.x = get_wall_normal().x * WALL_JUMP_PUSH
				facing = int(sign(get_wall_normal().x))
				_wall_jump_input_locked = true
				_wall_jump_lock_timer = WALL_JUMP_LOCK_DURATION
			_auto_stick_timer = AUTO_STICK_DURATION
			jump_buffer_timer = 0.0
		elif _at_water_surface and _near_solid_terrain():
			# One jump, no double-jump chaining on top of it — this doesn't
			# set can_double_jump, unlike the floor case above, so leaping
			# out of water can't be extended into a second airborne jump.
			# Shorter than a regular jump (SURFACE_JUMP_MULT), and requires
			# solid ground/wall within reach — treading water in open water
			# with nothing nearby doesn't let her hop out.
			velocity.y = JUMP_VELOCITY * SURFACE_JUMP_MULT * GameData.jump_mult * jump_weight_factor
			jump_buffer_timer = 0.0
		elif not _in_water and GameData.double_jump_enabled and can_double_jump:
			velocity.y = JUMP_VELOCITY * GameData.jump_mult * jump_weight_factor
			can_double_jump = false
			jump_buffer_timer = 0.0

	if not _wall_jump_input_locked and not is_wall_sliding:
		var speed = MOVE_SPEED * (1.0 + (GameData.move_speed_herb_bonus + GameData.agility_herb_speed_bonus) / 100.0) * slow_factor
		if direction != 0 and sign(direction) != facing:
			speed *= 0.7
		if on_slippery_tile:
			velocity.x = move_toward(velocity.x, direction * speed, SLIPPERY_ACCEL * delta)
		else:
			# direction is already forced to 0 while is_stunned (which
			# apply_shock() sets), so this naturally hard-stops horizontal
			# movement the instant she's shocked — no special case needed.
			# Vertical velocity is untouched here either way, so gravity/
			# falling momentum keeps going uninterrupted; that's the real
			# distinction from apply_freeze(), which explicitly zeros the
			# whole velocity vector (both axes) instead.
			velocity.x = direction * speed

	move_and_slide()
	# Same-frame catch — the top-of-frame check (above, start of this
	# function) only catches this one frame late, which is the gap where a
	# NaN result from this specific move_and_slide() call could still
	# render once before recovering. Checking right here closes that gap
	# for the main/default movement path specifically (the one active
	# during ordinary standing-and-taking-a-hit situations, as opposed to
	# the dodge/knockback/water/grapple/plunge branches above, which each
	# already return before reaching this line).
	if is_nan(velocity.x) or is_nan(velocity.y):
		_recover_from_nan()

func _has_stair_corner() -> bool:
	var away_from_wall = sign(get_wall_normal().x)
	var space = get_world_2d().direct_space_state
	var from = global_position + Vector2(away_from_wall * 6, 12)
	var to = from + Vector2(0, 20)
	var query = PhysicsRayQueryParameters2D.create(from, to, 1)
	query.exclude = [self.get_rid()]
	return not space.intersect_ray(query).is_empty()

# Checked before letting a water-surface jump fire — a short raycast in
# each of a few directions against the terrain layer (1), same technique
# _has_stair_corner() already uses. Treading water with nothing solid
# nearby shouldn't let her hop out.
func _near_solid_terrain() -> bool:
	var space = get_world_2d().direct_space_state
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		var query = PhysicsRayQueryParameters2D.create(
			global_position, global_position + dir * SURFACE_JUMP_TERRAIN_RANGE, 1)
		query.exclude = [self.get_rid()]
		if not space.intersect_ray(query).is_empty():
			return true
	return false

func _draw() -> void:
	if not (GameData.elemental_active and GameData.elemental_element == "elec"):
		return
	const RANGE = 125.0
	const HALF_RAD = PI / 180.0 * 35.0
	var aim = get_local_mouse_position().normalized()
	var base_angle = aim.angle()
	var line_col = Color(1.0, 1.0, 0.3, 0.4)
	var arc_col = Color(1.0, 1.0, 0.3, 0.8)
	draw_line(Vector2.ZERO, Vector2.from_angle(base_angle - HALF_RAD) * RANGE, line_col, 1.0)
	draw_line(Vector2.ZERO, Vector2.from_angle(base_angle + HALF_RAD) * RANGE, line_col, 1.0)
	draw_arc(Vector2.ZERO, RANGE, base_angle - HALF_RAD, base_angle + HALF_RAD, 32, arc_col, 2.0)

func _process(delta):
	_update_sprite(delta)
	_update_camera_zoom(delta)
	_update_camera_lock(delta)
	_update_camera_shake(delta)
	_update_elec_redraw()
	_tick_passives(delta)
	_tick_status_effects(delta)
	_tick_scout_weapon_drain(delta)
	# Glint's off scouting, or a cutscene/dialogue is playing — no attacking,
	# aiming, or herb-charging for Elana until it's over, on top of the
	# movement freeze in _physics_process. Also locked for the whole
	# prologue — she's canonically too weak to fight until Stone Being
	# actually grants her the power, not just during the cutscenes.
	if not GameData.glint_scouting and not GameData.in_cutscene and GameData.received_stone_being_power:
		_handle_attack_input(delta)
		_update_facing_from_mouse()
		_update_herb_state(delta)

func _update_sprite(delta: float) -> void:
	if not _sprite:
		return
	_sprite.flip_h = facing == -1
	_sprite.position.x = _sprite_base_x + (flip_offset_x if facing == -1 else 0.0)
	var attacking_now = is_attacking or is_plunge_attacking
	if attacking_now and not _was_attacking_anim:
		_fist_attack_anim = "attack_fist" if randi() % 2 == 0 else "attack_fist2"
	_was_attacking_anim = attacking_now
	var moving_now = abs(velocity.x) > 10.0
	# Bored idle — sticky once triggered. Moving/blocking only pauses the
	# countdown (or holds the already-triggered state) instead of resetting
	# it; only an actual attack, a hit taken, or leaving fist resets it.
	if GameData.current_weapon != "fist" or attacking_now:
		_idle_timer = 0.0
		_idle_normal_active = false
	elif not moving_now and not is_blocking:
		_idle_timer += delta
		if _idle_timer >= IDLE_NORMAL_THRESHOLD:
			_idle_normal_active = true
	var anim: String
	# Glint is the one who visually becomes the weapon, hovering at Elana's
	# side — she's detached and off scouting during this, so the weapon
	# shouldn't still show on Elana's own sprite even though
	# GameData.current_weapon stays the real, logically-equipped weapon
	# underneath (gameplay-wise, and for the scouting HP-drain cost — see
	# _tick_scout_weapon_drain()). Visual-only override, confined to anim
	# selection here.
	var visual_weapon: String = "fist" if GameData.glint_scouting else GameData.current_weapon
	if attacking_now:
		anim = _fist_attack_anim if visual_weapon == "fist" else "attack_" + visual_weapon
		if not _sprite.sprite_frames.has_animation(anim):
			anim = "attack_fist"
	elif moving_now:
		anim = "walk"
	elif visual_weapon == "fist" and _idle_normal_active and _sprite.sprite_frames.has_animation("idle_normal"):
		anim = "idle_normal"
	else:
		anim = "idle_" + visual_weapon
		if not _sprite.sprite_frames.has_animation(anim):
			anim = "idle"
	# Only trigger play() when the animation actually changes — guarantees the
	# attack anim starts fresh exactly once and is left alone for the rest of
	# the swing, instead of depending on Godot's same-name replay behavior.
	if _sprite.animation != anim:
		_sprite.play(anim)

const BOSS_ZOOM: Vector2 = Vector2(3.5, 3.5)

func _update_camera_zoom(delta: float) -> void:
	if GameData.dev_fixed_zoom_1x:
		$Camera.zoom = $Camera.zoom.lerp(Vector2(1.5, 1.5), 5.0 * delta)
		return
	# Boss arena reveal — overrides the normal context-based zoom entirely and
	# stays wide indefinitely once set (nothing clears it automatically; a
	# future "boss defeated" trigger would be the one to turn it back off).
	# boss_zoom_active and camera_locked now flip on together in one step
	# (dialog_marker.gd's BossCameraLock()) — no separate intermediate
	# cutscene zoom stage anymore; the pan/roar/knockup reveal beat before it
	# (Boss1NormalEntrance()) deliberately leaves zoom untouched. Slower
	# than the 5.0 rate every combat zoom pop above uses (those are meant to
	# be quick, punchy reactions) — this is a one-shot cinematic zoom, so a
	# gentler ease reads as smooth rather than snappy.
	if GameData.boss_zoom_active:
		$Camera.zoom = $Camera.zoom.lerp(BOSS_ZOOM, 1.5 * delta)
		return
	var zoom_active := false
	if is_plunge_attacking:
		_zoom_target = Vector2(2.6, 2.6)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	elif _grapple_timer > 0.0:
		_zoom_target = Vector2(2.8, 2.8)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	elif is_air_dashing:
		_zoom_target = Vector2(3.3, 3.3)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	elif is_heavy_attack and GameData.current_weapon == "spear":
		_zoom_target = Vector2(3.3, 3.3)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	elif not is_on_floor() and not can_double_jump and GameData.double_jump_enabled:
		_zoom_target = Vector2(3.0, 3.0)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	elif not is_on_floor():
		_zoom_target = Vector2(3.3, 3.3)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	elif abs(velocity.x) > 0.0 and not is_dodging:
		_zoom_target = Vector2(3.7, 3.7)
		_zoom_lerp_speed = 5.0
		zoom_active = true
	if zoom_active:
		_zoom_return_timer = 0.4
	else:
		_zoom_return_timer = max(0.0, _zoom_return_timer - delta)
		if _zoom_return_timer <= 0.0:
			_zoom_target = Vector2(4.0, 4.0)
			_zoom_lerp_speed = 5.0
	$Camera.zoom = $Camera.zoom.lerp(_zoom_target, _zoom_lerp_speed * delta)

# Public — call from anywhere a heavy impact happens (warhammer heavy hits,
# Fire Blast, plunge landing, taking a big hit). Additive and clamped, so
# several triggers landing close together don't overshoot past full shake.
func add_camera_trauma(amount: float) -> void:
	_shake_trauma = min(1.0, _shake_trauma + amount)

# Shared by both NaN-position check points. Always recovers to
# _last_valid_position (never teleports to the checkpoint — that was more
# disruptive than the bug itself, per user feedback).
func _recover_from_nan() -> void:
	_nan_recovery_streak += 1
	global_position = _last_valid_position
	_last_recovery_position = global_position
	velocity = Vector2.ZERO

# While GameData.camera_locked is true (boss-arena reveal cutscene — see
# dialog_marker.gd), keeps $Camera's own native limit_left/top/right/
# bottom synced to GameData.camera_bounds — NOT manual per-frame offset math
# like this used to do. The engine clamps its own rendered camera position
# directly against those limits, so there's no "assumed position vs. actual
# position" to fall out of sync (that's what caused the jump-triggered
# wonkiness with the old camera_offset_base-based approach — it worked from
# Elana's exact global_position each frame, an assumption a fast jump could
# outrun before the lerp caught up). Limits apply correctly regardless of
# drag/smoothing settings, so nothing else needs touching for this. Once
# cleared (reset_boss_camera(), on boss death or her own respawn), limits
# are restored to their captured "unlimited" defaults from _ready().
func _update_camera_lock(delta: float) -> void:
	# A scripted pan-tween (dialog_marker.gd's CAMERA_PAN cutscene) owns
	# camera_offset_base directly right now — touching it here too would
	# fight the tween's own animation every frame instead of leaving it in
	# sole control.
	if GameData.camera_pan_active:
		return
	if GameData.camera_locked:
		# An empty bounds rect means no boss-provided bounds (e.g. a future
		# boss without get_camera_bounds()) — leave whatever limits are
		# already applied rather than clamping to a single point at (0,0).
		if GameData.camera_bounds.size != Vector2.ZERO:
			$Camera.limit_left = int(GameData.camera_bounds.position.x)
			$Camera.limit_right = int(GameData.camera_bounds.end.x)
			$Camera.limit_top = int(GameData.camera_bounds.position.y)
			$Camera.limit_bottom = int(GameData.camera_bounds.end.y)
	else:
		$Camera.limit_left = _default_camera_limit_left
		$Camera.limit_top = _default_camera_limit_top
		$Camera.limit_right = _default_camera_limit_right
		$Camera.limit_bottom = _default_camera_limit_bottom
	# No lock-driven offset anymore — bounding is entirely the native
	# limits' job now, so this just decays back to zero same as always.
	camera_offset_base = camera_offset_base.lerp(Vector2.ZERO, 5.0 * delta)

func _update_camera_shake(delta: float) -> void:
	if _shake_trauma > 0.0:
		_shake_trauma = max(0.0, _shake_trauma - SHAKE_DECAY * delta)
	if not GameData.screen_shake_enabled or _shake_trauma <= 0.0:
		$Camera.offset = camera_offset_base
		return
	var amount = _shake_trauma * _shake_trauma
	var shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAX_OFFSET * amount
	$Camera.offset = camera_offset_base + shake_offset

func _update_elec_redraw() -> void:
	var elec_active = GameData.elemental_active and GameData.elemental_element == "elec"
	if elec_active or _elec_was_active != elec_active:
		queue_redraw()
	_elec_was_active = elec_active

func _handle_attack_input(delta: float) -> void:
	var transforming = GameData.transform_delay_timer > 0.0
	if is_stunned or is_blocking:
		return
	# In water: no plunge (falls through to a normal light attack instead)
	# and no charging into a heavy attack — light attacks only.
	if Input.is_action_just_pressed("attack") and not is_attacking and not is_plunge_attacking and not is_charging and not transforming:
		if not is_on_floor() and not _in_water and Input.is_action_pressed("move_down"):
			_start_plunge()
		else:
			attack()
	if not _in_water and not is_attacking and not is_plunge_attacking and not is_charging and not transforming:
		if Input.is_action_pressed("attack"):
			charge_timer += delta
			if charge_timer >= CHARGE_THRESHOLD:
				is_charging = true
		else:
			charge_timer = 0.0

func _update_facing_from_mouse() -> void:
	if not is_plunge_attacking and not _is_spinning and not _wall_jump_input_locked:
		var mouse_pos = get_global_mouse_position()
		var hb_width = _override_hitbox_size.x if _override_hitbox_size.x > 0 else GameData.weapon_hitbox_size.x
		if mouse_pos.x > global_position.x:
			$Hitbox.position.x = 0.0
			facing = 1
		else:
			$Hitbox.position.x = -hb_width
			facing = -1

# Passive defenses upkeep: Last Stand cooldown, Iron Body barrier,
# HP regen with overheal→shield conversion, shield aura visual
func _tick_passives(delta: float) -> void:
	if GameData.last_stand_cd > 0.0:
		GameData.last_stand_cd = max(0.0, GameData.last_stand_cd - delta)
	if GameData.dev_no_cooldowns:
		GameData.last_stand_cd = 0.0
	# Iron Body — accumulate no-damage timer; grant barrier when 20s reached
	if GameData.iron_body_pct > 0.0 and GameData.hp > 0:
		_iron_body_timer += delta
		if _iron_body_timer >= 20.0:
			_iron_body_timer = 0.0
			var ib_cap = GameData.max_hp * GameData.iron_body_pct
			if _iron_body_shield_hp < ib_cap:
				_iron_body_shield_hp = ib_cap
				GameData.passive_shield_hp = min(float(GameData.max_hp), _overheal_shield_hp + _iron_body_shield_hp)
	var total_regen = GameData.hp_regen + GameData.hp_regen_herb_bonus * (1.0 + GameData.herb_heal_bonus)
	if total_regen > 0.0 and GameData.hp > 0:
		var new_hp = GameData.hp + total_regen * delta
		if new_hp > GameData.max_hp and GameData.overheal_conv > 0.0:
			var overflow = new_hp - GameData.max_hp
			var oh_cap = GameData.max_hp * 0.50
			var can_add = max(0.0, oh_cap - _overheal_shield_hp)
			if can_add > 0.0:
				var gain = min(overflow * GameData.overheal_conv, can_add)
				_overheal_shield_hp += gain
				GameData.passive_shield_hp = min(float(GameData.max_hp), _overheal_shield_hp + _iron_body_shield_hp)
			new_hp = GameData.max_hp
		GameData.hp = min(GameData.max_hp, new_hp)
	# Hollowscale outline — hugs the sprite's silhouette, shown only while the
	# ward is charged and ready
	if _sprite_effects_material != null:
		var hs_ready = GameData.hollowscale_unlocked and GameData.hollowscale_cooldown <= 0.0
		_sprite_effects_material.set_shader_parameter("enabled", hs_ready)

const SCOUT_HP_DRAIN_PER_SEC: float = 2.0

# Cost of keeping the current weapon equipped while Glint's off scouting —
# she no longer force-reverts to fist the instant scouting starts (see the
# scout_glint input handler), so this is what actually makes leaving a
# weapon transformed active while detached cost something. Fist has no
# Glint HP pool to drain (same guard glint_take_hit() itself uses), so
# there's nothing to lose while unarmed. If this drains her to 0 mid-scout,
# she doesn't revert immediately/mid-flight — that's check_weapon_depletion(),
# called once scouting fully ends (glint.gd's _process_scouting()), same as
# every other Glint-HP-cost path in this file already defers to.
func _tick_scout_weapon_drain(delta: float) -> void:
	if not GameData.glint_scouting or GameData.current_weapon == "fist":
		return
	GameData.glint_hp = max(0.0, GameData.glint_hp - SCOUT_HP_DRAIN_PER_SEC * delta)

# Blessing #3 — slows every active enemy and enemy projectile in the room;
# Elana is unaffected. No new slow mechanic: reuses the existing apply_slow()
# built for hazards.
func _trigger_danger_sense() -> void:
	if _is_dead or GameData.danger_sense_cooldown > 0.0:
		return
	GameData.danger_sense_cooldown = GameData.DANGER_SENSE_COOLDOWN
	GameData.danger_sense_active_timer = GameData.DANGER_SENSE_DURATION
	GameData.spawn_float_text("DANGER SENSE", global_position, Color(0.85, 0.35, 0.85))
	HUD.flash_danger_sense_overlay(GameData.DANGER_SENSE_DURATION)
	var targets = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("enemy_projectiles")
	for target in targets:
		if target.has_method("apply_slow"):
			target.apply_slow(GameData.DANGER_SENSE_SLOW_FACTOR, GameData.DANGER_SENSE_DURATION)

# Herb right-click charge tracking + cleanup when the herb expires
func _update_herb_state(delta: float) -> void:
	if GameData.active_herb != null and not (HUD.inventory_open or HUD.char_screen_open or HUD.skill_tree_open or HUD._options_open):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			herb_charge_timer += delta
			if herb_charge_timer >= HERB_CHARGE_THRESHOLD and not is_herb_charging:
				is_herb_charging = true
				if GameData.active_herb.item_id == "herbElementalElec":
					_herb_storm()
				elif GameData.active_herb.item_id == "herbHeal":
					_start_life_barrier()
		elif not is_herb_charging:
			herb_charge_timer = 0.0
	# Herb expiry cleanup
	if GameData.active_herb == null:
		if _storm_active:
			_storm_active = false
		if _blood_fury_active:
			_blood_fury_active = false
			GameData.damage_multiplier = 1.0
			if GameData.herb_drain_multiplier == 1.5:
				GameData.herb_drain_multiplier = 1.0
			_blood_fury_visual.visible = false
		if _life_barrier_active:
			_stop_life_barrier()
		if is_herb_charging:
			is_herb_charging = false
			herb_charge_timer = 0.0
		_herb_skill_pending = false
	# Fire an airborne-released charged skill the instant she lands
	if _herb_skill_pending and is_on_floor():
		_herb_skill_pending = false
		is_herb_charging = false
		_trigger_herb_skill()
		_start_herb_cast_lock()
	if _casting_herb_skill:
		_cast_lock_timer -= delta
		if _cast_lock_timer <= 0.0:
			_casting_herb_skill = false

func _start_herb_cast_lock() -> void:
	_casting_herb_skill = true
	_cast_lock_timer = HERB_CAST_LOCK_DURATION

func get_attack_cooldown() -> float:
	var as_clamped = clamp(float(GameData.attack_speed_stat + GameData.weapon_attack_speed + GameData.attack_speed_herb_bonus), 0.0, 100.0)
	var reduction = ATTACK_SPEED_R_MAX * pow(as_clamped / 100.0, ATTACK_SPEED_P)
	return max(0.01, GameData.weapon_base_cooldown - reduction)

func _spawn_shockwave() -> void:
	var sw = preload("res://shockwave.gd").new()
	var tip_x = facing * GameData.weapon_hitbox_size.x
	sw.global_position = global_position + Vector2(tip_x, 0.0)
	sw.direction = facing
	sw.damage = max(1, _melee_base_damage(GameData.shockwave_pct))
	sw.source = self
	get_parent().add_child(sw)

func attack():
	is_attacking = true
	_hit_this_swing.clear()
	if not is_on_floor():
		velocity.y = 0.0
		_suppress_gravity = true
	# 100% slower (double every timing) while in water — captured once at
	# the start of the swing, not re-checked mid-await, so surfacing
	# mid-swing doesn't yank the timing out from under an in-progress hit.
	var water_mult = 2.0 if _in_water else 1.0
	match GameData.current_weapon:
		"warhammer":
			await get_tree().create_timer(0.5 * water_mult).timeout
		"spear":
			await get_tree().create_timer(0.5 * water_mult).timeout
		_:
			await get_tree().create_timer(ATTACK_WINDUP * water_mult).timeout
	$Hitbox/CollisionShape2D.shape.size = GameData.weapon_hitbox_size
	$Hitbox/CollisionShape2D.position.x = GameData.weapon_hitbox_size.x / 2.0
	$Hitbox.monitoring = true
	if GameData.shockwave_pct > 0.0:
		_spawn_shockwave()
	await get_tree().create_timer(GameData.weapon_swing_window * water_mult).timeout
	$Hitbox.monitoring = false
	_suppress_gravity = false
	await get_tree().create_timer(max(0.0, get_attack_cooldown() - GameData.weapon_swing_window) * water_mult).timeout
	GameData.check_weapon_depletion()
	is_attacking = false

func heavy_attack() -> void:
	is_attacking = true
	is_heavy_attack = true
	_hit_this_swing.clear()
	match GameData.current_weapon:
		"fist":       await _heavy_fist()
		"sword":      await _heavy_sword()
		"spear":      await _heavy_spear()
		"warhammer":  await _heavy_warhammer()
		"chain_claw": await _heavy_chain()
		_:
			$Hitbox/CollisionShape2D.shape.size = GameData.weapon_hitbox_size
			$Hitbox/CollisionShape2D.position.x = GameData.weapon_hitbox_size.x / 2.0
			$Hitbox.monitoring = true
			await get_tree().create_timer(GameData.weapon_swing_window * 2.0).timeout
			$Hitbox.monitoring = false
	is_heavy_attack = false
	await get_tree().create_timer(get_attack_cooldown()).timeout
	GameData.check_weapon_depletion()
	is_attacking = false

func _heavy_fist() -> void:
	if not is_on_floor():
		velocity.y = 0.0
		_suppress_gravity = true
	await get_tree().create_timer(ATTACK_WINDUP).timeout
	$Hitbox/CollisionShape2D.shape.size = GameData.weapon_hitbox_size
	$Hitbox/CollisionShape2D.position.x = GameData.weapon_hitbox_size.x / 2.0
	$Hitbox.monitoring = true
	await get_tree().create_timer(GameData.weapon_swing_window * 2.0).timeout
	$Hitbox.monitoring = false
	_suppress_gravity = false

func _heavy_sword() -> void:
	var heavy_size = Vector2(56.0, 30.0)
	_override_hitbox_size = heavy_size
	if not is_on_floor():
		velocity.y = 0.0
		_suppress_gravity = true
	await get_tree().create_timer(ATTACK_WINDUP).timeout
	$Hitbox/CollisionShape2D.shape.size = heavy_size
	$Hitbox/CollisionShape2D.position.x = heavy_size.x / 2.0
	$Hitbox.monitoring = true
	await get_tree().create_timer(GameData.weapon_swing_window * 2.0).timeout
	$Hitbox.monitoring = false
	_suppress_gravity = false
	_override_hitbox_size = Vector2.ZERO

func _heavy_spear() -> void:
	if not is_on_floor():
		velocity.y = 0.0
		_suppress_gravity = true
	await get_tree().create_timer(ATTACK_WINDUP).timeout
	$Hitbox/CollisionShape2D.shape.size = GameData.weapon_hitbox_size
	$Hitbox/CollisionShape2D.position.x = GameData.weapon_hitbox_size.x / 2.0
	_spear_dash_speed = 550.0 * facing
	_spear_dash_timer = 0.25
	$Hitbox.monitoring = true
	await get_tree().create_timer(0.25).timeout
	$Hitbox.monitoring = false
	_suppress_gravity = false

func _heavy_warhammer() -> void:
	var initial_facing = facing
	_is_spinning = true
	$Hitbox/CollisionShape2D.shape.size = GameData.weapon_hitbox_size
	for i in 5:
		var spin_facing = initial_facing if i % 2 == 0 else -initial_facing
		facing = spin_facing
		$Hitbox.position.x = 0.0 if spin_facing == 1 else -GameData.weapon_hitbox_size.x
		$Hitbox/CollisionShape2D.position.x = GameData.weapon_hitbox_size.x / 2.0
		_hit_this_swing.clear()
		if not is_on_floor():
			velocity.y = 0.0
			_suppress_gravity = true
		$Hitbox.monitoring = true
		await get_tree().create_timer(0.12).timeout
		$Hitbox.monitoring = false
		_suppress_gravity = false
		if i < 4:
			await get_tree().create_timer(0.05).timeout
	_is_spinning = false

func _heavy_chain() -> void:
	var proj = preload("res://chain_projectile.gd").new()
	proj.direction = (get_global_mouse_position() - global_position).normalized()
	# Intentional: the thrown chain gets fresh-weapon power but not the on-hit
	# Glint bonuses (crit/stacks/weapon dmg) — those are melee-only.
	proj.damage = _melee_base_damage(GameData.weapon_heavy_multiplier)
	proj.source = self
	# add_child() first: global_position on an unparented node is just its
	# local position (no parent transform to resolve against yet), so setting
	# it before parenting double-counts the level root's own offset once the
	# node is added. Parent first, then set the real world position.
	get_parent().add_child(proj)
	proj.global_position = global_position

func _apply_heavy_knockback(enemy: Node) -> void:
	# _pending_knockback is a base_enemy.gd field — not every "enemies"-group
	# member declares it (e.g. hollowfang.gd extends CharacterBody2D
	# directly), so an undeclared-property write here would throw a runtime
	# script error instead of silently doing nothing.
	if not ("_pending_knockback" in enemy):
		return
	match GameData.current_weapon:
		"fist":
			enemy._pending_knockback = Vector2(0.0, -260.0)
		"sword":
			enemy._pending_knockback = Vector2(facing * 100.0, -320.0)
		"spear":
			enemy._pending_knockback = Vector2(facing * 120.0, -220.0)
		"warhammer":
			enemy._pending_knockback = Vector2(facing * 550.0, -260.0)

func pick_up(item: String) -> void:
	GameData.add_item(item)
	HUD.refresh_slots()

func _input(event) -> void:
	if event.is_action_pressed("scout_glint"):
		var menu_open = HUD.inventory_open or HUD.char_screen_open or HUD.skill_tree_open or HUD._options_open
		if not GameData.glint_scouting:
			if not menu_open and not _is_dead and not is_attacking and not is_plunge_attacking \
					and not is_dodging and not is_air_dashing and GameData.received_stone_being_power \
					and GameData.glint_scout_tutorial_done:
				GameData.glint_scouting = true
				# No longer cancel_ore() here — scouting keeps whatever weapon
				# is currently equipped instead of force-reverting to fist.
				# Costs 2 Glint HP/sec while scouting instead (see elana.gd's
				# _process()); if that drains her weapon's HP to 0 she reverts
				# the normal way (check_weapon_depletion(), called once
				# scouting fully ends — see glint.gd's _process_scouting()).
				if not GameData.glint_scout_return_hint_shown:
					GameData.glint_scout_return_hint_shown = true
					HUD.show_prompt("Press X again to return to Elana", get_node("Glint"), "scout_return_hint")
		elif not GameData.glint_scout_returning:
			GameData.glint_scout_returning = true
			HUD.hide_prompt("scout_return_hint")
	if event.is_action_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER_WINDOW
	if event.is_action_released("attack"):
		if is_charging:
			is_charging = false
			charge_timer = 0.0
			if GameData.transform_delay_timer <= 0.0:
				heavy_attack()
		else:
			charge_timer = 0.0
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			if _storm_active:
				_storm_active = false
				is_herb_charging = false
				herb_charge_timer = 0.0
			elif _life_barrier_active:
				_stop_life_barrier()
				is_herb_charging = false
				herb_charge_timer = 0.0
			elif is_herb_charging:
				herb_charge_timer = 0.0
				# Only Fire Blast / Ice Wall need to land first — Flash Stun
				# and Blood Fury still fire instantly on release regardless.
				var needs_ground = GameData.active_herb != null and \
						GameData.active_herb.item_id in ["herbElementalFire", "herbElementalFrost"]
				if needs_ground and not is_on_floor():
					# Released mid-air — hold the charge until she lands,
					# then fire automatically instead of casting airborne.
					_herb_skill_pending = true
				else:
					is_herb_charging = false
					_trigger_herb_skill()
					if needs_ground:
						_start_herb_cast_lock()
			else:
				herb_charge_timer = 0.0
				if GameData.elemental_active and elemental_cooldown_timer <= 0.0:
					if not (HUD.inventory_open or HUD.char_screen_open or HUD.skill_tree_open or HUD._options_open):
						_cast_elemental()

func _cast_elemental() -> void:
	if GameData.elemental_element == "elec":
		_cast_elec_bolt(false)
		return
	elemental_cooldown_timer = ELEMENTAL_COOLDOWN * (1.0 - GameData.casting_speed_bonus)
	var elem: String = GameData.elemental_element
	var dmg: int = GameData.get_magic_damage()
	var dir: Vector2 = (get_global_mouse_position() - global_position).normalized()
	_spawn_elemental_proj(elem, dmg, dir)
	if GameData.double_cast_mult > 0.0:
		var dc_dmg: int = int(float(dmg) * GameData.double_cast_mult)
		_delay_second_proj(elem, dc_dmg, dir)

func _spawn_elemental_proj(elem: String, dmg: int, dir: Vector2) -> void:
	var proj = preload("res://elemental_projectile.gd").new()
	proj.element = elem
	proj.damage = dmg
	proj.aim_direction = dir
	proj.source = self
	proj.global_position = global_position + Vector2(facing * 8.0, -4)
	get_parent().add_child(proj)

func _delay_second_proj(elem: String, dmg: int, dir: Vector2) -> void:
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self) or not GameData.elemental_active or GameData.elemental_element != elem:
		return
	_spawn_elemental_proj(elem, dmg, dir)

func _start_plunge() -> void:
	is_plunge_attacking = true
	_hit_this_swing.clear()
	var speed = PLUNGE_SPEED_CHAIN if GameData.current_weapon == "chain_claw" else PLUNGE_SPEED
	velocity.y = speed
	print("[plunge] start | weapon: %s | speed: %.0f" % [GameData.current_weapon, speed])
	match GameData.current_weapon:
		"sword":
			$Hitbox.monitoring = true
		"spear", "fist":
			$Hitbox.position = Vector2(-8, 14)
			$Hitbox.monitoring = true
		_:
			$Hitbox.monitoring = false

func _on_plunge_land() -> void:
	is_attacking = true
	add_camera_trauma(0.9)
	var dmg = _melee_base_damage(PLUNGE_LAND_MULT)
	print("[plunge] land | weapon: %s | dmg: %d" % [GameData.current_weapon, dmg])
	_show_plunge_aoe(global_position)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _in_plunge_aoe(enemy):
			var hit_dir = 1 if enemy.global_position.x >= global_position.x else -1
			# Generic hook — lets a target (Burrower) fully replace the
			# normal plunge-damage path with its own custom reaction.
			# Returns true if it handled the hit itself (skip normal damage).
			if enemy.has_method("on_plunge_hit") and enemy.on_plunge_hit(self, hit_dir, dmg):
				continue
			_plunge_hit(enemy, hit_dir, dmg)
			GameData.glint_take_hit(GameData.get_weapon_hit_cost(false))
	await get_tree().create_timer(0.35).timeout
	GameData.check_weapon_depletion()
	is_attacking = false

func _in_plunge_aoe(enemy: Node) -> bool:
	var center = global_position + Vector2(0, 11)
	var e = enemy.global_position - center
	match GameData.current_weapon:
		"warhammer":  return e.length() <= 60.0
		"fist":       return e.length() <= 20.0
		"spear":      return e.length() <= 35.0
		"sword":
			var fwd = e.x * facing
			return fwd >= 0.0 and fwd <= 70.0 and abs(e.y) <= 20.0
		"chain_claw": return abs(e.x) <= 40.0 and abs(e.y) <= 8.0
		_:            return e.length() <= 55.0

func _show_plunge_aoe(pos: Vector2) -> void:
	var poly = Polygon2D.new()
	var c = GameData.weapon_color
	poly.color = Color(c.r, c.g, c.b, 0.35)
	poly.global_position = pos + Vector2(0, 11)
	poly.z_index = 3
	match GameData.current_weapon:
		"warhammer":
			var pts := PackedVector2Array()
			for i in 32:
				var a = (float(i) / 32.0) * TAU
				pts.append(Vector2(cos(a), sin(a)) * 60.0)
			poly.polygon = pts
		"fist":
			var pts := PackedVector2Array()
			for i in 16:
				var a = (float(i) / 16.0) * TAU
				pts.append(Vector2(cos(a), sin(a)) * 20.0)
			poly.polygon = pts
		"spear":
			var pts := PackedVector2Array()
			for i in 16:
				var a = (float(i) / 16.0) * TAU
				pts.append(Vector2(cos(a), sin(a)) * 35.0)
			poly.polygon = pts
		"sword":
			var fwd = 70.0 * facing
			poly.polygon = PackedVector2Array([
				Vector2(0, -20), Vector2(fwd, -20),
				Vector2(fwd, 20), Vector2(0, 20),
			])
		"chain_claw":
			poly.polygon = PackedVector2Array([
				Vector2(-40, -8), Vector2(40, -8),
				Vector2(40, 8), Vector2(-40, 8),
			])
		_:
			var pts := PackedVector2Array()
			for i in 32:
				var a = (float(i) / 32.0) * TAU
				pts.append(Vector2(cos(a), sin(a)) * 55.0)
			poly.polygon = pts
	get_parent().add_child(poly)
	var tween = get_tree().create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.45)
	tween.tween_callback(poly.queue_free)

func _plunge_hit(enemy: Node, hit_dir: int, dmg: int) -> void:
	if enemy.get("hp") == null or enemy.hp <= 0:
		return
	var defense = enemy.get("defense") or 0
	var final_dmg = GameData.calc_damage(float(dmg), float(defense))
	# Executioner — instakill at ≤15% HP
	if GameData.executioner_chance > 0.0:
		var emax: float = float(enemy.get("max_hp") if enemy.get("max_hp") != null else 100)
		if emax > 0 and enemy.hp <= emax * 0.15 and randf() < GameData.executioner_chance:
			final_dmg = int(enemy.hp)
	if enemy.get("regen_delay_timer") != null:
		enemy.regen_delay_timer = 3.0
	enemy.hp -= final_dmg
	if enemy.get("immortal"):
		enemy.hp = max(1.0, enemy.hp)
	GameData.spawn_damage_number(final_dmg, enemy.global_position)
	if GameData.lifesteal > 0.0:
		GameData.hp = min(GameData.max_hp, GameData.hp + int(float(final_dmg) * GameData.lifesteal))
	# Anger Strikes — bonus % of enemy max HP when Power Herb active
	if GameData.anger_strikes_pct > 0.0 and GameData.active_herb != null and GameData.active_herb.item_id == "herbPower":
		var emax: float = float(enemy.get("max_hp") if enemy.get("max_hp") != null else 100)
		var bonus: int = max(1, int(emax * GameData.anger_strikes_pct))
		enemy.hp -= bonus
		GameData.spawn_damage_number(bonus, enemy.global_position + Vector2(0, -14), Color(0.7, 0.2, 1.0))
	var color_rect = enemy.get_node_or_null("ColorRect")
	var orig: Color = enemy.get("original_color") if enemy.get("original_color") != null else Color.WHITE
	if color_rect:
		color_rect.color = Color.RED
	if enemy.hp <= 0 and not enemy.get("immortal"):
		GameData.mark_removed(get_tree().current_scene.scene_file_path, enemy.name)
		GameData.glint_register_kill()
		GameData.gain_xp(enemy.get("xp_reward") or 0)
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(enemy):
			enemy.queue_free()
		return
	_plunge_effect(enemy, hit_dir, color_rect, orig)

func _plunge_effect(enemy: Node, hit_dir: int, color_rect: ColorRect, orig: Color) -> void:
	# is_stunned/_pending_knockback are base_enemy.gd fields — not every
	# "enemies"-group member declares them (e.g. hollowfang.gd extends
	# CharacterBody2D directly), so skip the whole stun/knockback sequence
	# for anything that doesn't support it rather than crashing on the
	# undeclared-property write. (color_rect is already null for those
	# targets too, since it's looked up by a node name only base_enemy.gd
	# enemies have, so nothing else here needs guarding.)
	if not ("is_stunned" in enemy):
		return
	enemy.is_stunned = true
	match GameData.current_weapon:
		"warhammer":
			enemy._pending_knockback = Vector2(hit_dir * 450.0, -200.0)
			var ind = GameData.make_stun_indicator()
			enemy.add_child(ind)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(color_rect): color_rect.color = orig
			if is_instance_valid(enemy): enemy.velocity.x = 0
			await get_tree().create_timer(1.0).timeout
			if is_instance_valid(enemy): enemy.is_stunned = false
			if is_instance_valid(ind): ind.queue_free()
		"sword":
			enemy._pending_knockback = Vector2(facing * 38.0, -105.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(color_rect): color_rect.color = orig
			await get_tree().create_timer(0.35).timeout
			if is_instance_valid(enemy): enemy.is_stunned = false
		"fist":
			enemy._pending_knockback = Vector2(0.0, -188.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(color_rect): color_rect.color = orig
			await get_tree().create_timer(0.3).timeout
			if is_instance_valid(enemy): enemy.is_stunned = false
		"spear":
			enemy._pending_knockback = Vector2(0.0, -150.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(color_rect): color_rect.color = orig
			await get_tree().create_timer(0.3).timeout
			if is_instance_valid(enemy): enemy.is_stunned = false
		"chain_claw":
			enemy._pending_knockback = Vector2(hit_dir * 100.0, -50.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(color_rect): color_rect.color = orig
			await get_tree().create_timer(0.1).timeout
			if is_instance_valid(enemy): enemy.is_stunned = false


# enemy.global_position sits at each enemy's own collision origin — fine for
# normal-sized enemies (effectively their body center), but wildly off for a
# huge boss like Hollowfang. get_targeting_points() (opt-in hook) lets an
# enemy expose several candidate points (e.g. head/body/tail markers placed
# by hand in the editor) instead of one fixed spot — picks whichever is
# actually closest to Elana, so short-range effects can connect near any
# part of a large boss. get_targeting_center() is a single-point version of
# the same hook for enemies that only need one. Falls back to plain
# global_position for anything implementing neither.
func _enemy_target_pos(enemy: Node) -> Vector2:
	if enemy.has_method("get_targeting_points"):
		var points: Array = enemy.get_targeting_points()
		if not points.is_empty():
			var best: Vector2 = points[0]
			var best_dist: float = global_position.distance_to(best)
			for i in range(1, points.size()):
				var d: float = global_position.distance_to(points[i])
				if d < best_dist:
					best_dist = d
					best = points[i]
			return best
	if enemy.has_method("get_targeting_center"):
		return enemy.get_targeting_center()
	return enemy.global_position

func _find_elec_target() -> Node:
	const MAX_RANGE = 125.0
	const HALF_ANGLE_DEG = 35.0
	var aim = (get_global_mouse_position() - global_position).normalized()
	var closest: Node = null
	var closest_dist = INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = _enemy_target_pos(enemy) - global_position
		var dist = to_enemy.length()
		if dist > MAX_RANGE:
			continue
		if abs(rad_to_deg(aim.angle_to(to_enemy.normalized()))) > HALF_ANGLE_DEG:
			continue
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	return closest

func _cast_elec_bolt(from_storm: bool = false) -> void:
	var closest: Node = _find_elec_target()
	if closest == null:
		return
	elemental_cooldown_timer = ELEMENTAL_COOLDOWN * (1.0 - GameData.casting_speed_bonus)
	var bolt_dmg: int = GameData.get_magic_damage()
	var hit_dir: int = 1 if closest.global_position.x >= global_position.x else -1
	closest.on_elemental_hit("elec", hit_dir, bolt_dmg, self)
	_draw_elec_bolt(global_position, _enemy_center(closest))
	if GameData.chain_lightning_count > 0:
		var prev: Node = closest
		var chain_dmg: int = int(bolt_dmg * 0.7)
		for _i in GameData.chain_lightning_count:
			var next: Node = _find_chain_target(prev)
			if next == null:
				break
			var chain_dir: int = 1 if next.global_position.x >= prev.global_position.x else -1
			next.on_elemental_hit("elec", chain_dir, chain_dmg, self)
			_draw_elec_bolt(_enemy_center(prev), _enemy_center(next))
			chain_dmg = int(chain_dmg * 0.7)
			prev = next
	if not from_storm and GameData.double_cast_mult > 0.0:
		var dc_dmg: int = int(float(bolt_dmg) * GameData.double_cast_mult)
		_delay_second_elec(dc_dmg)

func _delay_second_elec(dmg: int) -> void:
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self) or not GameData.elemental_active or GameData.elemental_element != "elec":
		return
	var closest: Node = _find_elec_target()
	if closest == null:
		return
	var hit_dir: int = 1 if closest.global_position.x >= global_position.x else -1
	closest.on_elemental_hit("elec", hit_dir, dmg, self)
	_draw_elec_bolt(global_position, _enemy_center(closest))

# Enemies' global_position sits at their feet (collision origin) — offset
# upward so elec effects visually connect to the middle of their body
# instead of the ground beneath them.
func _enemy_center(enemy: Node) -> Vector2:
	return _enemy_target_pos(enemy) + Vector2(0, -10)

const ELECTRIC_BOLT_FRAMES = [
	"res://projectiles/electric_bolt1.png",
	"res://projectiles/electric_bolt2.png",
	"res://projectiles/electric_bolt3.png",
]

const ELECTRIC_BOLT_NATIVE_WIDTH: float = 24.0
const ELECTRIC_BOLT_NATIVE_HEIGHT: float = 16.0

# Elec is an instant hitscan zap (no travel time like fire/frost) — the bolt
# sprite is repeated end-to-end at native scale along the strike path
# (never squashed/stretched). If the distance isn't an exact multiple of the
# sprite's width, the leftover space gets one cropped partial segment instead
# of compressing every segment's spacing to fit evenly.
func _draw_elec_bolt(from: Vector2, to: Vector2) -> void:
	var frames = SpriteFrames.new()
	frames.add_animation("spark")
	frames.set_animation_loop("spark", true)
	frames.set_animation_speed("spark", 12.0)
	for path in ELECTRIC_BOLT_FRAMES:
		frames.add_frame("spark", load(path))

	var diff = to - from
	var dist = diff.length()
	var angle = diff.angle()
	var dir = diff.normalized() if dist > 0.0 else Vector2.RIGHT
	var full_segments = int(dist / ELECTRIC_BOLT_NATIVE_WIDTH)
	var leftover = dist - float(full_segments) * ELECTRIC_BOLT_NATIVE_WIDTH

	for i in full_segments:
		var pos = from + dir * (ELECTRIC_BOLT_NATIVE_WIDTH * (float(i) + 0.5))
		_spawn_elec_bolt_segment(frames, pos, angle)

	if leftover > 1.0:
		var cropped_frames = SpriteFrames.new()
		cropped_frames.add_animation("spark")
		cropped_frames.set_animation_loop("spark", true)
		cropped_frames.set_animation_speed("spark", 12.0)
		for path in ELECTRIC_BOLT_FRAMES:
			var atlas = AtlasTexture.new()
			atlas.atlas = load(path)
			atlas.region = Rect2(0, 0, leftover, ELECTRIC_BOLT_NATIVE_HEIGHT)
			cropped_frames.add_frame("spark", atlas)
		var pos = from + dir * (ELECTRIC_BOLT_NATIVE_WIDTH * float(full_segments) + leftover / 2.0)
		_spawn_elec_bolt_segment(cropped_frames, pos, angle)

	_spawn_elec_bolt_glow(from + diff * 0.5, angle, dist)
	_spawn_elec_impact_glow(to)

# Linear fill instead of radial — fades only across the bolt's thickness
# (top-to-bottom of the texture) and stays uniformly bright along its full
# length, so it reads as a straight bar of light instead of an ellipse.
# Two layers: a normal one that fades slowly, and a thinner/hotter one on
# top that fades out quick.
func _spawn_elec_bolt_glow(pos: Vector2, angle: float, length: float) -> void:
	_spawn_elec_line_light(pos, angle, length, 4, 6.0, 0.8)
	_spawn_elec_line_light(pos, angle, length, 8, 10.0, 0.15)

func _spawn_elec_line_light(pos: Vector2, angle: float, length: float, thickness: int, energy: float, fade_duration: float) -> void:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.5, 1])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.9, 0.2, 0),
		Color(3.0, 3.0, 1.8, 1),
		Color(1.0, 0.9, 0.2, 0),
	])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	# Width baked directly to the bolt's actual length, height fixed (and
	# thin) — texture_scale stays at 1.0 so thickness never couples to
	# length, and width never overshoots past the bolt's visible ends.
	tex.width = max(8, int(length))
	tex.height = thickness

	var light = PointLight2D.new()
	light.texture = tex
	light.color = Color.WHITE
	light.energy = energy
	light.texture_scale = 1.0
	light.rotation = angle
	light.global_position = pos
	light.z_index = 10
	get_tree().current_scene.add_child(light)
	var tween := light.create_tween()
	# Sharp flash instead of a slow fade — hits hard then cuts out fast.
	tween.tween_property(light, "energy", 0.0, fade_duration)
	tween.tween_callback(light.queue_free)

# Two radial bursts stacked at the same spot (the bolt's landing point) — a
# big one that fades slowly (matching the normal line's speed), and a
# smaller, more intense one on top that fades out quick (matching the
# intense line's speed).
func _spawn_elec_impact_glow(pos: Vector2) -> void:
	_spawn_elec_radial_light(pos, 0.18, 0.3, 5.0, 0.8)
	_spawn_elec_radial_light(pos, 0.4, 0.65, 10.0, 0.15)

func _spawn_elec_radial_light(pos: Vector2, start_scale: float, end_scale: float, energy: float, fade_duration: float) -> void:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.35, 1])
	gradient.colors = PackedColorArray([
		Color(3.0, 3.0, 1.8, 1),
		Color(1.0, 0.9, 0.2, 0.6),
		Color(1.0, 0.9, 0.2, 0),
	])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	tex.width = 96
	tex.height = 96

	var light = PointLight2D.new()
	light.texture = tex
	light.color = Color.WHITE
	light.energy = energy
	light.texture_scale = start_scale
	light.global_position = pos
	light.z_index = 10
	get_tree().current_scene.add_child(light)
	var tween := light.create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "energy", 0.0, fade_duration)
	tween.tween_property(light, "texture_scale", end_scale, fade_duration)
	tween.set_parallel(false)
	tween.tween_callback(light.queue_free)

func _spawn_elec_bolt_segment(frames: SpriteFrames, pos: Vector2, angle: float) -> void:
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.global_position = pos
	sprite.rotation = angle
	sprite.z_index = 10
	sprite.play("spark")
	get_tree().current_scene.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.25)
	tween.tween_callback(sprite.queue_free)

func _find_chain_target(prev: Node) -> Node:
	const CHAIN_RANGE: float = 150.0
	var best: Node = null
	var best_dist: float = CHAIN_RANGE
	var prev_pos: Vector2 = _enemy_target_pos(prev)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == prev:
			continue
		var dist: float = _enemy_target_pos(enemy).distance_to(prev_pos)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best

# ── Herb charged skill dispatcher ──────────────────────────────────────────────

func _trigger_herb_skill() -> void:
	if GameData.active_herb == null:
		return
	match GameData.active_herb.item_id:
		"herbElementalFire":  _herb_fire_blast()
		"herbElementalFrost": _herb_ice_wall()
		"herbAgility":      _herb_flash_stun()
		"herbPower":      _herb_blood_fury()
		# herbHeal (Life Barrier) is a hold-channel like herbElementalElec
		# (Storm) — started at charge-threshold, stopped on release.

# ── 1. Fire Blast — herbElementalFire ──────────────────────────────────────────────────

func _herb_fire_blast() -> void:
	if not GameData.is_skill_unlocked("fire_blast_skill"):
		return
	add_camera_trauma(0.6)
	const RADIUS := 40.0
	var dmg = GameData.get_magic_damage()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= RADIUS:
			var dir: int = int(sign(enemy.global_position.x - global_position.x))
			if dir == 0: dir = facing
			enemy.on_elemental_hit("fire", dir, dmg, self)
			# _pending_knockback is a base_enemy.gd field — not every
			# "enemies"-group member declares it (e.g. hollowfang.gd).
			if "_pending_knockback" in enemy:
				enemy._pending_knockback = (enemy.global_position - global_position).normalized() * 75.0 + Vector2(0.0, -30.0)
	_spawn_fire_blast_sprite(global_position + Vector2(0, -5))
	_spawn_fire_explosion_glow(global_position + Vector2(0, -5))

# ── 2. Ice Wall — herbElementalFrost ───────────────────────────────────────────────────

func _herb_ice_wall() -> void:
	if not GameData.is_skill_unlocked("shield_wall_skill"):
		return
	var wall = preload("res://ice_wall.gd").new()
	wall.hp = float(GameData.get_magic_damage()) * 2.0
	wall.global_position = global_position + Vector2(facing * 16.0, 0.0)
	get_parent().add_child(wall)

# ── 3. Storm — herbElementalElec ──────────────────────────────────────────────────────

func _herb_storm() -> void:
	if not GameData.is_skill_unlocked("storm_skill"):
		return
	if _storm_active:
		return
	_storm_active = true
	GameData.herb_drain_multiplier = 3.0
	_run_storm()

func _run_storm() -> void:
	while _storm_active and GameData.active_herb != null:
		_cast_elec_bolt(true)
		await get_tree().create_timer(0.2).timeout
	_storm_active = false
	if GameData.active_herb != null and GameData.herb_drain_multiplier == 3.0:
		GameData.herb_drain_multiplier = 1.0

# ── 4. Flash Stun — Agility Herb ─────────────────────────────────────────────────────

func _herb_flash_stun() -> void:
	if not GameData.is_skill_unlocked("flash_stun_skill"):
		return
	var cost: float = GameData.herb_max_timer * 0.25
	if GameData.herb_timer < cost:
		return
	GameData.herb_timer -= cost
	for enemy in get_tree().get_nodes_in_group("enemies"):
		# stun_timer/is_stunned are base_enemy.gd fields — not every
		# "enemies"-group member declares them (e.g. hollowfang.gd extends
		# CharacterBody2D directly and has no stun state at all).
		if not ("is_stunned" in enemy):
			continue
		enemy.stun_timer = 3.0
		enemy.is_stunned = true
		enemy.velocity = Vector2.ZERO
		# Cancel a mid-windup attack outright. attack_cooldown gets a brief
		# grace period too — without it, _tick_attack()'s own restart branch
		# fires the instant is_stunned clears (windup==0, in zone, no
		# cooldown), skipping idle entirely. With it, unstun shows idle first
		# and a fresh windup only starts once the grace period runs out.
		# Not every "enemies" member has this (training_dummy doesn't attack).
		var windup = enemy.get("attack_windup_timer")
		var anim_timer = enemy.get("attack_anim_timer")
		var mid_attack = (windup != null and windup > 0.0) or (anim_timer != null and anim_timer > 0.0)
		if mid_attack:
			enemy.attack_windup_timer = 0.0
			enemy.attack_anim_timer = 0.0
			enemy.attack_cooldown = max(enemy.attack_cooldown, 0.4)
		var cr = enemy.get_node_or_null("ColorRect")
		if cr:
			cr.color = Color(1.0, 1.0, 0.3)
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(enemy): cr.color = enemy.original_color)
		var stun_indicator = GameData.make_stun_indicator()
		enemy.add_child(stun_indicator)
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(stun_indicator): stun_indicator.queue_free())
	_show_circle_flash(global_position, 200.0, Color(1.0, 1.0, 0.5, 0.35))

# ── 5. Life Barrier — Heal Herb ───────────────────────────────────────────────────

func _make_barrier_circle_texture() -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 48
	tex.height = 48
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	return tex

# Same radial gradient, but transparent → opaque → transparent, so only a
# thin ring near the outer edge shows instead of a filled disc.
func _make_ring_texture() -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.72, 0.82, 0.92, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.9),
		Color(1, 1, 1, 0.9),
		Color(1, 1, 1, 0.0),
	])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 48
	tex.height = 48
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	return tex

func _start_life_barrier() -> void:
	if not GameData.is_skill_unlocked("life_barrier_skill") or _life_barrier_active:
		return
	_life_barrier_active = true
	GameData.herb_drain_multiplier = 2.0
	_life_barrier_visual.visible = true

func _stop_life_barrier() -> void:
	_life_barrier_active = false
	if GameData.herb_drain_multiplier == 2.0:
		GameData.herb_drain_multiplier = 1.0
	_life_barrier_visual.visible = false

# ── 6. Blood Fury — Power Herb ─────────────────────────────────────────────────────

func _herb_blood_fury() -> void:
	if not GameData.is_skill_unlocked("blood_fury_skill"):
		return
	if _blood_fury_active:
		_blood_fury_active = false
		GameData.damage_multiplier /= 2.0
		if GameData.herb_drain_multiplier == 1.5:
			GameData.herb_drain_multiplier = 1.0
		_blood_fury_visual.visible = false
	else:
		_blood_fury_active = true
		GameData.damage_multiplier *= 2.0
		GameData.herb_drain_multiplier = 1.5
		_blood_fury_visual.visible = true

# ── Shared visual helper ───────────────────────────────────────────────────────

func _show_circle_flash(pos: Vector2, radius: float, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.color = color
	poly.global_position = pos
	poly.z_index = 3
	var pts := PackedVector2Array()
	for i in 24:
		var a := (float(i) / 24.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	get_parent().add_child(poly)
	var tween := get_tree().create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.35)
	tween.tween_callback(poly.queue_free)

const FIRE_BLAST_FRAMES = [
	"res://fire_charged_attack/F0.png",
	"res://fire_charged_attack/F1.png",
	"res://fire_charged_attack/F2.png",
	"res://fire_charged_attack/F3.png",
	"res://fire_charged_attack/F4.png",
	"res://fire_charged_attack/F5.png",
	"res://fire_charged_attack/F6.png",
	"res://fire_charged_attack/F7.png",
]

func _spawn_fire_blast_sprite(pos: Vector2) -> void:
	var frames = SpriteFrames.new()
	frames.add_animation("blast")
	frames.set_animation_loop("blast", false)
	frames.set_animation_speed("blast", 14.0)
	for path in FIRE_BLAST_FRAMES:
		frames.add_frame("blast", load(path))
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.global_position = pos
	sprite.z_index = 3
	sprite.animation_finished.connect(sprite.queue_free)
	get_parent().add_child(sprite)
	sprite.play("blast")

# Same red-hot/yellow-fade radial burst as the thrown fireball's impact
# glow, just bigger — sized to roughly cover Fire Blast's own AOE radius.
func _spawn_fire_explosion_glow(pos: Vector2) -> void:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.35, 1])
	gradient.colors = PackedColorArray([
		Color(3.0, 0.45, 0.15, 1),
		Color(3.0, 2.7, 0.6, 0.6),
		Color(3.0, 2.7, 0.6, 0),
	])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	tex.width = 128
	tex.height = 128

	var light = PointLight2D.new()
	light.texture = tex
	light.color = Color.WHITE
	light.energy = 3.0
	light.texture_scale = 0.5
	light.global_position = pos
	light.z_index = 3
	get_parent().add_child(light)
	var tween := light.create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "energy", 0.0, 0.5)
	tween.tween_property(light, "texture_scale", 1.0, 0.5)
	tween.set_parallel(false)
	tween.tween_callback(light.queue_free)
