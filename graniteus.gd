extends CharacterBody2D

# Graniteus -- twin boss #2 of 2 ("Graniteus, Leader of Golems"), the
# grounded half of a fully independent twin encounter (Wyrmbat is the
# other -- no shared HP/mechanical link, though their ATTACKS can affect
# each other -- see the backlog's "cross-boss interactions" list, all
# deferred, not built in this pass).
#
# extends CharacterBody2D directly, not enemy.gd -- same "too different a
# shape" call every other boss in this codebase makes.
#
# Fully stationary, no chase at all (2026-08-23, user explicit: "graniteus
# will be stationary in the middle of arena. ill place it myself.").
#
# Dormant/Awake state (2026-08-23, user explicit: "so if no enemy detected.
# it becomes a big rock.") -- starts (and returns to, if Elana leaves aggro
# range) a fully invulnerable ROCK state, visually tinted gray; the instant
# she's detected he wakes to the real GOLEM state (his normal color,
# vulnerable) and stays that way until she leaves range again. on_hit()/
# on_elemental_hit() both no-op entirely while dormant.
#
# 3 attacks (2026-08-24, user explicit spec), picked via the same
# deterministic ATTACK_ROTATION round-robin cobblecroak.gd already uses --
# NO per-attack cooldowns here though (2026-08-24, user explicit: "golem
# lord has a rest between attacks" -- contrast with Wyrmbat, who instead
# has one cooldown per attack, see her own file's header). Pacing is
# entirely owned by post_attack_rest_duration + the rotation itself.
#
# Rock Shield (2026-08-24, user explicit: "golem lord also periodically
# creates a rock shield") -- a periodic passive, independent of the attack
# rotation (doesn't consume a turn), that tops up a damage-absorbing shield
# on a fixed interval while awake. Numbers below are my own recommendation
# (25s interval, 20% max_hp per top-up) -- nothing further was specified.
# Breaking it (Shriek Wave vs an active shield, cracking Graniteus instead
# if none is up) is a deferred cross-boss interaction, backlog only.
#
# Real gravity, standard terrain collision (collision_mask 1). Mountain
# Judgement's own rising terrain platform (graniteus_terrain.gd) is on this
# same shared layer -- briefly isolated onto its own dedicated layer while
# chasing an unrelated ore-piece bug, reverted back once that turned out to
# be caused by something else entirely (see graniteus_terrain.gd's own
# comment).

@export var max_hp: int = 2500
@export var defense: int = 250
@export var xp_reward: int = 300

# Same convention base_enemy.gd's own fire_resist/frost_resist/elec_resist
# exports use (1.0 = normal, <1.0 = resistant, 0.0 = fully immune) --
# extends CharacterBody2D directly rather than base_enemy.gd (see the
# header comment) so this doesn't come for free and needs its own copy,
# applied in on_elemental_hit() below. 2026-08-25, user explicit: "75% on
# frost and fire. 100% on electric" -- a rock/earth golem shrugging off
# elemental attacks except lightning arcing straight through stone.
@export_group("Elemental Resistance")
@export var fire_resist: float = 0.25
@export var frost_resist: float = 0.25
@export var elec_resist: float = 0.0

enum State { ROCK, GOLEM }
const ROCK_TINT: Color = Color(0.55, 0.55, 0.58, 1.0)
const BOULDER_TINT: Color = Color(0.5, 0.42, 0.35, 1.0)

enum Attack { MOUNTAIN_JUDGEMENT, BOULDER_ROLL, BOULDER_HURL }
const ATTACK_ROTATION: Array = [Attack.MOUNTAIN_JUDGEMENT, Attack.BOULDER_ROLL, Attack.BOULDER_HURL]

@export_group("Arena")
@export var arena_bounds_path: NodePath

@export_group("Movement")
# Chases toward her while resting between attacks (2026-08-24, user: "during
# rest, do chase to elana.") -- he's otherwise still fully stationary (never
# moves during an attack itself, Boulder Roll aside).
@export var rest_chase_speed: float = 80.0
@export var rest_chase_stop_distance: float = 60.0

# Shared rest between attacks -- my own recommendation (2026-08-24), a bit
# longer than Cobblecroak's 2.0s since every one of these attacks is bigger
# and slower (a full-arena earth wave, 3 end-to-end rolls, or 3 staggered
# throws) than anything in her kit.
@export var post_attack_rest_duration: float = 2.5

@export_group("Rock Shield")
@export var rock_shield_enabled: bool = true
@export var rock_shield_interval: float = 50.0  # 2026-08-24, user-tuned (was 25)
@export var rock_shield_amount_pct: float = 0.15  # 2026-08-24, user-tuned (was 0.2/25%, "maybe 15 for now")

@export_group("Mountain Judgement")
@export var mountain_judgement_enabled: bool = true
# Terrain rises beneath him, lifting him HIGH (2026-08-24, user-tuned: 200px
# over 3 seconds -- was 1.0s).
@export var mountain_judgement_rise_height: float = 200.0
@export var mountain_judgement_rise_time: float = 3.0
@export var mountain_judgement_hold_time: float = 0.5
# The hop he does once up on the raised terrain, before it falls out from
# under him -- 0.2s total (jump + land), user-tuned.
@export var mountain_judgement_jump_height: float = 30.0
@export var mountain_judgement_jump_time: float = 0.2
@export var mountain_judgement_drop_time: float = 0.2
@export var mountain_judgement_camera_shake: float = 1.0  # 2026-08-24, user: make landing shake big (was 0.8) -- 1.0 is the actual max, add_camera_trauma() clamps there
# Repeated (not one-shot) camera shake for the whole rise, giving a
# rumbling-earthquake feel while the terrain visibly climbs (2026-08-24,
# user: "also make camera shakes while doing it").
@export var mountain_judgement_rise_shake_interval: float = 0.2
@export var mountain_judgement_rise_shake_amount: float = 0.3
# Small spacing/stagger so the wave reads as one continuous ripple rather
# than separated bumps (2026-08-24, user: "more tight knit to each other" --
# then nudged back up slightly, "too much tight knit... just a lil bit").
@export var mountain_judgement_mound_spacing: float = 26.0
# Both directions spawn one mound per tick, together -- reads as a single
# wave splitting left and right from him, not two sequential ones.
@export var mountain_judgement_mound_stagger: float = 0.05
@export var mountain_judgement_mound_damage: int = 25
@export var mountain_judgement_mound_knockup: float = -260.0
@export var mountain_judgement_mound_knockback_x: float = 100.0
# Bigger/lower than the shared scene's own default hitbox (2026-08-24, user:
# "make collision of wave a bit lower and bigger") -- only affects mounds
# Mountain Judgement spawns, not Elemental Golem's Ground Slam.
@export var mountain_judgement_mound_hit_radius: float = 45.0  # 2026-08-24, user: increase radius of the wave (was 30)
@export var mountain_judgement_mound_hit_vertical_offset: float = 12.0
# 2026-08-24, user: "make ores also jump on the wave from judgement" --
# purely cosmetic (ore_node.gd's own bounce()), any ore node within this
# radius of a spawning mound hops along with the wave passing through.
@export var mountain_judgement_ore_bounce_radius: float = 60.0  # 2026-08-24, user: increase radius (was 40)

@export_group("Boulder Roll")
@export var boulder_roll_enabled: bool = true
@export var boulder_roll_speed: float = 260.0
@export var boulder_roll_passes: int = 3
@export var boulder_roll_camera_shake: float = 0.7
# 2026-08-24, fixed -- his own body is 168px wide (84px half-width), so a
# small ~26px radius almost never triggered: their CENTERS have to be
# within this distance, and his body visually overlaps her long before that
# (user report: "not getting hit by boulder roll"). Sized to his own
# half-width plus a buffer for Elana's own hitbox.
@export var boulder_roll_contact_radius: float = 100.0
@export var boulder_roll_contact_damage: int = 20
# 2026-08-24, user: "add significant knockback when hit by boulder roll" --
# for comparison, Hollowfang's own Bite (an ordinary attack) already uses
# 250 horizontal; a boulder physically rolling over her should hit harder
# than that.
@export var boulder_roll_contact_knockback: float = 500.0
@export var boulder_roll_contact_knockup: float = -180.0
@export var boulder_roll_contact_knockback_duration: float = 0.45
@export var boulder_roll_wall_knockup_radius: float = 60.0
@export var boulder_roll_wall_knockup: float = -240.0
# Spike Tail <-> Boulder Roll interaction (2026-08-24, user explicit --
# built ahead of the Shriek Wave <-> Graniteus one): rolling into a stuck
# TailSpike consumes it and makes him hop over it -- a real jump (upward
# velocity impulse, gravity brings him back down naturally, same as any
# other jump in this codebase), continuing to roll horizontally the whole
# time (his velocity.x gets reasserted every frame regardless, so the hop
# never interrupts the roll). Landing knocks up Elana wherever she
# currently is in the arena, not just nearby -- matches the backlog spec's
# "applying to the whole arena."
#
# 2026-08-24, reworked to real collision -- user: "it should touch the
# spike to trigger the jump" (a distance-radius guess had already gone
# through two failed tuning passes: full 2D distance missed spikes while
# he was airborne from a previous hop, horizontal-only then missed nothing
# but also ignored vertical separation entirely, wrongly triggering on
# spikes a full floor level away). trigger_boulder_roll_spike_jump() below
# is now called directly by wyrmbat_tailspike.gd's own _on_body_entered()
# the instant his REAL collision shape touches a PINNED spike -- no
# polling, no radius tuning.
@export var boulder_roll_jump_launch_speed: float = 420.0
@export var boulder_roll_jump_arena_knockup: float = -150.0  # 2026-08-24, user: decreased from -300
@export var boulder_roll_jump_arena_knockup_duration: float = 0.4

@export_group("Boulder Hurl")
@export var boulder_hurl_enabled: bool = true
@export var boulder_hurl_count: int = 3
@export var boulder_hurl_interval: float = 0.5
@export var boulder_hurl_peak_height: float = 300.0  # 2026-08-24, user: increase arc height more (was 100, then 180)
@export var boulder_hurl_damage: int = 20

const EARTH_MOUND_SCENE: PackedScene = preload("res://elemental_golem_earth_mound.tscn")
const BOULDER_SCENE: PackedScene = preload("res://graniteus_boulder.tscn")
const TERRAIN_SCENE: PackedScene = preload("res://graniteus_terrain.tscn")

var hp: float
var direction: int = 1
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var target: Node = null
var original_color: Color
var _state: int = State.ROCK

var _is_attacking: bool = false
var _is_rolling: bool = false
var _rotation_index: int = 0
var _post_attack_pause_timer: float = 0.0
var _boulder_hit_cooldown_timer: float = 0.0
var _boulder_jump_pending_landing: bool = false
var _boulder_jump_landing_timeout: float = 0.0

var _rock_shield_hp: float = 0.0
var _rock_shield_timer: float = 0.0

# Captured once at _ready() -- his true resting ground Y, snapped back to
# exactly after Mountain Judgement's terrain finishes falling (see
# _do_mountain_judgement()). 2026-08-25, real bug found: this used to
# reference an undeclared `graniteus_start_y`, which GDScript's static
# analysis can't compile -- the whole script silently failed to load as a
# result, leaving him a bare scriptless CharacterBody2D (explains a report
# of "Nonexistent function 'on_hit' in base 'CharacterBody2D'" on a melee
# hit -- on_hit() was never missing, the entire script never attached).
var _start_y: float = 0.0

@onready var _hp_bar: Node2D = $HPBar
@onready var _hp_bg: ColorRect = $HPBar/Background
@onready var _hp_fill: ColorRect = $HPBar/Fill
@onready var _shield_bar: Node2D = $ShieldBar
@onready var _shield_bg: ColorRect = $ShieldBar/Background
@onready var _shield_fill: ColorRect = $ShieldBar/Fill
@onready var _body_visual: ColorRect = $ColorRect
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _arena_bounds: Node = get_node_or_null(arena_bounds_path)

func _ready() -> void:
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	add_to_group("enemies")
	add_to_group("bosses")
	hp = max_hp
	original_color = _body_visual.color
	_start_y = position.y
	_go_dormant()
	if _arena_bounds == null:
		push_warning("Graniteus: arena_bounds_path not wired -- aggro detection, Mountain Judgement's full-arena reach, and Boulder Roll's wall bounces won't work.")

# Aggro is driven by the arena bounds rect, not a dedicated AggroZone shape
# (2026-08-24, user: "i delete agro zone collision. use the arena as the
# agro zone instead") -- checked every physics frame rather than via
# Area2D enter/exit signals, since AggroZone no longer has a
# CollisionShape2D to fire them.
func _tick_aggro() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var elana = tree.get_first_node_in_group("player")
	if elana == null:
		return
	var arena_rect: Rect2 = _get_arena_rect()
	if arena_rect.size == Vector2.ZERO:
		return  # arena not wired -- can't determine aggro, stays dormant (see the push_warning above)
	var elana_inside: bool = arena_rect.has_point(elana.global_position)
	if elana_inside and _state == State.ROCK:
		target = elana
		_wake_up()
	elif not elana_inside and _state == State.GOLEM:
		target = null
		_go_dormant()

func _wake_up() -> void:
	_state = State.GOLEM
	_body_visual.color = original_color
	_rock_shield_timer = rock_shield_interval

func _go_dormant() -> void:
	_state = State.ROCK
	_body_visual.color = ROCK_TINT
	_rock_shield_hp = 0.0
	_rock_shield_timer = 0.0

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_tick_aggro()
	_tick_rest_timer(delta)
	_tick_rock_shield(delta)
	_update_facing()
	if not _is_rolling:
		if _state == State.GOLEM and not _is_attacking and _post_attack_pause_timer > 0.0 and target != null:
			_tick_rest_chase()
		else:
			velocity.x = 0.0
	if _state == State.GOLEM and not _is_attacking:
		_tick_attack_rotation(delta)
	_update_hp_bar()
	_update_shield_bar()
	move_and_slide()

func _tick_rest_chase() -> void:
	var dist: float = abs(target.global_position.x - global_position.x)
	velocity.x = 0.0 if dist <= rest_chase_stop_distance else rest_chase_speed * direction

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

func _tick_rest_timer(delta: float) -> void:
	if _post_attack_pause_timer > 0.0:
		_post_attack_pause_timer -= delta

func _tick_rock_shield(delta: float) -> void:
	if not rock_shield_enabled or _state != State.GOLEM:
		return
	_rock_shield_timer -= delta
	if _rock_shield_timer <= 0.0:
		_rock_shield_timer = rock_shield_interval
		# Only grants a fresh shield if the current one is fully gone --
		# 2026-08-24, user explicit: "does not regain new one if current one
		# is there, damaged or not. so if its remaining like 10 shield, stay
		# as 10 shield after the interval." The timer still resets on its own
		# fixed 50s heartbeat regardless -- it's the grant itself that's
		# gated, not the interval.
		if _rock_shield_hp <= 0.0:
			_rock_shield_hp = float(max_hp) * rock_shield_amount_pct

func _update_facing() -> void:
	if target == null:
		return
	direction = 1 if target.global_position.x >= global_position.x else -1
	_hurtbox.scale.x = direction

func _get_arena_x_range() -> Vector2:
	if _arena_bounds == null:
		return Vector2(global_position.x, global_position.x)
	var shape_node: CollisionShape2D = _arena_bounds.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Vector2(global_position.x, global_position.x)
	var rect: RectangleShape2D = shape_node.shape
	var center: Vector2 = _arena_bounds.global_position + shape_node.position
	return Vector2(center.x - rect.size.x / 2.0, center.x + rect.size.x / 2.0)

# Full 2D box, used by _tick_aggro() -- same underlying shape as
# _get_arena_x_range() above, just returning both axes instead of X only.
func _get_arena_rect() -> Rect2:
	if _arena_bounds == null:
		return Rect2()
	var shape_node: CollisionShape2D = _arena_bounds.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Rect2()
	var rect: RectangleShape2D = shape_node.shape
	var center: Vector2 = _arena_bounds.global_position + shape_node.position
	return Rect2(center - rect.size / 2.0, rect.size)

# Picks the next attack in ATTACK_ROTATION the instant she's awake, aggro'd,
# not mid-attack, and not still resting from the last one. A disabled
# attack's turn is silently skipped (rotation still advances), same as
# cobblecroak.gd's own convention.
func _tick_attack_rotation(_delta: float) -> void:
	if _post_attack_pause_timer > 0.0 or target == null:
		return
	var attack: int = ATTACK_ROTATION[_rotation_index]
	_rotation_index = (_rotation_index + 1) % ATTACK_ROTATION.size()
	match attack:
		Attack.MOUNTAIN_JUDGEMENT:
			if mountain_judgement_enabled:
				_do_mountain_judgement()
		Attack.BOULDER_ROLL:
			if boulder_roll_enabled:
				_do_boulder_roll()
		Attack.BOULDER_HURL:
			if boulder_hurl_enabled:
				_do_boulder_hurl()

# ── Mountain Judgement ───────────────────────────────────────────────────
# Not a slam. Full sequence: real terrain rises beneath him, physically
# carrying him up -> brief hold at the peak -> a jump hop while up there ->
# the terrain falls back down, carrying him with it -> THEN the earth-mound
# wave fires in both directions at once, densely packed ("tight knit") --
# reuses elemental_golem_earth_mound.tscn exactly as elemental_golem.gd's
# own Ground Slam does, just bigger and bidirectional. "sometimes creates
# breakable terrain" from the spec is still NOT built this pass -- flagged
# to the user as deferred, not silently dropped.
#
# 2026-08-24, reworked per user: "lets make the terrain a different scene
# outside of graniteus... it should be rested on ground. its not attached
# to golem." graniteus_terrain.tscn is a real, independent AnimatableBody2D
# (Godot's dedicated moving-platform body) spawned at his feet -- he does
# NOT tween his own Y for the rise/fall at all anymore; he just naturally
# stands on it and gets carried up/down by real physics (his own gravity +
# move_and_slide()'s built-in platform inheritance), same as standing on
# any other floor. This is what fixed the earlier "terrain jumps with him"
# and "spurious extra jump on landing" bugs, not workarounds on top of the
# old self-tweened version.
func _do_mountain_judgement() -> void:
	_is_attacking = true
	var terrain = TERRAIN_SCENE.instantiate()
	terrain.rise_height = mountain_judgement_rise_height
	terrain.rise_time = mountain_judgement_rise_time
	terrain.fall_time = mountain_judgement_drop_time
	terrain.global_position = global_position + Vector2(4, 48)  # matches his own feet offset, see body CollisionShape2D
	get_parent().add_child(terrain)
	# Not awaited directly -- runs detached so this coroutine can shake the
	# camera repeatedly on its own timer for the whole rise instead of just
	# waiting silently (2026-08-24, user: "also make camera shakes while
	# doing it"). Both are driven by the same mountain_judgement_rise_time,
	# so they stay in sync.
	#
	# 2026-08-25: "golem gets lost when doing judgement" investigated with
	# real diagnostic logging (see [[feedback_confirm_root_cause_before_fixing]])
	# before writing any fix -- confirmed platform-riding itself is fine
	# (drift stayed a stable ~1.8px all rise, is_on_floor() true throughout,
	# never a runaway divergence). The actual cause was almost certainly the
	# ore-piece bounce-spam bug (severe frame drops during Judgement feeding
	# a huge delta into a single physics step) -- already fixed separately,
	# and this stopped reproducing once that fix landed. No change needed
	# here; kept trusting the real platform physics as originally built.
	terrain.rise()
	var rise_elapsed: float = 0.0
	while rise_elapsed < mountain_judgement_rise_time:
		await get_tree().physics_frame
		if not is_instance_valid(self) or not is_inside_tree():
			if is_instance_valid(terrain):
				terrain.queue_free()
			return
		var pd: float = get_physics_process_delta_time()
		rise_elapsed += pd
		# Reuses the already-tracked target instead of re-querying the
		# "player" group every physics frame for the whole rise (2026-08-25,
		# code review efficiency finding) -- target is guaranteed set here
		# since Mountain Judgement only ever starts while aggro'd.
		if is_instance_valid(target) and target.has_method("add_camera_trauma") and int(rise_elapsed / mountain_judgement_rise_shake_interval) != int((rise_elapsed - pd) / mountain_judgement_rise_shake_interval):
			target.add_camera_trauma(mountain_judgement_rise_shake_amount)
	if not is_instance_valid(self) or not is_inside_tree():
		if is_instance_valid(terrain):
			terrain.queue_free()
		return
	await get_tree().create_timer(mountain_judgement_hold_time).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		if is_instance_valid(terrain):
			terrain.queue_free()
		return
	var peak_y: float = position.y
	var jump_tween := create_tween()
	jump_tween.tween_property(self, "position:y", peak_y - mountain_judgement_jump_height, mountain_judgement_jump_time * 0.5)
	jump_tween.tween_property(self, "position:y", peak_y, mountain_judgement_jump_time * 0.5)
	await jump_tween.finished
	if not is_instance_valid(self) or not is_inside_tree():
		if is_instance_valid(terrain):
			terrain.queue_free()
		return
	await terrain.fall()
	if is_instance_valid(terrain):
		terrain.queue_free()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	position.y = _start_y  # snap exactly back to true ground level
	var elana = get_tree().get_first_node_in_group("player")
	if elana and elana.has_method("add_camera_trauma"):
		elana.add_camera_trauma(mountain_judgement_camera_shake)
	var mound_counts: Vector2i = _mound_counts_for_arena()
	var max_count: int = max(mound_counts.x, mound_counts.y)
	for i in max_count:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if i < mound_counts.x:
			_spawn_earth_mound(1, i)
		if i < mound_counts.y:
			_spawn_earth_mound(-1, i)
		await get_tree().create_timer(mountain_judgement_mound_stagger).timeout
	if is_instance_valid(self) and is_inside_tree():
		_post_attack_pause_timer = post_attack_rest_duration
		_is_attacking = false

# Per-direction, not symmetric off total arena width -- 2026-08-24, bug
# found via user report ("doesn't reach end of arena"): using half the
# total arena width assumes he's sitting exactly at arena center, but he
# gets placed by hand and isn't guaranteed to be. Each side now uses his
# ACTUAL current distance to that side's own edge, so both directions
# always reach their real wall regardless of where he's standing.
# x = mounds needed to the right, y = mounds needed to the left.
func _mound_counts_for_arena() -> Vector2i:
	var range: Vector2 = _get_arena_x_range()
	if range.x == range.y:
		return Vector2i(5, 5)  # arena not wired -- same fallback count Ground Slam defaults to
	var right: float = max(range.y - global_position.x, 0.0)
	var left: float = max(global_position.x - range.x, 0.0)
	return Vector2i(
		int(ceil(right / mountain_judgement_mound_spacing)),
		int(ceil(left / mountain_judgement_mound_spacing))
	)

func _spawn_earth_mound(dir: int, index: int) -> void:
	var mound = EARTH_MOUND_SCENE.instantiate()
	var mound_pos: Vector2 = position + Vector2(dir * mountain_judgement_mound_spacing * (index + 1), 0.0)
	mound.position = mound_pos
	mound.away_direction = dir
	mound.damage = mountain_judgement_mound_damage
	mound.knockup = mountain_judgement_mound_knockup
	mound.knockback_x = mountain_judgement_mound_knockback_x
	mound.hit_radius = mountain_judgement_mound_hit_radius
	mound.hit_vertical_offset = mountain_judgement_mound_hit_vertical_offset
	get_parent().call_deferred("add_child", mound)
	_bounce_nearby_ore(mound_pos, mountain_judgement_ore_bounce_radius)

# Any ore node or loose ore piece within radius of pos hops along with a
# ground knockup Graniteus causes (2026-08-24, user: "make ores also jump
# on the wave from judgement" / "make ore pieces also jump on the knock
# ups on the ground caused by graniteus") -- ore_node.gd's bounce() is a
# cosmetic sprite tween, ore_piece.gd's is a real upward velocity impulse
# (it's a RigidBody2D), but both expose the same bounce() call so this one
# helper covers both without caring which it's touching.
func _bounce_nearby_ore(pos: Vector2, radius: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for ore in tree.get_nodes_in_group("ore_nodes"):
		if not is_instance_valid(ore) or not ore.has_method("bounce"):
			continue
		if pos.distance_to(ore.global_position) <= radius:
			ore.bounce()
	for piece in tree.get_nodes_in_group("ore_pieces"):
		if not is_instance_valid(piece) or not piece.has_method("bounce"):
			continue
		if pos.distance_to(piece.global_position) <= radius:
			piece.bounce()

# Arena-wide -- every ore node/piece currently in the scene hops, matching
# the same "applying to the whole arena" scope Boulder Roll's own player
# knockup already uses for this specific landing.
func _bounce_all_ore() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for ore in tree.get_nodes_in_group("ore_nodes"):
		if is_instance_valid(ore) and ore.has_method("bounce"):
			ore.bounce()
	for piece in tree.get_nodes_in_group("ore_pieces"):
		if is_instance_valid(piece) and piece.has_method("bounce"):
			piece.bounce()

# ── Boulder Roll ──────────────────────────────────────────────────────────
# Curls up (tint swap, no new sprite -- same placeholder-art convention his
# own base body already uses) and rolls the full arena floor 3 end-to-end
# passes, reversing at each wall. Deals continuous contact damage to Elana
# while rolling (the actual hazard of the attack), plus camera shake and a
# knockup if she's near the wall at the moment of each bounce. Stays
# wherever the 3rd pass ends -- 2026-08-24, user correction: "the middle
# thing i said is just the starting position," not something he snaps back
# to after every attack. This is the one attack that ever moves him.
func _do_boulder_roll() -> void:
	_is_attacking = true
	_is_rolling = true
	_boulder_jump_pending_landing = false
	_body_visual.color = BOULDER_TINT
	var range: Vector2 = _get_arena_x_range()
	var roll_dir: int = 1 if global_position.x <= (range.x + range.y) / 2.0 else -1
	for pass_i in boulder_roll_passes:
		var target_x: float = range.y if roll_dir == 1 else range.x
		velocity.x = boulder_roll_speed * roll_dir
		# Bounces off whichever comes first: the virtual arena-bounds edge, OR
		# real physical wall contact (is_on_wall(), set by _physics_process()'s
		# own move_and_slide() each frame) -- the arena-bounds box is purely
		# geometric (no collision of its own, see TwinsArenaBounds in
		# full_map.tscn), so if the actual terrain wall stops him even
		# slightly short of target_x, waiting on distance alone would leave
		# him wedged against the wall forever, never closing to within the
		# 4.0 tolerance.
		while is_instance_valid(self) and is_inside_tree() and abs(global_position.x - target_x) > 4.0:
			await get_tree().physics_frame
			if not is_instance_valid(self) or not is_inside_tree():
				return
			_tick_boulder_contact_damage()
			_tick_boulder_jump_landing()
			if is_on_wall():
				break
			velocity.x = boulder_roll_speed * roll_dir
		if not is_instance_valid(self) or not is_inside_tree():
			return
		velocity.x = 0.0
		_on_boulder_wall_hit()
		roll_dir *= -1
	_is_rolling = false
	_body_visual.color = original_color
	# Stays wherever the 3rd pass left him -- "stationary in the middle of
	# the arena" was only ever describing his spawn point, not something to
	# snap back to after every attack (2026-08-24, user correction).
	_post_attack_pause_timer = post_attack_rest_duration
	_is_attacking = false

func _tick_boulder_contact_damage() -> void:
	if _boulder_hit_cooldown_timer > 0.0:
		_boulder_hit_cooldown_timer -= get_physics_process_delta_time()
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var elana = tree.get_first_node_in_group("player")
	if elana == null:
		return
	if global_position.distance_to(elana.global_position) <= boulder_roll_contact_radius:
		if elana.has_method("take_damage"):
			elana.take_damage(boulder_roll_contact_damage, false, self)
		if elana.has_method("apply_knockback"):
			var away: float = sign(elana.global_position.x - global_position.x)
			elana.apply_knockback(Vector2(away * boulder_roll_contact_knockback, boulder_roll_contact_knockup), boulder_roll_contact_knockback_duration)
		_boulder_hit_cooldown_timer = 0.4

# Checked EVERY frame regardless of _boulder_jump_pending_landing's most
# recent value -- by the time this runs, at least one full physics frame
# (including _physics_process()'s own move_and_slide()) has elapsed since
# the jump was launched (see trigger_boulder_roll_spike_jump() below), so
# is_on_floor() correctly reflects whether he's actually airborne yet
# rather than a stale pre-jump grounded state.
#
# Timeout safety net (2026-08-24, bug found via user report: "for the
# tailspike on the ground. sometimes graniteus jumps. sometimes no") --
# if is_on_floor() ever misses the actual landing frame for any reason,
# this flag used to stay stuck true for the rest of the roll. 1.5s
# comfortably covers the real ~0.86s flight time a 420 launch speed gives
# under standard gravity, so this only ever fires as a fallback, not on a
# normal jump.
func _tick_boulder_jump_landing() -> void:
	if not _boulder_jump_pending_landing:
		return
	_boulder_jump_landing_timeout -= get_physics_process_delta_time()
	if is_on_floor() or _boulder_jump_landing_timeout <= 0.0:
		_boulder_jump_pending_landing = false
		_bounce_all_ore()
		var tree: SceneTree = get_tree()
		if tree == null:
			return
		var elana = tree.get_first_node_in_group("player")
		if elana and elana.has_method("apply_knockback"):
			elana.apply_knockback(Vector2(0.0, boulder_roll_jump_arena_knockup), boulder_roll_jump_arena_knockup_duration)

# Called by wyrmbat_tailspike.gd's own _on_body_entered() the instant his
# REAL collision shape touches a PINNED spike -- real touch, not a
# distance guess (2026-08-24, user: "it should touch the spike to trigger
# the jump"). Only actually triggers while he's mid Boulder Roll -- merely
# touching a pinned spike some other time (e.g. resting/chasing) does
# nothing and leaves the spike alone. Returns true when it actually fired,
# so the spike knows whether to consume itself.
#
# Chains naturally through a cluster of close-together spikes: each new
# contact just re-launches velocity.y (extending the pending-landing
# window via the timeout below), so a run of several spikes reads as one
# continuous bounce rather than stopping after the first. The one
# arena-wide knockup still only fires once, when he actually lands for
# real after the last spike in the chain (see _tick_boulder_jump_landing()).
func trigger_boulder_roll_spike_jump() -> bool:
	if not _is_rolling:
		return false
	velocity.y = -boulder_roll_jump_launch_speed
	_boulder_jump_pending_landing = true
	_boulder_jump_landing_timeout = 1.5
	return true

func _on_boulder_wall_hit() -> void:
	_bounce_nearby_ore(global_position, boulder_roll_wall_knockup_radius)
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var elana = tree.get_first_node_in_group("player")
	if elana == null:
		return
	if elana.has_method("add_camera_trauma"):
		elana.add_camera_trauma(boulder_roll_camera_shake)
	if global_position.distance_to(elana.global_position) <= boulder_roll_wall_knockup_radius:
		if elana.has_method("apply_knockback"):
			elana.apply_knockback(Vector2(0.0, boulder_roll_wall_knockup), 0.4)

# ── Boulder Hurl ──────────────────────────────────────────────────────────
# 3 consecutive angled throws at Elana's position (sampled fresh per throw,
# not homing), 0.5s apart -- same ballistic-arc math cobblecroak.gd's own
# Leap Drop uses (peak height -> launch velocity -> flight time), see
# graniteus_boulder.gd. Each breaks and spills real ore1-4 pieces on
# landing (2026-08-24, user explicit: "Real ore items").
func _do_boulder_hurl() -> void:
	_is_attacking = true
	for i in boulder_hurl_count:
		if not is_instance_valid(self) or not is_inside_tree() or target == null:
			break
		var boulder = BOULDER_SCENE.instantiate()
		boulder.global_position = global_position
		boulder.target_position = target.global_position
		boulder.peak_height = boulder_hurl_peak_height
		boulder.damage = boulder_hurl_damage
		get_tree().current_scene.add_child(boulder)
		await get_tree().create_timer(boulder_hurl_interval).timeout
	if is_instance_valid(self) and is_inside_tree():
		_post_attack_pause_timer = post_attack_rest_duration
		_is_attacking = false

func _update_hp_bar() -> void:
	_hp_fill.size.x = clamp(hp / float(max_hp), 0.0, 1.0) * _hp_bg.size.x
	_hp_bar.visible = GameData.show_hp_bars and hp < max_hp

# Shows Rock Shield (2026-08-24, user: "show graniteus rock armor too") --
# same gold shield-bar visual just added to Wyrmbat, stacked above his own
# HP bar. Filled relative to the shield's own cap (rock_shield_amount_pct
# of max_hp), not max_hp itself, same reasoning as Wyrmbat's version.
func _update_shield_bar() -> void:
	var cap: float = float(max_hp) * rock_shield_amount_pct
	_shield_fill.size.x = clamp(_rock_shield_hp / cap, 0.0, 1.0) * _shield_bg.size.x if cap > 0.0 else 0.0
	_shield_bar.visible = GameData.show_hp_bars and _rock_shield_hp > 0.0

# Chain Claw's Yank writes directly to is_stunned/_pending_knockback --
# neither declared here (extends CharacterBody2D directly, no base_enemy.gd
# fields) -- same "too big/boss-tier" call Hollowfang/Elemander/Broodspawner
# already make, and same fix as wyrmbat.gd just got (2026-08-24, user
# report/confirmation). chain_projectile.gd's own blocks_chain_pull() check
# now reverses the pull (Elana yanked to him instead) rather than the
# grapple just silently latching on and never actually pulling anything.
func blocks_chain_pull() -> bool:
	return true

func apply_boss_damage(damage: int) -> void:
	if hp <= 0:
		return
	var remaining: float = float(damage)
	if _rock_shield_hp > 0.0:
		var absorbed: float = min(_rock_shield_hp, remaining)
		_rock_shield_hp -= absorbed
		remaining -= absorbed
	if remaining > 0.0:
		hp -= remaining
	GameData.spawn_crit_aware_damage_number(damage, global_position)
	_flash_hit()
	if hp <= 0:
		_die()

func _flash_hit() -> void:
	_body_visual.color = Color.RED
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		_body_visual.color = BOULDER_TINT if _is_rolling else original_color

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0 or _state == State.ROCK:
		return
	var final_damage: int = GameData.calc_damage(float(damage), float(defense))
	apply_boss_damage(final_damage)

func _get_element_mult(element: String) -> float:
	match element:
		"fire":
			return fire_resist
		"frost":
			return frost_resist
		"elec":
			return elec_resist
	return 1.0

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	var mult: float = _get_element_mult(element)
	if mult <= 0.0:
		return  # fully immune (electric) -- no damage, no flash/shield-absorb, matches hit_handler.gd's own immune early-return
	on_hit(hit_direction, max(1, int(round(float(damage) * mult))), true, attacker)

func on_plunge_hit(attacker: Node, hit_direction: int, damage: int) -> bool:
	on_hit(hit_direction, damage, false, attacker)
	return true

func _die() -> void:
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	GameData.gain_xp(xp_reward)
	queue_free()
