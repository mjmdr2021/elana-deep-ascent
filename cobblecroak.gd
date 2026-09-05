extends CharacterBody2D

# Cobblecroak -- mini-boss #4 (stone/leap frog, sticky tongue), 2026-08-23.
# Renamed from "Cobblehop" same day, user explicit: "make rest of
# cobblecroak. yeah rename." -- ties in the Croak attack (still to come)
# alongside the stone/leap theme the original name only covered half of.
# Base creature only for this pass -- user explicit: "do base frog first. no
# attacks yet. lets do everything one by one this time. so code is clean as
# we go." Chase movement, hp/damage/knockback, and the two blanket
# immunities (weapon stun, Chain Claw pull) land now; Leap Drop, Tongue
# Pull, Croak, and Hibernate all come in later passes, one at a time, once
# this base is confirmed working.
#
# extends CharacterBody2D directly, not enemy.gd -- same "too different a
# shape for the generic melee cycle" call Broodspawner/Hollowfang/Elemander
# already made (see broodspawner.gd's own header) -- every attack coming
# later is a named special, no ordinary AttackZone melee at all.
#
# Own on_hit()/on_elemental_hit() (bypasses hit_handler.gd entirely, same as
# Broodspawner) -- needed to actually enforce "cannot be stunned by any
# weapon" (hit_handler.gd unconditionally sets is_stunned on every hit) and
# to scale down incoming knockback (see KNOCKBACK_SCALE below).

@export var max_hp: int = 3000
@export var defense: int = 200
@export var xp_reward: int = 200

# Same convention base_enemy.gd's own fire_resist/frost_resist/elec_resist
# exports use (1.0 = normal, <1.0 = resistant, 0.0 = fully immune) --
# extends CharacterBody2D directly rather than base_enemy.gd (see header)
# so this doesn't come for free, applied in on_elemental_hit() below.
# 2026-08-25, user explicit: "have frost resistance of 75% and fire resist
# of 75%" -- elec left at normal (1.0), not mentioned.
@export_group("Elemental Resistance")
@export var fire_resist: float = 0.25
@export var frost_resist: float = 0.25
@export var elec_resist: float = 1.0

@export_group("Movement")
@export var chase_speed: float = 60.0
@export var chase_stop_distance: float = 60.0

# Leap Drop (2026-08-23, first attack pass; retuned same day -- user: "make
# cobblehop leap on elans position the time hope is triggered. the further
# elana is, the higher the jump. the longer the rain of rocks is.") -- a real
# ballistic aim at Elana's exact position, sampled once the instant the leap
# triggers (not homing -- she can still dodge by moving after liftoff, same
# "telegraphed, not tracking" fairness every other ranged attack in this
# codebase follows). _do_leap_drop() solves the launch velocity itself: pick
# a peak height that scales with horizontal distance (leap_drop_base_height
# + leap_drop_height_per_distance per px, capped at leap_drop_max_height),
# derive the vertical launch speed from that height (v = sqrt(2*g*h)), derive
# flight time from THAT (t = 2v/g, symmetric rise+fall to the same height),
# then divide the horizontal distance by that flight time for the horizontal
# speed -- so a farther leap is both a higher arc AND automatically still
# lands on the same spot instead of overshooting/undershooting. Real gravity
# (already running every frame via _apply_gravity(), untouched by this)
# carries the actual fall -- no scripted descent, matching the user's
# original framing ("leaps then lets gravity drop it down"). No range gate,
# no windup -- selection/pacing is entirely owned by the attack rotation now
# (see ATTACK_ROTATION below), not a per-attack cooldown of its own. Lands
# with a vertical knockup + AoE damage, then kicks off a Rain of Rocks
# window (see the export group below) that ALSO scales with the same leap
# distance.
@export_group("Leap Drop")
@export var leap_drop_enabled: bool = true
@export var leap_drop_base_height: float = 80.0
@export var leap_drop_height_per_distance: float = 0.15
# Lessened by almost half (2026-08-23, user explicit: "max height too high.
# lessen by almost half") -- was 400.0.
@export var leap_drop_max_height: float = 220.0
@export var leap_drop_landing_damage: int = 25
# The knockup weakens the farther she was when the leap launched (2026-08-23,
# user explicit: "lessen the knock up distance upwards the further away
# elana is from the jump") -- opposite scaling from the arc height above:
# a long-range leap arcs higher to reach her, but hits softer on landing.
# leap_drop_landing_knockup_base is the full-strength value at (near) zero
# distance; leap_drop_landing_knockup_reduction_per_distance eats into it per
# px of leap distance, clamped so it never weakens past
# leap_drop_landing_knockup_min or flips sign (see _apply_leap_landing_impact()).
@export var leap_drop_landing_knockup_base: float = -550.0
@export var leap_drop_landing_knockup_reduction_per_distance: float = 0.35
@export var leap_drop_landing_knockup_min: float = -150.0
@export var leap_drop_landing_radius: float = 180.0

# Tongue Pull (2026-08-23, second attack pass) -- user's own exact spec:
# "stretches tongue straight forward and if hits elana, pulls her and eats
# her doing dps until spat out, to make frog spit out elana, elana must
# attack inside the frog with a threshold of 8 attacks or does fire blast
# (fire element heavy attack). the spit throws elana out 200px away. if
# tongue pull didnt hit elana, tongue will stick to wall and frog will be
# pulled to wall and be stunned, will also cause the rain of rocks. same
# duration." A single forward RayCast2D (TongueRay, collision_mask 3 =
# terrain|player) does double duty: hits Elana -> grab; hits terrain instead
# -> wall-stick; hits nothing within range -> clean miss, just retracts (no
# spec given for that case, kept simple). A pure horizontal ray also
# naturally encodes "must be roughly level with her" for free -- no extra
# vertical-tolerance check needed, it just won't hit her if she's not
# in line.
@export_group("Tongue Pull")
@export var tongue_pull_enabled: bool = true
# Effectively unlimited (2026-08-23, user: "make the tile go on as long til
# it hits a wall or elana") -- was a real 320px cap (20 tiles); TongueRay
# already stops at whatever it actually collides with regardless of how far
# target_position reaches, so this is just "far enough to never be the
# thing that runs out first" rather than a real gameplay range anymore.
@export var tongue_pull_range: float = 3000.0
# How far the visual tongue stretches during the windup, before the raycast
# has actually resolved (see _do_tongue_pull()'s own comment).
@export var tongue_pull_windup_preview_length: float = 80.0
@export var tongue_pull_windup: float = 0.3
# How long the drag-in (grab) or the self-pull-to-wall (miss) takes.
@export var tongue_pull_pull_duration: float = 0.4
# % of Elana's OWN max_hp per tick (2026-08-23, user's explicit choice via
# AskUserQuestion: "% of Elana's max HP per tick") -- reads GameData.max_hp
# directly, not this boss's own stats.
@export var tongue_pull_eaten_pct_per_tick: float = 0.02
@export var tongue_pull_eaten_tick_interval: float = 0.5
@export var tongue_pull_hits_to_escape: int = 8
@export var tongue_pull_spit_distance: float = 200.0
@export var tongue_pull_spit_duration: float = 0.3
# Where the grab holds her, relative to his own position/facing. X zeroed
# 2026-08-23 (user: "move elana in the middle of cc. he is eating elana
# yknow" -- was 60, holding her out in front of his mouth instead of
# visually swallowed at his own center). Y raised 12 -> 20.5 + a small 3.5px
# embed margin = 24.0 the same day (user: "still not releasing the attack
# when inside belly of cc") -- root cause: Fire Blast (herbElementalFire)
# requires is_on_floor() to actually fire, holding as "pending" and waiting
# for a landing otherwise (see elana.gd's needs_ground handling) -- at y=12
# her own collision box (23 tall, centered on her origin, same as his own
# convention) was floating well above his real floor line (his own 64-tall
# box's bottom = his origin +32), so she could never actually land while
# held and the pending cast never fired. This Y places her feet AT (plus a
# small embed for safety margin) his own floor line instead, so her own
# move_and_slide() genuinely detects floor contact every frame she's pinned
# here, same as if she were standing on real ground.
@export var tongue_pull_mouth_offset: Vector2 = Vector2(0.0, 24.0)
@export var tongue_pull_miss_stuck_duration: float = 2.0
# Keeps his own collision shape from embedding into the wall he sticks to.
@export var tongue_pull_wall_stick_gap: float = 56.0

# Croak (2026-08-23, third attack pass; corrected same day -- user: "when
# did i agree on that number. i thought i said croak and dont stop until
# stopped by freeze or shock" -- the original croak_duration timeout was
# never actually part of the spec, my own invented default. Removed: no
# time cap at all now, matching the real original spec verbatim -- "to stop
# croaking, needs to shock or freeze the mini boss"). Roots in place,
# channels indefinitely, still fully damageable throughout (nothing blocks
# on_hit()/on_elemental_hit() from working during an attack, only his own
# movement -- true for free, no extra code needed), fires Rain of Rocks
# around himself for as long as the channel keeps running -- "the longer
# the croak, the more rocks fall" is just a natural consequence of an
# open-ended channel now, not a separate mechanic. Each individual "croak"
# pulse (one at the start, then every croak_pulse_interval) briefly stuns
# Elana if she's in range. Only stops via a lucky frost-freeze roll (see
# on_elemental_hit()) -- Shock doesn't exist as an enemy-facing status yet,
# so it can't stop this yet either, per the user's own note -- or via the
# shared Hibernate HP threshold below.
@export_group("Croak")
@export var croak_enabled: bool = true
@export var croak_pulse_interval: float = 1.0
@export var croak_stun_radius: float = 200.0
@export var croak_stun_duration: float = 0.2
# More rocks per wave the longer the channel runs (2026-08-23, user
# explicit: "not accelarating. increasing in numbers!" -- corrects an
# earlier wrong guess that shrank the spawn INTERVAL instead). The interval
# itself stays fixed at rain_of_rocks_spawn_interval (0.3s, same as every
# other Rain of Rocks window) -- what grows is how many rocks spawn at once
# each tick: 1 to start, +1 more every croak_rock_count_growth_interval
# seconds of channel time.
@export var croak_rock_count_growth_interval: float = 2.0
# Third way out, alongside the frost-freeze roll and the Hibernate
# threshold (2026-08-23, user explicit: "make croak also stop croaking if
# reached a damage threshold. if get damaged by 350 hp during the duration
# of croak. stops croaking.") -- tracked in apply_boss_damage() (see its
# own comment), reset fresh at the start of every _do_croak().
@export var croak_damage_threshold: int = 350
# Shared with the not-yet-built Hibernate attack (same 20% value from its
# own spec) -- Croak checks this every tick so a channel that was already
# running when HP crosses the threshold cuts short instead of running its
# full duration and blocking Hibernate from taking over once it exists
# (user explicit: "stops croak if reached hybernation threshold since itll
# do hybernation"). Hibernate itself will read this same export once built,
# rather than each attack carrying its own separate copy of the number.
@export var hibernate_hp_threshold_pct: float = 0.20

# Hibernate (2026-08-23, fourth and final attack pass) -- user's own spec:
# "becomes a rock, and when a rock, regens 1% hp per second. cannot be
# damaged. lasts until hp is full." Triggers automatically (preempts
# ATTACK_ROTATION entirely, checked in _tick_attack_rotation() BEFORE the
# rotation itself, and doesn't require a target -- healing when critically
# low shouldn't need Elana in aggro range) the instant HP crosses
# hibernate_hp_threshold_pct, gated by hibernate_cooldown_duration (100s,
# user's own exact spec) so it can't immediately re-trigger. Ends either
# naturally at full HP, or early from a warhammer heavy hit -- per the
# earlier AskUserQuestion resolution ("Lower the break threshold to match
# real warhammer knockback"), a real unquartered warhammer heavy hit only
# reaches ~34px under this game's gravity anyway (nowhere near the
# original "~50px" guess), so the break condition is simply "was hit by a
# warhammer heavy attack while hibernating" (checked directly in on_hit())
# rather than an actual simulated jump-height check -- the two coincide
# exactly at that calibration. That hit deals NO damage even though it
# breaks the hibernation -- "cannot be damaged" is absolute here, breaking
# it is a pure state change, not bonus damage on top of what regen already
# reversed.
@export_group("Hibernate")
@export var hibernate_enabled: bool = true
@export var hibernate_regen_pct_per_sec: float = 0.01
@export var hibernate_cooldown_duration: float = 100.0

# Shared "breather" between ANY of Cobblecroak's attacks (2026-08-23, user
# explicit: "make cobble rest for 1 second in between attacks") -- not
# Leap-Drop-specific despite living here for now; every future attack
# (Tongue Pull, Croak) sets this same timer on finishing, and
# _apply_movement() holds chase off while it's counting down, same "don't
# slide an attack straight into a walk" reason Broodspawner's own
# down_post_attack_pause exists. Bumped 1.0 -> 2.0 same day, alongside the
# rename (user: "to 2 seconds instead").
@export_group("Combat Pacing")
@export var post_attack_rest_duration: float = 2.0

# Rain of Rocks (2026-08-23) -- shared hazard, real falling projectiles
# (cobblecroak_rock.gd/.tscn, modeled on hollowfang_spike.gd's proximity-hit
# pattern) rather than a simple tick-damage zone, per the user's explicit
# choice. Three different callers, three different shapes: Leap Drop's
# landing and Tongue Pull's miss both call _start_rain_of_rocks() with a
# fixed/distance-scaled duration (rain_of_rocks_base_duration +
# rain_of_rocks_duration_per_distance per px, capped at
# rain_of_rocks_max_duration); Croak's channel is open-ended (no time cap
# at all, see its own export group) so it calls _spawn_rock() directly on
# its own timer instead, at this same rain_of_rocks_spawn_interval cadence,
# for as long as the channel keeps running.
@export_group("Rain of Rocks")
@export var rain_of_rocks_base_duration: float = 2.0
@export var rain_of_rocks_duration_per_distance: float = 0.0015
@export var rain_of_rocks_max_duration: float = 5.0
@export var rain_of_rocks_spawn_interval: float = 0.3
# Fallback only now (2026-08-23, user: "does it disperse to the whole
# arena" -- "ill adjust it" after choosing the real arena-aware option) --
# used as a fixed radius around wherever a rock spawn was triggered ONLY
# while arena_bounds_path (see the "Arena" export group below) isn't wired.
# Once it is, _spawn_rock() samples that shape's real width instead and
# this is never read.
@export var rain_of_rocks_radius: float = 140.0
@export var rain_of_rocks_spawn_height: float = 300.0
@export var rain_of_rocks_damage: int = 10

# Real arena bounds (2026-08-23) -- same "independent sibling placed
# directly in the level scene" convention broodspawner.gd's own
# arena_box_path already uses, not a child of this scene. Wire this to a
# RectangleShape2D-shaped Area2D spanning the room's actual playable width
# once placed in a real level -- Rain of Rocks then spawns anywhere across
# that full width instead of a fixed radius around the trigger point,
# regardless of which attack (Leap Drop, Tongue Pull, Croak) caused it.
@export_group("Arena")
@export var arena_bounds_path: NodePath

const ROCK_SCENE: PackedScene = preload("res://cobblecroak_rock.tscn")

# Originally scaled ALL incoming knockback down (2026-08-23, user explicit:
# "also velocities of knockbacks and knockups are quarted. so it would look
# like mini boss is heavy af." -- then retuned: "quartered is a bit too
# much. just halve it") -- narrowed further, same day, to Hibernate only
# ("remove the halving of velocity of cc. and put it on when in hybernation
# only") -- normal-state hits now get full, unscaled knockback; only a
# "rock" being nudged during Hibernate uses this. See
# _apply_incoming_knockback()'s own comment for where it's actually applied.
# Never scales knockback Cobblecroak DEALS (Leap Drop's landing impact,
# etc.) either way.
const KNOCKBACK_SCALE: float = 0.5
# How long chase movement holds off after a hit to let the (small, scaled-
# down) knockback velocity actually play out instead of being overwritten
# the very next physics frame.
const KNOCKBACK_RECOVERY_TIME: float = 0.3

const CROAK_TINT: Color = Color(0.5, 0.75, 0.35, 1.0)
const HIBERNATE_TINT: Color = Color(0.55, 0.55, 0.6, 1.0)

var hp: float
var direction: int = 1
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var target: Node = null
var original_color: Color
var _knockback_timer: float = 0.0
# True for the duration of ANY attack -- liftoff through landing impact for
# Leap Drop, windup through grab/wall-stick resolution for Tongue Pull.
# _apply_movement() skips chase entirely while this is true (an attack's own
# velocity/position control needs to carry through untouched, instead of
# being overwritten by chase logic every tick), and _tick_attack_rotation()
# uses it to refuse starting a new attack mid-attack.
var _is_attacking: bool = false
# Holds chase off for a beat after any attack finishes, same "don't slide an
# attack straight into a walk" reason Broodspawner's own
# down_post_attack_pause exists.
var _post_attack_pause_timer: float = 0.0

# Round-robin attack selection (2026-08-23, added alongside Tongue Pull --
# replaces Leap Drop's own former per-attack cooldown entirely). No RNG --
# same "deterministic over rolled" preference this session's design settled
# on repeatedly for Broodspawner too.
enum Attack { LEAP_DROP, TONGUE_PULL, CROAK }
const ATTACK_ROTATION: Array = [Attack.LEAP_DROP, Attack.TONGUE_PULL, Attack.CROAK]
var _rotation_index: int = 0

# Tongue Pull grab state -- read/written by on_hit()/on_elemental_hit() so
# they can tell a landed hit apart from normal combat while she's actually
# being eaten (see _do_tongue_grab()).
var _is_grabbing_elana: bool = false
var _tongue_pull_hits_landed: int = 0
var _tongue_pull_release_requested: bool = false

# Croak state -- read by on_elemental_hit() so it can tell whether a frost
# hit landing right now should even attempt the interrupt roll.
var _is_croaking: bool = false
var _croak_interrupted: bool = false
var _croak_damage_taken: float = 0.0

# Hibernate state -- read by on_hit() to gate invulnerability/the break
# condition, and by _tick_attack_rotation() to know whether it's on
# cooldown before preempting the normal rotation.
var _is_hibernating: bool = false
var _hibernate_cooldown_timer: float = 0.0

@onready var _hp_bar: Node2D = $HPBar
@onready var _hp_bg: ColorRect = $HPBar/Background
@onready var _hp_fill: ColorRect = $HPBar/Fill
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
	$AggroZone.body_entered.connect(_on_aggro_zone_body_entered)
	$AggroZone.body_exited.connect(_on_aggro_zone_body_exited)
	if _arena_bounds == null:
		push_warning("Cobblecroak: arena_bounds_path not wired -- Rain of Rocks falls back to a fixed radius around wherever it's triggered instead of spanning the whole room.")

func _on_aggro_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		target = body

func _on_aggro_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		target = null

func _physics_process(delta: float) -> void:
	# Ticks in real time regardless of what he's doing (matches Broodspawner's
	# own poison_spit_cooldown_timer convention) -- set the instant
	# hibernation STARTS (see _do_hibernate()), so it's ready exactly
	# hibernate_cooldown_duration after that, not gated behind whatever
	# attack state he happens to be in and not reset by how it ends.
	if _hibernate_cooldown_timer > 0.0:
		_hibernate_cooldown_timer -= delta
	_apply_gravity(delta)
	_update_facing()
	_tick_attack_rotation(delta)
	_apply_movement(delta)
	_update_hp_bar()
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

func _update_facing() -> void:
	if target == null or _is_attacking:
		return
	direction = 1 if target.global_position.x >= global_position.x else -1
	_hurtbox.scale.x = direction

func _apply_movement(delta: float) -> void:
	if _is_attacking:
		return
	# Checked BEFORE _post_attack_pause_timer (2026-08-23 fix -- this was
	# the actual "no knockback" bug, not move_and_slide()/motion_mode at
	# all): the pause branch below unconditionally zeroes velocity.x and
	# returns every frame, which was silently swallowing an active
	# knockback whenever a hit landed while still resting from the last
	# attack (proven by the DEBUG logs never printing "KNOCKBACK ENDED" --
	# _knockback_timer was set but never reached its own decrement branch).
	# An active knockback now always wins over a leftover rest timer.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		if _knockback_timer <= 0.0:
			# Back to normal grounded movement now that the knockback window
			# is over -- see on_hit()'s own comment for why this got
			# switched to FLOATING in the first place.
			motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
		return
	if _post_attack_pause_timer > 0.0:
		_post_attack_pause_timer -= delta
		velocity.x = 0.0
		return
	if target == null:
		velocity.x = 0.0
		return
	var dist: float = abs(target.global_position.x - global_position.x)
	velocity.x = 0.0 if dist <= chase_stop_distance else chase_speed * direction

# Picks the next attack in ATTACK_ROTATION and starts it the instant she's
# grounded, aggro'd, not mid-attack, not mid-knockback, and not still resting
# from the last attack -- no per-attack cooldown of its own anymore, pacing
# is entirely owned by post_attack_rest_duration + the rotation itself.
# _knockback_timer guarded (2026-08-23 fix -- found while chasing "why isn't
# cc getting knocked back") so an attack launching the exact same frame a
# hit lands can't silently overwrite the knockback velocity on_hit() just
# set. A disabled attack's turn is silently skipped (rotation still
# advances) rather than cascading to the next one -- simplest safe behavior,
# nothing happens that tick if it's ever disabled, no infinite-recursion risk.
func _tick_attack_rotation(_delta: float) -> void:
	if _is_attacking or not is_on_floor() or _knockback_timer > 0.0 or _post_attack_pause_timer > 0.0:
		return
	# Hibernate preempts the rotation entirely (2026-08-23) -- checked here,
	# before the target-null return below, since healing when critically low
	# shouldn't require Elana to actually be in aggro range.
	if hibernate_enabled and _hibernate_cooldown_timer <= 0.0 and float(hp) / float(max_hp) <= hibernate_hp_threshold_pct:
		_do_hibernate()
		return
	if target == null:
		return
	# 2026-08-24, user: "only make Cobblecroak attack if elana is in its
	# arena" -- AggroZone (what actually sets target) can be a wider/
	# differently-shaped range than the real arena, so being aggro'd alone
	# isn't enough once arena_bounds_path is wired. Falls back to the old
	# aggro-only behavior if it isn't (same graceful-degradation convention
	# every other arena_bounds_path usage in this file already follows).
	if _arena_bounds != null and not _get_arena_rect().has_point(target.global_position):
		return
	var attack: int = ATTACK_ROTATION[_rotation_index]
	_rotation_index = (_rotation_index + 1) % ATTACK_ROTATION.size()
	match attack:
		Attack.LEAP_DROP:
			if leap_drop_enabled:
				_do_leap_drop()
		Attack.TONGUE_PULL:
			if tongue_pull_enabled:
				_do_tongue_pull()
		Attack.CROAK:
			if croak_enabled:
				_do_croak()

# Solves a real ballistic launch aimed at Elana's exact position (sampled
# once, right here -- not homing) then just waits (one physics_frame at a
# time) for is_on_floor() to go true again -- gravity and move_and_slide(),
# already running every frame regardless, do the actual arc entirely on
# their own; nothing here fights or overrides that. The one-frame await
# before the wait-loop starts is so the loop doesn't read this same frame's
# still-true is_on_floor() (set before liftoff) as an instant landing.
func _do_leap_drop() -> void:
	_is_attacking = true
	var dx: float = target.global_position.x - global_position.x
	if dx != 0.0:
		direction = 1 if dx > 0.0 else -1
	# Peak height scales with distance -- see the export group's own comment
	# for the full derivation (height -> vertical speed -> flight time ->
	# horizontal speed).
	var peak_height: float = clamp(leap_drop_base_height + leap_drop_height_per_distance * abs(dx), leap_drop_base_height, leap_drop_max_height)
	var launch_speed_y: float = sqrt(2.0 * gravity * peak_height)
	var flight_time: float = 2.0 * launch_speed_y / gravity
	var launch_speed_x: float = dx / flight_time
	velocity = Vector2(launch_speed_x, -launch_speed_y)
	await get_tree().physics_frame
	while is_instance_valid(self) and not is_on_floor():
		await get_tree().physics_frame
	if not is_instance_valid(self):
		return
	velocity.x = 0.0
	_apply_leap_landing_impact(abs(dx))
	var rain_duration: float = clamp(rain_of_rocks_base_duration + rain_of_rocks_duration_per_distance * abs(dx), rain_of_rocks_base_duration, rain_of_rocks_max_duration)
	_start_rain_of_rocks(global_position, rain_duration)
	_post_attack_pause_timer = post_attack_rest_duration
	_is_attacking = false

# leap_distance is the same horizontal distance _do_leap_drop() computed the
# arc from -- knockup weakens as it grows (see the export group's own
# comment for the full derivation), the opposite direction the arc height
# itself scales.
func _apply_leap_landing_impact(leap_distance: float) -> void:
	# Camera shake on every landing (2026-08-23, user explicit: "on the leap
	# drop add camera shake on landing") -- unconditional, not gated on
	# actually hitting Elana below (a slam this size should shake the screen
	# even if she's out of range/dodged it).
	_shake_player_camera(0.5)
	# 2026-08-25, real bug found via code review: clamp()'s min/max args were
	# passed as (leap_drop_landing_knockup_min, leap_drop_landing_knockup_base)
	# -- min=-150 is numerically GREATER than max=-550, inverting the whole
	# distance-falloff curve (a close-range landing, meant to be full-strength
	# -550, clamped down to the weak -150 instead, and vice versa for a long
	# leap). base is the true numeric minimum (most negative/strongest); min
	# is the true numeric maximum (least negative/weakest) -- swapped here to
	# match.
	var knockup: float = clamp(leap_drop_landing_knockup_base + leap_drop_landing_knockup_reduction_per_distance * leap_distance, leap_drop_landing_knockup_base, leap_drop_landing_knockup_min)
	for body in _nearby_bodies(leap_drop_landing_radius):
		# Only lands if Elana's actually grounded at the moment of impact
		# (2026-08-23, user explicit: "only apply the knockup dmg and knock
		# up on leap drop only when she is touching floor") -- a ground-slam
		# shockwave shouldn't reach up and hit her while she's already
		# airborne (e.g. jumped over it), same real is_on_floor() every
		# CharacterBody2D exposes, not a made-up check.
		if body.is_in_group("player") and body.is_on_floor():
			if body.has_method("apply_knockback"):
				body.apply_knockback(Vector2(0.0, knockup), 0.4)
			if body.has_method("take_damage"):
				# Note: if Elana has Bulwark leveled (GameData.bulwark_pct),
				# this can synchronously reflect a % of this damage straight
				# back into our own on_hit() before take_damage() returns --
				# found 2026-08-23 while debugging an unrelated knockback
				# report (see [[backlog]]'s Cobblecroak entry). Not guarded
				# against here; working as designed.
				body.take_damage(leap_drop_landing_damage, false, self)

# Windup telegraph, then a single forward raycast decides the whole
# attack's shape -- see the export group's own comment for the 3-way split
# (hit Elana / hit terrain / hit nothing). Re-cast fresh AFTER the windup
# (not before) so the telegraph is a real dodge window, not just a visual.
# The visual starts at a short preview length (tongue_pull_range itself is
# effectively unlimited now, see its own comment -- drawing the full length
# during windup, before the ray's even been cast, would stretch way past
# wherever it actually ends up hitting) and gets resized to the real hit
# distance the instant the raycast resolves.
func _do_tongue_pull() -> void:
	_is_attacking = true
	var visual: Line2D = _spawn_tongue_visual(tongue_pull_windup_preview_length)
	await get_tree().create_timer(tongue_pull_windup).timeout
	if not is_instance_valid(self):
		return
	$TongueRay.target_position = Vector2(tongue_pull_range * direction, 0.0)
	$TongueRay.force_raycast_update()
	var reach: float = tongue_pull_range
	if $TongueRay.is_colliding():
		reach = $TongueRay.global_position.distance_to($TongueRay.get_collision_point())
	if is_instance_valid(visual):
		visual.points = PackedVector2Array([Vector2.ZERO, Vector2(reach * direction, 0.0)])
	# Ownership of `visual` passes to whichever branch fires below -- both
	# now shrink it to match the live pull distance each frame and free it
	# the instant the pull actually finishes (arrival at the mouth, or at
	# the wall), instead of it sitting there at its original resolved length
	# for the whole rest of the attack (2026-08-23, user: "tongue doesnt
	# disappear on pull. it should match distance of elana when on pull").
	if $TongueRay.is_colliding() and $TongueRay.get_collider().is_in_group("player"):
		await _do_tongue_grab($TongueRay.get_collider(), visual)
	elif $TongueRay.is_colliding():
		await _do_tongue_wall_stick($TongueRay.get_collision_point(), visual)
	elif is_instance_valid(visual):
		visual.queue_free()
	if is_instance_valid(self):
		_post_attack_pause_timer = post_attack_rest_duration
		_is_attacking = false

# Purely cosmetic, no collision role -- same "spawn a Line2D child, no real
# scene node" convention broodspawner.gd's own Web Pull uses.
func _spawn_tongue_visual(length: float) -> Line2D:
	var line := Line2D.new()
	# Fattened 6.0 -> 14.0 (2026-08-23, user explicit: "make tongue fatter").
	line.width = 14.0
	line.default_color = Color(0.75, 0.3, 0.4, 1.0)
	line.position = $TongueRay.position
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(length * direction, 0.0)])
	add_child(line)
	return line

# Drags Elana in, THEN -- critically -- stops stunning her (2026-08-23 fix,
# user: "fire blast doesnt spit elana out"). Every prior version kept
# calling apply_stun() every tick to hold her in place, but is_stunned
# blocks her own attack INPUT in elana.gd -- she could never actually swing
# at him while grabbed, so neither escape condition (8 real hits, or a fire-
# heavy hit) was ever reachable through her own actions, only through
# Bulwark's automatic reflects off the eaten-tick damage (no input needed
# for those). Position is now pinned every physics frame instead (not just
# once per damage-tick) purely by overwriting global_position -- that alone
# is enough to stop her leaving; it doesn't touch is_stunned/input at all,
# so she's free to actually fight back the whole time she's held. Damage
# still only ticks once per tongue_pull_eaten_tick_interval, tracked with a
# running accumulator since the loop itself now runs every frame.
func _do_tongue_grab(elana: Node, visual: Line2D) -> void:
	var mouth_pos: Vector2 = global_position + Vector2(tongue_pull_mouth_offset.x * direction, tongue_pull_mouth_offset.y)
	if elana.has_method("apply_drag_stun"):
		elana.apply_drag_stun(mouth_pos, tongue_pull_pull_duration, tongue_pull_pull_duration)
	# Tongue visually shrinks to match her REAL current distance every frame
	# while she's actually being reeled in (not the distance at the moment
	# she was first hit), then disappears the instant she arrives -- it no
	# longer sits stretched out to its original length for the whole eating
	# duration afterward.
	var pull_elapsed: float = 0.0
	while pull_elapsed < tongue_pull_pull_duration and is_instance_valid(self) and is_instance_valid(elana):
		if is_instance_valid(visual):
			var dist: float = $TongueRay.global_position.distance_to(elana.global_position)
			visual.points = PackedVector2Array([Vector2.ZERO, Vector2(dist * direction, 0.0)])
		await get_tree().physics_frame
		pull_elapsed += get_physics_process_delta_time()
	if is_instance_valid(visual):
		visual.queue_free()
	if not is_instance_valid(self) or not is_instance_valid(elana):
		return
	_tongue_pull_hits_landed = 0
	_tongue_pull_release_requested = false
	_is_grabbing_elana = true
	var tick_elapsed: float = 0.0
	while is_instance_valid(self) and is_instance_valid(elana) \
			and _tongue_pull_hits_landed < tongue_pull_hits_to_escape \
			and not _tongue_pull_release_requested:
		elana.global_position = mouth_pos
		if "velocity" in elana:
			elana.velocity = Vector2.ZERO
		tick_elapsed += get_physics_process_delta_time()
		if tick_elapsed >= tongue_pull_eaten_tick_interval:
			tick_elapsed -= tongue_pull_eaten_tick_interval
			if elana.has_method("take_damage"):
				elana.take_damage(max(1, int(GameData.max_hp * tongue_pull_eaten_pct_per_tick)), false, self)
		await get_tree().physics_frame
	_is_grabbing_elana = false
	if is_instance_valid(self) and is_instance_valid(elana):
		_spit_out(elana)

# Ends the grab (clears her stun directly -- same "reach into the player
# node's own fields" pattern chain_projectile.gd's pull already uses) and
# throws her tongue_pull_spit_distance further in the SAME direction she was
# pulled (continuing outward past the mouth, not back into him).
func _spit_out(elana: Node) -> void:
	elana.is_stunned = false
	elana.stun_timer = 0.0
	if elana.has_method("apply_knockback"):
		var speed: float = tongue_pull_spit_distance / tongue_pull_spit_duration
		elana.apply_knockback(Vector2(direction * speed, -100.0), tongue_pull_spit_duration, true)

# Miss case -- pulls HIMSELF to the wall he hit instead (a Tween over the
# same pull_duration as the grab, for symmetry) and sits rooted there
# (_is_attacking stays true the whole time, blocking chase/rotation the same
# way it already does for every other attack -- no separate "stunned" flag
# needed, this isn't weapon-inflicted so his stun-immunity doesn't apply or
# need to be worked around). Rain of Rocks fires around his own final
# position once he arrives. Camera shakes on impact and a stun-stars
# indicator shows for the whole stuck window (2026-08-23, user explicit:
# "when toung pull and cc hits wall, make the camera shake too" / "when
# stunned. show the stars") -- GameData.make_stun_indicator() is the same
# "★★★" label hit_handler.gd's own weapon-stun already uses, reused here
# rather than a new visual, even though this isn't the weapon-stun system
# (see the comment above about why -- this is purely visual, doesn't touch
# is_stunned/his own stun-immunity).
func _do_tongue_wall_stick(wall_point: Vector2, visual: Line2D) -> void:
	var target_pos: Vector2 = wall_point - Vector2(tongue_pull_wall_stick_gap * direction, 0.0)
	var tween := create_tween()
	tween.tween_property(self, "global_position", target_pos, tongue_pull_pull_duration)
	# Same live-shrink-then-disappear treatment as the grab case -- he's the
	# one moving here (toward the fixed wall_point), so the tongue tracks
	# HIS shrinking distance to it instead of Elana's.
	while tween.is_running():
		if is_instance_valid(visual):
			var dist: float = $TongueRay.global_position.distance_to(wall_point)
			visual.points = PackedVector2Array([Vector2.ZERO, Vector2(dist * direction, 0.0)])
		await get_tree().physics_frame
	if is_instance_valid(visual):
		visual.queue_free()
	if not is_instance_valid(self):
		return
	_shake_player_camera(0.4)
	var stun_indicator: Label = GameData.make_stun_indicator()
	add_child(stun_indicator)
	_start_rain_of_rocks(global_position, tongue_pull_miss_stuck_duration)
	await get_tree().create_timer(tongue_pull_miss_stuck_duration).timeout
	if is_instance_valid(stun_indicator):
		stun_indicator.queue_free()

# Shared by Leap Drop's landing and Tongue Pull's wall-hit -- add_camera_
# trauma() is a public method on Elana herself (elana.gd), not a global, so
# this reaches through the player group the same way every other cross-
# script call in this file already does.
func _shake_player_camera(amount: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_camera_trauma"):
		player.add_camera_trauma(amount)

# Roots in place (_is_attacking blocks chase the same as every other attack,
# nothing extra needed) and channels INDEFINITELY -- no time cap (2026-08-23
# correction, see the export group's own comment) -- pulsing a brief
# Elana-stun (see _croak_pulse()) once at the start and again every
# croak_pulse_interval, and spawning rocks around himself for as long as the
# channel keeps running, at the same fixed rain_of_rocks_spawn_interval
# every other Rain of Rocks window uses -- but MORE rocks land each wave the
# longer it goes (see croak_rock_count_growth_interval), not a faster rate,
# so it's a real reason not to let this drag on. Three ways out: a lucky
# frost hit (see on_elemental_hit()), taking croak_damage_threshold total
# damage during the channel (350, tracked in apply_boss_damage() -- user
# explicit: "if get damaged by 350 hp during the duration of croak. stops
# croaking."), or dropping to the Hibernate HP threshold (2026-08-23, user:
# "stops croak if reached hybernation threshold since itll do hybernation")
# -- Hibernate itself doesn't exist yet at the time this was written, so
# this just frees him up sooner once it does, rather than actually handing
# off to it here.
func _do_croak() -> void:
	_is_attacking = true
	_is_croaking = true
	_croak_interrupted = false
	_croak_damage_taken = 0.0
	_body_visual.color = CROAK_TINT
	_croak_pulse()
	var elapsed: float = 0.0
	var pulse_timer: float = 0.0
	var rock_timer: float = 0.0
	while is_instance_valid(self) and not _croak_interrupted \
			and _croak_damage_taken < croak_damage_threshold \
			and float(hp) / float(max_hp) > hibernate_hp_threshold_pct:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		pulse_timer += delta
		if pulse_timer >= croak_pulse_interval:
			pulse_timer -= croak_pulse_interval
			_croak_pulse()
		rock_timer += delta
		if rock_timer >= rain_of_rocks_spawn_interval:
			rock_timer -= rain_of_rocks_spawn_interval
			var rock_count: int = 1 + int(elapsed / croak_rock_count_growth_interval)
			for _i in rock_count:
				_spawn_rock(global_position)
	_is_croaking = false
	if is_instance_valid(self):
		_body_visual.color = original_color
		_post_attack_pause_timer = post_attack_rest_duration
		_is_attacking = false

# Each individual "croak" -- briefly stuns Elana if she's in range
# (2026-08-23, user explicit: "each croak is going to stun elana for 0.2
# seconds"). Reuses _nearby_bodies()'s same shape-query pattern every other
# AoE check in this file already uses.
func _croak_pulse() -> void:
	for body in _nearby_bodies(croak_stun_radius):
		if body.is_in_group("player") and body.has_method("apply_stun"):
			body.apply_stun(croak_stun_duration)

# Turns to stone: fully invulnerable (see on_hit()'s own gate) and rooted
# (_is_attacking blocks chase/rotation the same as every other attack),
# regenerating hibernate_regen_pct_per_sec of max_hp every frame until
# either full HP (natural end) or _is_hibernating gets flipped false from
# outside (the warhammer-break condition, set directly in on_hit()). The
# cooldown starts counting the instant hibernation STARTS, not when it ends
# (2026-08-23, user explicit: "cooldown starts as hybernation starts") --
# so a quick hammer-break doesn't reset the clock to a fresh 100s from
# whenever it happened to end; the cadence is consistent regardless of how
# (or how fast) any individual hibernation actually resolves.
func _do_hibernate() -> void:
	_is_attacking = true
	_is_hibernating = true
	_hibernate_cooldown_timer = hibernate_cooldown_duration
	_body_visual.color = HIBERNATE_TINT
	while is_instance_valid(self) and _is_hibernating and hp < float(max_hp):
		await get_tree().physics_frame
		hp = min(float(max_hp), hp + float(max_hp) * hibernate_regen_pct_per_sec * get_physics_process_delta_time())
	_is_hibernating = false
	if is_instance_valid(self):
		_body_visual.color = original_color
		_post_attack_pause_timer = post_attack_rest_duration
		_is_attacking = false

# Same shape-query pattern broodspawner.gd's own _nearby_bodies() uses for
# its landing-impact/knockback checks -- collision_mask 2 is the player's
# own physics layer (see elana.tscn's root collision_layer), not a group
# filter, so the is_in_group("player") check above still matters (nothing
# else is expected on that layer today, but this doesn't assume it).
func _nearby_bodies(radius: float) -> Array:
	var space = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.collision_mask = 2
	query.transform = Transform2D(0.0, global_position)
	var results: Array = []
	for hit in space.intersect_shape(query, 8):
		results.append(hit["collider"])
	return results

# Fire-and-forget -- deliberately not awaited by callers, so a 2s rain
# window doesn't hold up Leap Drop's own _is_attacking/cooldown resolution.
# Spawns one rock per rain_of_rocks_spawn_interval for the given duration
# total -- see _spawn_rock()'s own comment for where each rock actually
# lands (arena-wide once arena_bounds_path is wired, a fixed radius around
# center otherwise).
func _start_rain_of_rocks(center: Vector2, duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed < duration:
		_spawn_rock(center)
		await get_tree().create_timer(rain_of_rocks_spawn_interval).timeout
		if not is_instance_valid(self):
			return
		elapsed += rain_of_rocks_spawn_interval

# center only matters as a fallback (see rain_of_rocks_radius's own
# comment) -- once arena_bounds_path is wired, BOTH axes come from that real
# shape instead: X anywhere across its full width, Y from its own top edge
# (2026-08-23, user explicit: "spawn the rocks on the top of the arena
# inside it") rather than a flat rain_of_rocks_spawn_height offset above
# wherever the triggering attack happened.
# Used by _tick_attack_rotation()'s arena-gate (2026-08-24) -- same shape
# _spawn_rock() below already reads inline for Rain of Rocks, pulled out
# into a reusable helper.
func _get_arena_rect() -> Rect2:
	if _arena_bounds == null:
		return Rect2()
	var shape_node: CollisionShape2D = _arena_bounds.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Rect2()
	var rect: RectangleShape2D = shape_node.shape
	var center: Vector2 = _arena_bounds.global_position + shape_node.position
	return Rect2(center - rect.size / 2.0, rect.size)

func _spawn_rock(center: Vector2) -> void:
	var rock = ROCK_SCENE.instantiate()
	var spawn_x: float = center.x + randf_range(-rain_of_rocks_radius, rain_of_rocks_radius)
	var spawn_y: float = center.y - rain_of_rocks_spawn_height
	if _arena_bounds != null:
		var shape_node: CollisionShape2D = _arena_bounds.get_node_or_null("CollisionShape2D")
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var rect: RectangleShape2D = shape_node.shape
			var arena_center: Vector2 = _arena_bounds.global_position + shape_node.position
			var half_size: Vector2 = rect.size / 2.0
			spawn_x = randf_range(arena_center.x - half_size.x, arena_center.x + half_size.x)
			spawn_y = arena_center.y - half_size.y
	rock.global_position = Vector2(spawn_x, spawn_y)
	rock.damage = rain_of_rocks_damage
	get_tree().current_scene.add_child(rock)

func _update_hp_bar() -> void:
	_hp_fill.size.x = clamp(hp / float(max_hp), 0.0, 1.0) * _hp_bg.size.x
	_hp_bar.visible = GameData.show_hp_bars and hp < max_hp

func apply_boss_damage(damage: int) -> void:
	if hp <= 0:
		return
	hp -= damage
	# Croak's damage-threshold interrupt (2026-08-23, user explicit: "if get
	# damaged by 350 hp during the duration of croak. stops croaking.") --
	# accumulated here, the single choke-point for every actual HP loss,
	# rather than duplicated at each call site. Reset fresh at the start of
	# every _do_croak(), only ever adds up while _is_croaking is true.
	if _is_croaking:
		_croak_damage_taken += damage
	GameData.spawn_crit_aware_damage_number(damage, global_position)
	_flash_hit()
	if hp <= 0:
		_die()

func _flash_hit() -> void:
	_body_visual.color = Color.RED
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		_body_visual.color = original_color

# Immune to weapon stun (2026-08-23, user explicit: "mini boss cannot be
# stunned by the any weapon") -- deliberately never sets is_stunned
# regardless of GameData.weapon_has_stun, unlike hit_handler.gd's normal
# on_hit(). Knockback still lands (just scaled down) -- stun-lock and
# knockback are separate effects here; only the stun-lock is blanket-immune.
#
# NOTE (2026-08-23): heavy warhammer hits land with the same knockback as
# light ones here -- elana.gd's own bonus heavy-hit knockback
# (_apply_heavy_knockback()) only writes to a _pending_knockback field every
# base_enemy.gd-derived enemy has, which Cobblecroak doesn't. A fix for this
# was written and then explicitly reverted same session (user: "REMEMBER
# THE MEMEMORY THAT ASK FIRST BEFORE APPLYING CODE CHANGE") -- flagged here,
# not fixed, until asked for.
func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	if hp <= 0:
		return
	# Hibernate invulnerability (2026-08-23, user's own spec: "cannot be
	# damaged") -- damage is always skipped here, but knockback still lands
	# (scaled, see _apply_incoming_knockback()'s own comment) -- a "rock"
	# can still be nudged even while fully damage-immune. The warhammer-
	# break condition (see the Hibernate export group's own comment for the
	# real-physics calibration) is checked here directly rather than in
	# _do_hibernate()'s own loop, since it needs the actual hit's
	# attacker/weapon context.
	if _is_hibernating:
		if attacker != null and is_instance_valid(attacker) and ("is_heavy_attack" in attacker) and attacker.is_heavy_attack and GameData.current_weapon == "warhammer":
			_is_hibernating = false
			_shake_player_camera(0.5)
			_flash_hit()
		# 2026-08-25, real bug found: is_magic used to be dropped entirely
		# (underscore-prefixed, unused) -- every hit, magic or not, always
		# applied whatever weapon Elana currently has equipped's knockback,
		# so Bulwark's reflect damage (is_magic=true, no weapon involved at
		# all) and any elemental/magic hit shoved her exactly like a melee
		# swing would. Gated now, matching hit_handler.gd's own on_hit()
		# convention (every other enemy in the codebase already skips
		# weapon knockback on magic hits) -- user explicit: "fix it."
		if not is_magic:
			_apply_incoming_knockback(hit_direction, KNOCKBACK_SCALE)
		return
	var final_damage: int = GameData.calc_damage(float(damage), float(defense))
	apply_boss_damage(final_damage)
	# Tongue Pull's escape tracking (2026-08-23) -- only while she's actually
	# grabbed (_is_grabbing_elana, see _do_tongue_grab()). The Fire Blast
	# check lives in on_elemental_hit() below, not here -- see that
	# function's own comment for why. Every landed hit counts toward the
	# 8-hit threshold regardless of element/weapon.
	if _is_grabbing_elana:
		_tongue_pull_hits_landed += 1
	if not is_magic:
		_apply_incoming_knockback(hit_direction, 1.0)

# Scale is 1.0 (full strength) outside Hibernate, KNOCKBACK_SCALE (halved)
# only while hibernating (2026-08-23, user explicit: "remove the halving of
# velocity of cc. and put it on when in hybernation only" -- normal combat
# used to be halved everywhere; now only a "rock" being nudged is).
# Bypasses CharacterBody2D's floor-snap/stop-on-slope handling for the
# knockback's duration, letting velocity apply like a plain physics body
# instead of grounded-specific logic potentially fighting it --
# _apply_movement() switches back to GROUNDED the instant _knockback_timer
# runs out. Investigated as the suspected cause of a real "no horizontal
# knockback" bug (2026-08-23); the actual cause turned out to be a
# check-order bug in _apply_movement() (see its own comment) -- kept as
# cheap defense-in-depth rather than reverted.
func _apply_incoming_knockback(hit_direction: int, scale: float) -> void:
	if GameData.weapon_knockback_x != 0.0 or GameData.weapon_knockback_y != 0.0:
		velocity = Vector2(hit_direction * GameData.weapon_knockback_x, GameData.weapon_knockback_y) * scale
		_knockback_timer = KNOCKBACK_RECOVERY_TIME
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

# Fire Blast escape condition (2026-08-23 fix -- was checking the wrong
# thing entirely). "Fire Blast" is a real, separate, NAMED herb skill
# (elana.gd's _herb_fire_blast(), herbElementalFire equipped + right-click
# charge/release) -- a small AOE burst around ELANA'S OWN position that
# calls enemy.on_elemental_hit("fire", ...) on anything nearby. It has
# nothing to do with is_heavy_attack (that's the melee weapon-swing flag,
# a completely different thing) -- the original check here
# (attacker.is_heavy_attack) could never match a real Fire Blast cast at
# all, which is why it silently never released her. Any "fire" elemental
# hit landed while grabbed now satisfies the condition, full stop.
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
	if _is_grabbing_elana and element == "fire":
		_tongue_pull_release_requested = true
	# Croak interrupt (2026-08-23) -- frost uses the same chance-based roll
	# every other enemy's freeze already does (GameData.freeze_chance), not
	# a guaranteed cut -- user's own explicit choice ("same chance-based
	# roll as everyone else") over a guaranteed interrupt.
	if _is_croaking and element == "frost" and GameData.freeze_chance > 0.0 and randf() < GameData.freeze_chance:
		_croak_interrupted = true
	# Shock now exists (hit_handler.gd's on_elemental_hit(), innate stun,
	# 2026-08-25) -- unlike frost above, this is a GUARANTEED interrupt on a
	# single hit, no chance roll (user explicit: "make it interrupt if hit
	# by shock 1 time").
	if _is_croaking and element == "elec":
		_croak_interrupted = true
	var mult: float = _get_element_mult(element)
	if mult <= 0.0:
		return  # fully immune -- no damage
	on_hit(hit_direction, max(1, int(round(float(damage) * mult))), true, attacker)

func on_plunge_hit(attacker: Node, hit_direction: int, damage: int) -> bool:
	on_hit(hit_direction, damage, false, attacker)
	return true

func _die() -> void:
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	GameData.gain_xp(xp_reward)
	# Death reward -- permanent jump height increase (see
	# GameData.cobblecroak_defeated / get_jump_mult()'s own comments).
	GameData.cobblecroak_defeated = true
	queue_free()

# Same reasoning as Broodspawner's/Hollowfang's/Elemander's own
# blocks_chain_pull() (2026-08-23, user explicit: "also cannot be pull by
# chain claw") -- chain_projectile.gd checks this hook before ever setting
# _pull_target; the hit/damage above still lands normally through the
# chain's own on_hit() call, only the actual drag-in is refused.
func blocks_chain_pull() -> bool:
	return true
