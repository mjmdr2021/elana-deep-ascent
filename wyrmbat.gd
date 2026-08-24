extends CharacterBody2D

# Wyrmbat -- twin boss #1 of 2 ("Great King Wyrmbat"), the flying half of a
# fully independent twin encounter (Graniteus is the other -- no shared
# HP/mechanical link, though their ATTACKS can affect each other -- see the
# backlog's own "cross-boss interactions" list, all deferred, not built in
# this pass). extends CharacterBody2D directly, same "too different a shape"
# call every boss in this codebase makes. True flight -- no gravity.
#
# Idle = clings to the ceiling (see _tick_ceiling_cling()). In combat, while
# no attack is ready, she flies left-to-right across the arena instead of
# holding still (2026-08-24, user explicit: "when bat in combat, it
# constantly flies left to right if attacks are on cooldown.") -- needs
# arena_bounds_path wired (same convention cobblecroak.gd's Rain of Rocks
# already uses) to know where the walls are.
#
# 4 attacks, each on its OWN cooldown (2026-08-24, user explicit: "only bat
# has cooldown on attacks" -- Graniteus instead uses one shared rest, see
# his own file). Fixed priority order when multiple are simultaneously
# ready (rare, cooldowns are all different lengths): Blackout Canopy >
# King's Slumber > Shriek Wave > Spike Tail.
#
# is_stunned/stun_timer exist ONLY so Elana's Flash Stun (_herb_flash_stun()
# in elana.gd, which loops "enemies"-group members checking `"is_stunned" in
# enemy`) actually reaches her -- without these fields she'd be silently
# skipped. A real stun-lock (frozen, same as every other enemy Flash Stun
# hits) AND the specific thing the user asked for: clears Blackout Canopy
# early if it's active.
#
# No other special immunities (no quartered knockback, no self-knockback on
# a hit) -- Cobblecroak-specific flavor, not a generic boss convention.

@export var max_hp: int = 1800
@export var defense: int = 100
@export var xp_reward: int = 250

@export_group("Movement")
@export var combat_fly_speed: float = 70.0
# Slow vertical sine bob while combat-flying (2026-08-24, user: "when
# flying, do bobing up and down slowly") -- absolute-position based
# (bob_base_y + sin(...)), not velocity-driven, so it can't drift over a
# long fight. Bobs her whole real body (not just the visual), keeping the
# Hurtbox/attacks in sync with what's actually drawn.
@export var combat_fly_bob_amplitude: float = 6.0
@export var combat_fly_bob_speed: float = 1.5  # radians/sec -- slow

@export_group("Ceiling Cling")
@export var ceiling_probe_range: float = 400.0
@export var ceiling_rest_offset: float = 8.0
@export var ceiling_move_speed: float = 60.0
@export var ceiling_arrive_threshold: float = 2.0
# How far below the ceiling she descends back to once King's Slumber ends
# (2026-08-24, user-specified: "200px below ceiling"). Only used by
# _do_kings_slumber()'s own post-heal descent, NOT a general combat-fly
# height gate. Computed off _ceiling_y, not a fixed world Y, so it adapts
# to whatever room she's actually in.
@export var combat_fly_height_offset: float = 200.0

@export_group("Arena")
@export var arena_bounds_path: NodePath

@export_group("Blackout Canopy")
@export var blackout_canopy_enabled: bool = false  # 2026-08-24, user: disabled for now (isolating other attacks during testing)
@export var blackout_canopy_cooldown: float = 45.0
@export var blackout_canopy_swoop_duration: float = 1.5
@export var blackout_canopy_effect_duration: float = 30.0
# Elana's own fog_of_war.gd defaults elana_reveal_radius to 28 -- this is
# what it gets forced down to for the effect's duration.
@export var blackout_canopy_reveal_radius: float = 8.0

@export_group("Spike Tail")
@export var spike_tail_enabled: bool = true
@export var spike_tail_cooldown: float = 2.0  # 2026-08-24, user: increase frequency (was 4.0)
@export var spike_tail_speed: float = 700.0
@export var spike_tail_damage: int = 15

@export_group("Shriek Wave")
@export var shriek_wave_enabled: bool = true
@export var shriek_wave_cooldown: float = 12.0
@export var shriek_wave_windup: float = 0.4
# Purely cosmetic echo rings, played AFTER the disarm lands, not locking
# her out of combat for the whole duration (2026-08-24, user: "do a
# visual. like a circle going out like an echo. every second. shriek
# lasts 5 seconds").
@export var shriek_wave_echo_duration: float = 5.0
@export var shriek_wave_echo_interval: float = 1.0
# Proximity-scaled damage (2026-08-24, user: "do damage to elana and the
# nearer she is to bat, the bigger the damage.. does significant damage if
# very very close to bat") -- linear falloff from max_damage at point-blank
# down to min_damage at the edge of the radius, nothing beyond it. Doesn't
# touch the disarm itself, which stays unconditional/range-independent as
# it already was.
@export var shriek_wave_damage_radius: float = 300.0
@export var shriek_wave_max_damage: int = 40
@export var shriek_wave_min_damage: int = 5

@export_group("King's Slumber")
@export var kings_slumber_enabled: bool = true
@export var kings_slumber_cooldown: float = 40.0
@export var kings_slumber_heal_pct_per_sec: float = 0.05
@export var kings_slumber_duration: float = 10.0
# Overflow past max_hp converts to shield instead of being wasted, same
# "overheal -> shield" shape Elana's own overheal_conv system already uses,
# capped as a % of max_hp (2026-08-24, user explicit: "slumber generates
# 15% shield if overhealing").
@export var kings_slumber_shield_cap_pct: float = 0.15

const SPIKE_SCENE: PackedScene = preload("res://wyrmbat_tailspike.tscn")
const SHRIEK_ECHO_SCENE: PackedScene = preload("res://wyrmbat_shriek_echo.tscn")

var hp: float
var direction: int = 1
var target: Node = null
var original_color: Color
var _ceiling_y: float = 0.0
var _is_clinging: bool = false
var _is_at_flight_height: bool = false
var _bob_time: float = 0.0
var _bob_base_y: float = 0.0
var _is_attacking: bool = false
var _is_slumbering: bool = false
var _shield_hp: float = 0.0
var _combat_fly_direction: int = 1

var is_stunned: bool = false
var stun_timer: float = 0.0

var _blackout_canopy_cooldown_timer: float = 0.0
var _blackout_canopy_active_timer: float = 0.0
var _blackout_canopy_original_reveal_radius: float = 28.0
var _spike_tail_cooldown_timer: float = 0.0
var _shriek_wave_cooldown_timer: float = 0.0
var _kings_slumber_cooldown_timer: float = 0.0

@onready var _hp_bar: Node2D = $HPBar
@onready var _hp_bg: ColorRect = $HPBar/Background
@onready var _hp_fill: ColorRect = $HPBar/Fill
@onready var _shield_bar: Node2D = $ShieldBar
@onready var _shield_bg: ColorRect = $ShieldBar/Background
@onready var _shield_fill: ColorRect = $ShieldBar/Fill
@onready var _body_visual: ColorRect = $ColorRect
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _boulder_redirect_zone: Area2D = $BoulderRedirectZone
@onready var _arena_bounds: Node = get_node_or_null(arena_bounds_path)

func _ready() -> void:
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	add_to_group("enemies")
	add_to_group("bosses")
	hp = max_hp
	original_color = _body_visual.color
	_boulder_redirect_zone.area_entered.connect(_on_boulder_redirect_zone_area_entered)
	_find_ceiling()
	# Starts already on cooldown -- every cooldown timer defaults to 0.0
	# (ready), so without this, King's Slumber (2nd priority, right after
	# Blackout Canopy) would fire the instant she first engages combat
	# (2026-08-24, user: "start slumber cd immediately. so it doesnt
	# slumber at start").
	_kings_slumber_cooldown_timer = kings_slumber_cooldown
	if _arena_bounds == null:
		push_warning("Wyrmbat: arena_bounds_path not wired -- aggro detection, combat left-right flying, and any arena-width attacks won't work.")

# Aggro is driven by the arena bounds rect, not a dedicated AggroZone shape
# (2026-08-24, user: "use the arena as aggro zone for wyrmbat" -- matches
# the same rework graniteus.gd just got) -- checked every physics frame
# rather than via Area2D enter/exit signals.
func _tick_aggro() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var elana = tree.get_first_node_in_group("player")
	if elana == null:
		return
	var arena_rect: Rect2 = _get_arena_rect()
	if arena_rect.size == Vector2.ZERO:
		return  # arena not wired -- can't determine aggro, stays idle (see the push_warning above)
	var elana_inside: bool = arena_rect.has_point(elana.global_position)
	if elana_inside and target == null:
		target = elana
	elif not elana_inside and target != null:
		target = null
		_find_ceiling()

func _get_arena_rect() -> Rect2:
	if _arena_bounds == null:
		return Rect2()
	var shape_node: CollisionShape2D = _arena_bounds.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Rect2()
	var rect: RectangleShape2D = shape_node.shape
	var center: Vector2 = _arena_bounds.global_position + shape_node.position
	return Rect2(center - rect.size / 2.0, rect.size)

func _physics_process(delta: float) -> void:
	_tick_aggro()
	_tick_stun(delta)
	_tick_cooldowns(delta)
	_tick_blackout_canopy(delta)
	_update_facing()
	if not is_stunned:
		_apply_movement(delta)
	else:
		velocity = Vector2.ZERO
	_update_hp_bar()
	_update_shield_bar()
	move_and_slide()

# Flash Stun's own loop just sets is_stunned/stun_timer/velocity directly
# (see elana.gd's _herb_flash_stun()) -- this just decays it and, the one
# thing the user actually asked for, clears Blackout Canopy the instant she
# gets stunned while it's active.
func _tick_stun(delta: float) -> void:
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
	if is_stunned and _blackout_canopy_active_timer > 0.0:
		_end_blackout_canopy()

func _tick_cooldowns(delta: float) -> void:
	if _blackout_canopy_cooldown_timer > 0.0:
		_blackout_canopy_cooldown_timer -= delta
	if _spike_tail_cooldown_timer > 0.0:
		_spike_tail_cooldown_timer -= delta
	if _shriek_wave_cooldown_timer > 0.0:
		_shriek_wave_cooldown_timer -= delta
	if _kings_slumber_cooldown_timer > 0.0:
		_kings_slumber_cooldown_timer -= delta

func _update_facing() -> void:
	if target == null:
		return
	direction = 1 if target.global_position.x >= global_position.x else -1
	_hurtbox.scale.x = direction

func _apply_movement(delta: float) -> void:
	if _is_attacking:
		return
	if target == null:
		_tick_ceiling_cling()
		return
	if _try_start_attack():
		return
	_tick_combat_fly(delta)

# Constant left-right patrol across the whole arena while every attack is on
# cooldown (2026-08-24, replaces the old "chase and hold at stop distance"
# idle-in-combat behavior entirely -- see the header comment). Also carries
# a slow vertical sine bob on top -- absolute-position based off
# _bob_base_y (set once, the moment she arrives at the ceiling or finishes
# her post-Slumber descent -- see _tick_ceiling_cling() and
# _do_kings_slumber()), not accumulated through velocity, so it can't
# drift over a long fight. Never height-gated here -- Y is otherwise left
# wherever it last was; only King's Slumber deliberately moves her
# vertically mid-combat (up to the ceiling, then back down after).
func _tick_combat_fly(delta: float) -> void:
	var range: Vector2 = _get_arena_x_range()
	if global_position.x <= range.x:
		_combat_fly_direction = 1
	elif global_position.x >= range.y:
		_combat_fly_direction = -1
	_bob_time += delta
	global_position.y = _bob_base_y + sin(_bob_time * combat_fly_bob_speed) * combat_fly_bob_amplitude
	velocity = Vector2(combat_fly_speed * _combat_fly_direction, 0.0)

func _get_arena_x_range() -> Vector2:
	if _arena_bounds == null:
		return Vector2(global_position.x, global_position.x)
	var shape_node: CollisionShape2D = _arena_bounds.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Vector2(global_position.x, global_position.x)
	var rect: RectangleShape2D = shape_node.shape
	var center: Vector2 = _arena_bounds.global_position + shape_node.position
	return Vector2(center.x - rect.size.x / 2.0, center.x + rect.size.x / 2.0)

func _try_start_attack() -> bool:
	if blackout_canopy_enabled and _blackout_canopy_cooldown_timer <= 0.0:
		_do_blackout_canopy()
		return true
	if kings_slumber_enabled and _kings_slumber_cooldown_timer <= 0.0:
		_do_kings_slumber()
		return true
	if shriek_wave_enabled and _shriek_wave_cooldown_timer <= 0.0:
		_do_shriek_wave()
		return true
	if spike_tail_enabled and _spike_tail_cooldown_timer <= 0.0:
		_do_spike_tail()
		return true
	return false

func _tick_ceiling_cling() -> void:
	var to_ceiling: float = _ceiling_y - global_position.y
	if abs(to_ceiling) > ceiling_arrive_threshold:
		velocity = Vector2(0.0, sign(to_ceiling) * ceiling_move_speed)
		_is_clinging = false
	else:
		velocity = Vector2.ZERO
		_is_clinging = true
		# Bob center re-anchors to wherever she actually settled -- combat
		# starting fresh (not right after a Slumber) bobs from here.
		_bob_base_y = global_position.y
		_bob_time = 0.0

# Only called from _do_kings_slumber()'s own ending now, not a general
# gate on combat -- 2026-08-24, reverted the broad version (which forced
# EVERY combat-fly through this first) after user correction: the ~200px-
# below-ceiling height was never a bug to fix generally, only something
# she specifically needs to return to after Slumber ("after slumber, it
# should do the start flight 200px below ceiling on flight. because it
# doesnt do it after slumber"). Flies from wherever she currently is (the
# ceiling, fresh off healing) down to combat_fly_height_offset below
# _ceiling_y.
func _tick_descend_to_flight_height() -> void:
	var flight_y: float = _ceiling_y + combat_fly_height_offset
	var to_target: float = flight_y - global_position.y
	if abs(to_target) > ceiling_arrive_threshold:
		velocity = Vector2(0.0, sign(to_target) * ceiling_move_speed)
		_is_at_flight_height = false
	else:
		velocity = Vector2.ZERO
		_is_at_flight_height = true
		_bob_base_y = global_position.y
		_bob_time = 0.0

func _find_ceiling() -> void:
	var space = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, -ceiling_probe_range), 1)
	query.exclude = [self.get_rid()]
	var result := space.intersect_ray(query)
	_ceiling_y = result.position.y + ceiling_rest_offset if result else global_position.y

# ── Blackout Canopy ──────────────────────────────────────────────────────
# Brief scripted swoop (locks her out via _is_attacking, same as every
# other attack), THEN the actual 30s darkness effect runs independently
# afterward -- she's free to act/fly/attack normally while it's active,
# only the swoop itself is a real "attack" window.
func _do_blackout_canopy() -> void:
	_is_attacking = true
	_blackout_canopy_cooldown_timer = blackout_canopy_cooldown
	var range: Vector2 = _get_arena_x_range()
	var target_x: float = range.x if global_position.x > (range.x + range.y) / 2.0 else range.y
	var tween := create_tween()
	tween.tween_property(self, "global_position:x", target_x, blackout_canopy_swoop_duration)
	await tween.finished
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_start_blackout_canopy_effect()
	_is_attacking = false

func _start_blackout_canopy_effect() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var fog = tree.get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("get") and "elana_reveal_radius" in fog:
		_blackout_canopy_original_reveal_radius = fog.elana_reveal_radius
		fog.elana_reveal_radius = blackout_canopy_reveal_radius
	_blackout_canopy_active_timer = blackout_canopy_effect_duration

func _tick_blackout_canopy(delta: float) -> void:
	if _blackout_canopy_active_timer <= 0.0:
		return
	_blackout_canopy_active_timer -= delta
	if _blackout_canopy_active_timer <= 0.0:
		_end_blackout_canopy()

func _end_blackout_canopy() -> void:
	_blackout_canopy_active_timer = 0.0
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var fog = tree.get_first_node_in_group("fog_of_war")
	if fog != null and "elana_reveal_radius" in fog:
		fog.elana_reveal_radius = _blackout_canopy_original_reveal_radius

# ── Spike Tail ────────────────────────────────────────────────────────────
# Fires a TailSpike (wyrmbat_tailspike.gd/.tscn) -- reworked 2026-08-24 to
# match hollowfang_spike.gd's own shape: a long real CollisionShape2D that
# travels straight in whatever direction Elana was in at throw time (not
# homing, not stopping at a fixed point) until it physically hits terrain.
func _do_spike_tail() -> void:
	if target == null:
		return
	_is_attacking = true
	_spike_tail_cooldown_timer = spike_tail_cooldown
	var spike = SPIKE_SCENE.instantiate()
	spike.global_position = global_position
	spike.aim_direction = (target.global_position - global_position).normalized()
	spike.speed = spike_tail_speed
	spike.damage = spike_tail_damage
	spike.source = self
	get_tree().current_scene.add_child(spike)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self) and is_inside_tree():
		_is_attacking = false

# ── Shriek Wave ───────────────────────────────────────────────────────────
# Elana-only effect for this pass -- the Graniteus crack/stun/armor-debuff
# side of this attack is a deferred cross-boss interaction, recorded in the
# backlog, not built here.
func _do_shriek_wave() -> void:
	_is_attacking = true
	_shriek_wave_cooldown_timer = shriek_wave_cooldown
	await get_tree().create_timer(shriek_wave_windup).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	GameData.force_unequip_weapon()
	_deal_shriek_wave_damage()
	_is_attacking = false
	# Not awaited -- runs detached so the 5s echo sequence is purely
	# cosmetic and doesn't lock her out of combat for its whole duration.
	_play_shriek_echoes()

func _deal_shriek_wave_damage() -> void:
	# Reuses the already-tracked target instead of re-querying the "player"
	# group (2026-08-25, code review efficiency finding) -- target is
	# guaranteed set here since Shriek Wave only ever fires while aggro'd.
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	var dist: float = global_position.distance_to(target.global_position)
	if dist > shriek_wave_damage_radius:
		return
	var t: float = clamp(dist / shriek_wave_damage_radius, 0.0, 1.0)
	var damage: int = int(round(lerp(float(shriek_wave_max_damage), float(shriek_wave_min_damage), t)))
	target.take_damage(damage, false, self)

func _play_shriek_echoes() -> void:
	var elapsed: float = 0.0
	while elapsed < shriek_wave_echo_duration:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		var echo = SHRIEK_ECHO_SCENE.instantiate()
		echo.global_position = global_position
		get_tree().current_scene.add_child(echo)
		await get_tree().create_timer(shriek_wave_echo_interval).timeout
		elapsed += shriek_wave_echo_interval

# ── King's Slumber ────────────────────────────────────────────────────────
# Reuses the ceiling-cling position (attaches to whatever ceiling is
# nearest, same _find_ceiling()/_tick_ceiling_cling() the idle state uses)
# rather than a separate scripted fly-to-ceiling routine.
func _do_kings_slumber() -> void:
	_is_attacking = true
	_is_slumbering = true
	_kings_slumber_cooldown_timer = kings_slumber_cooldown
	_find_ceiling()
	var elapsed: float = 0.0
	# 2026-08-25, real bug found via code review: this used to call
	# move_and_slide() itself right here, on top of _physics_process()'s own
	# unconditional tail-call move_and_slide() running later the SAME frame
	# with the same still-set velocity -- double-applying movement every
	# frame (climb speed effectively doubled) for as long as this loop ran.
	# Every other coroutine-driven boss movement in this codebase only sets
	# velocity and lets that one tail call apply it; matching that
	# convention here instead of calling move_and_slide() twice.
	while is_instance_valid(self) and is_inside_tree() and _is_slumbering and elapsed < kings_slumber_duration:
		_tick_ceiling_cling()
		_heal_with_overheal_shield(kings_slumber_heal_pct_per_sec * get_physics_process_delta_time())
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_is_slumbering = false
	# Flies back down to combat_fly_height_offset below the ceiling before
	# resuming normal behavior -- 2026-08-24, user: "after slumber, it
	# should do the start flight 200px below ceiling on flight. because it
	# doesnt do it after slumber." Still held under _is_attacking the whole
	# time, same as the healing loop above -- she can't start a new attack
	# or resume combat-fly mid-descent.
	_is_at_flight_height = false
	while is_instance_valid(self) and is_inside_tree() and not _is_at_flight_height:
		_tick_descend_to_flight_height()
		await get_tree().physics_frame
	if is_instance_valid(self) and is_inside_tree():
		_is_attacking = false

# Any hit during Slumber disrupts it -- called from apply_boss_damage()
# rather than tracked via the generic _is_attacking flag, which would
# wrongly cancel whatever OTHER attack happens to be running if she got hit
# mid-Blackout-Canopy-swoop or mid-Spike-Tail instead. Only fires on real
# HP loss (shield-only absorption, see apply_boss_damage(), doesn't count
# as a disrupting "hit").
func _interrupt_kings_slumber() -> void:
	_is_slumbering = false

func _heal_with_overheal_shield(pct: float) -> void:
	var amount: float = float(max_hp) * pct
	var new_hp: float = hp + amount
	if new_hp > float(max_hp):
		var overflow: float = new_hp - float(max_hp)
		var cap: float = float(max_hp) * kings_slumber_shield_cap_pct
		_shield_hp = min(cap, _shield_hp + overflow)
		new_hp = float(max_hp)
	hp = new_hp

func _update_hp_bar() -> void:
	_hp_fill.size.x = clamp(hp / float(max_hp), 0.0, 1.0) * _hp_bg.size.x
	_hp_bar.visible = GameData.show_hp_bars and hp < max_hp

# Shows King's Slumber's overheal shield (2026-08-24, user: "show shield on
# bat's over regen") -- same gold shield-bar color language HUD.gd already
# uses for Elana's own overheal_conv shield, stacked just above her HP bar.
# Filled relative to the shield's own cap (kings_slumber_shield_cap_pct of
# max_hp), not max_hp itself, so it always reads as "how full is the
# shield," not "how big is the shield relative to her health."
func _update_shield_bar() -> void:
	var cap: float = float(max_hp) * kings_slumber_shield_cap_pct
	_shield_fill.size.x = clamp(_shield_hp / cap, 0.0, 1.0) * _shield_bg.size.x if cap > 0.0 else 0.0
	_shield_bar.visible = GameData.show_hp_bars and _shield_hp > 0.0

# Chain Claw's Yank writes directly to is_stunned/_pending_knockback --
# she declares is_stunned (for Elana's own Flash Stun, see the header
# comment) but NOT _pending_knockback, so the pull's own write to it was
# throwing a real runtime error (2026-08-24, user report). Same "too big/
# boss-tier" call Hollowfang/Elemander/Broodspawner already make -- with
# this, chain_projectile.gd's own blocks_chain_pull() check now correctly
# reverses the pull (Elana yanked to her instead) rather than attempting
# the crash-prone normal pull at all.
func blocks_chain_pull() -> bool:
	return true

func apply_boss_damage(damage: int) -> void:
	if hp <= 0:
		return
	var remaining: float = float(damage)
	if _shield_hp > 0.0:
		var absorbed: float = min(_shield_hp, remaining)
		_shield_hp -= absorbed
		remaining -= absorbed
	if remaining > 0.0:
		hp -= remaining
		# Real HP damage (not fully shield-absorbed) disrupts Slumber.
		_interrupt_kings_slumber()
	GameData.spawn_crit_aware_damage_number(damage, global_position)
	_flash_hit()
	if hp <= 0:
		_die()

func _flash_hit() -> void:
	_body_visual.color = Color.RED
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		_body_visual.color = original_color

# Cross-boss interaction #4 -- BoulderRedirectZone (a real Area2D below her
# body, see wyrmbat.tscn) fires this the instant a Graniteus boulder
# actually touches it (2026-08-25, user: "why not make a collision box
# below the bat, and when collided, does the flap redirect" -- real
# collision instead of the per-frame proximity poll this used to be).
# Boulders sit on their own dedicated collision_layer (64,
# graniteus_boulder.gd) specifically so this zone's mask only ever picks
# those up -- nothing else can trigger it.
func _on_boulder_redirect_zone_area_entered(area: Area2D) -> void:
	if not area.has_method("redirect_toward"):
		return
	flap_wings()
	# Reuses the already-tracked target instead of re-querying the "player"
	# group (2026-08-25, code review efficiency finding) -- unlike Shriek
	# Wave/Mountain Judgement, this zone isn't gated on being aggro'd, so
	# target can genuinely be null here; same global_position fallback as
	# before covers that case.
	area.redirect_toward(target.global_position if is_instance_valid(target) else global_position)

# Cosmetic flap (no real wing sprite to animate yet) -- a quick bright
# flash reads as the flap; the boulder itself owns the actual redirect/
# explosion (see graniteus_boulder.gd's redirect_toward()).
func flap_wings() -> void:
	_body_visual.color = Color.WHITE
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self):
		_body_visual.color = original_color

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	var final_damage: int = GameData.calc_damage(float(damage), float(defense))
	apply_boss_damage(final_damage)

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

func on_plunge_hit(attacker: Node, hit_direction: int, damage: int) -> bool:
	on_hit(hit_direction, damage, false, attacker)
	return true

func _die() -> void:
	if _blackout_canopy_active_timer > 0.0:
		_end_blackout_canopy()
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	GameData.gain_xp(xp_reward)
	queue_free()
