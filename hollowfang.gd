extends CharacterBody2D

# Boss 1 — The Hollowfang. 512x512. Head is the weak point (low defense),
# body is armored (Shellback-grade defense) — one shared HP pool, only how
# much damage actually gets through differs by which region got hit. The
# Head is a separate child node with its own Hurtbox/on_hit forwarding
# computed damage back to this shared pool, rather than reusing
# hit_handler.gd directly (that assumes a single flat defense per enemy;
# this needed two different values feeding the same HP).
#
# Cycles through 5 evenly-weighted attacks at random (never repeating the
# same one twice in a row), plus Cave Disruptor as a separate periodic proc
# layered on top (see _pick_attack()) — each with its own telegraph:
#  - Bite: head lunges a fixed diagonal, collision hit via BiteZone, holds
#    at the landed spot then eases home over 1.5s (BITE_HOLD/BITE_RETURN).
#  - Charge Bite: Retreat, then a 3-hit combo — head lunges left/mid/right
#    of ChargeBiteTriggerZone's actual position (reused as a fixed target
#    box even outside the trigger-zone-test path), holding 0.3s between
#    each and easing home 1.5s after the last (CHARGE_HOLD/CHARGE_RETURN).
#    Shared setup (_start_charge_combo()) is used by both the random pick
#    and the dedicated trigger zone so neither path can whiff from missing
#    target data.
#  - Spit Volley: slow projectiles that hatch Swarmers if they land, see
#    hollowfang_spit.gd — destructible mid-air, busy-while-spitting is its
#    own punish window. Won't fire again until the whole volley (in-flight
#    spits + whatever they hatched) has resolved/died.
#  - Tail Slam: a separate Tail node, re-anchored at its own right-end
#    hinge, rotates AND translates (not pure rotation — that could only
#    ever reach as far as the tail is long) to land exactly on
#    TailSlamTriggerZone's actual position. Hits everyone in its box, not
#    just the first collision; includes a pure-vertical knock-up.
#  - Eject Spikes: head ducks to the body's right edge, holds 1s, fires 5
#    fast spike projectiles (hollowfang_spike.gd) to random scattered
#    points inside EjectSpikesTriggerZone, holds 1s more, eases home.
#  - Cave Disruptor: replaced Head Slam + Coil Sweep (2026-08-12), and has
#    no dedicated trigger zone (2026-08-12) — a periodic random proc instead
#    of an evenly-weighted pick or a manually-testable box. Every time
#    _pick_attack() would fire, once at least cave_disruptor_min_attacks_
#    between normal attacks have happened since the last Cave Disruptor, it
#    rolls a chance to preempt the pick (cave_disruptor_base_chance, or
#    cave_disruptor_half_hp_chance instead once hp drops to/below half —
#    more frequent as the fight goes on). The tail stomps at the boss's own
#    base cave_disruptor_slam_count times (rise → strike, pure rotation —
#    no distant target, so no translation needed); each strike knocks up
#    (no damage) everyone currently inside CaveDisruptorArenaZone, both
#    player and enemies. Concurrently, rocks (hollowfang_rock.gd/.tscn)
#    spawn at a steady interval and fall straight down ignoring all
#    terrain, exploding for real damage at the zone's bottom edge (the
#    placeholder "arena floor") at a random X each time — no landing-spot
#    telegraph, by design. The whole sequence occupies the entire state
#    machine the same way every other attack does, so the head is
#    naturally undefended by any other attack for its duration — that's
#    the intended risk/reward window, not extra code.
#
# 5 dedicated trigger-zone boxes (Bite/Spit/Charge/Tail/Eject) are the ONLY
# way an attack starts — Hollowfang stays fully passive whenever Elana isn't
# standing in at least one of them (see _tick_idle()). No proximity/aggro-
# range fallback.
#
# Known limitation: Charge Bite/Tail Slam/Eject Spikes all target wherever
# their own trigger-zone box is currently placed, not the player's actual
# position — fine as a placeholder, needs real targeting once a real arena
# exists. Cave Disruptor's rocks/knockup are scoped to CaveDisruptorArenaZone
# the same way — that box is meant to stand in for "the arena" until a real
# one exists.
#
# Scope note: just the creature — the arena room, the floor-is-the-boss
# plug mechanic, the two entrances, platforms, the chain-grapple-to-head
# windows, and the death/motes/stone-being reveal sequence are all still
# open follow-ups. Placeholder ColorRect visuals (body + a distinct head
# region), no sprite art yet.

signal boss_died

@export var max_hp: int = 800
@export var body_defense: int = 60
@export var head_defense: int = 5
@export var xp_reward: int = 250

@export var bite_damage: int = 18
@export var charge_bite_damage: int = 20
@export var spit_damage: int = 10
@export var spit_count: int = 3
# Gap between each shot in the volley — see _fire_spit_volley().
@export var spit_fire_interval: float = 0.3
@export var bite_knockback_x: float = 250.0
@export var bite_knockback_y: float = -120.0
@export var bite_telegraph_time: float = 0.8
@export var bite_miss_stun_chance: float = 0.3
@export var bite_stun_duration: float = 5.0
@export var tail_damage: int = 20
@export var tail_knockup_y: float = -420.0
@export var tail_telegraph_time: float = 0.6
@export var tail_active_time: float = 0.4
@export var tail_warn_duration: float = 2.0
@export var tail_warn_flash_count: int = 3
@export var charge_windup_time: float = 0.55
@export var charge_active_time: float = 0.25
@export var spike_damage: int = 12
@export var spike_count: int = 5
@export var eject_telegraph_time: float = 0.5
@export var eject_pre_fire_hold_time: float = 1.0
@export var eject_active_time: float = 1.0

# SpikyZone — always-active contact hazard (not tied to any attack state,
# unlike BiteZone/TailHitZone which only deal damage during their specific
# attack windows). Just touching it hurts and shoves Elana off, regardless
# of what the boss is currently doing.
@export var spiky_damage: int = 10
@export var spiky_knockback_dist: float = 10.0
# SpikyZone2 — same "always dangerous, no attack state involved" idea, but
# no knockback at all, and ticks damage repeatedly (polled, not
# body_entered) for as long as Elana stays overlapping — same shape as
# vine_gate.gd's ContactArea, just a fixed 1s tick instead of that one's
# 0.5s.
@export var spiky_dot_damage: int = 10
@export var spiky_dot_tick_interval: float = 1.0
# Drop Push — a named attack, also gated on SpikyZone2 — separate from the
# DoT tick above, on its own cooldown, so standing in Spike Zone 2 doesn't
# just chip HP away forever. The entire root body (not just Head/Tail)
# recoils significantly leftward (windup), HOLDS there for a beat —
# deliberately long enough that Elana has time to actually land/drop into
# the arena before anything pushes her — then thrusts straight back to her
# actual resting spot (the same one full_map.tscn places her at — no
# overshoot past it, that read as excessive). See _start_drop_push().
# Direction Elana actually gets knocked is computed from her position
# relative to the boss at the moment of the thrust (same away-from-center
# idea as SpikyZone's own knockback above), not a fixed axis, so it still
# reads as "pushed toward the arena" regardless of which side she's on. The
# body's own solid collision is disabled during the recoil (visual-only —
# can't drag her backward) and enabled for the thrust back home, so the
# physical shove and the explicit knockback below both actually connect at
# the same moment — see _set_body_collision_enabled().
@export var drop_push_pullback_dist: float = 220.0
@export var drop_push_pullback_time: float = 0.5
@export var drop_push_pullback_hold_time: float = 0.6
@export var drop_push_lunge_time: float = 0.15
@export var drop_push_knockback_dist: float = 220.0
@export var drop_push_damage: int = 20
# Warmup before the push itself even starts — see start_drop_push_sequence().
# Time from the cutscene calling it to the actual _start_drop_push() call is
# drop_push_trigger_delay; drop_push_shake_delay/duration are timed to end
# right as that fires at default values (2 + 3 = 5).
@export var drop_push_trigger_delay: float = 5.0
@export var drop_push_shake_delay: float = 2.0
@export var drop_push_shake_duration: float = 3.0
@export var cave_disruptor_slam_count: int = 12
@export var cave_disruptor_rise_time: float = 0.4
@export var cave_disruptor_strike_time: float = 0.55
@export var cave_disruptor_telegraph_time: float = 0.4
@export var cave_disruptor_knockup_y: float = -350.0
@export var cave_disruptor_stomp_angle: float = 1.1  # ~63 degrees, straight-down-ish
@export var cave_disruptor_min_attacks_between: int = 3
@export var cave_disruptor_base_chance: float = 0.5
@export var cave_disruptor_half_hp_chance: float = 0.8
@export var rock_count: int = 30
@export var rock_spawn_interval_min: float = 0.2
@export var rock_spawn_interval_max: float = 1.1
@export var rock_burst_min: int = 1
@export var rock_burst_max: int = 3
@export var rock_damage: int = 15
@export var rock_explosion_radius: float = 40.0
@export var rock_fall_speed: float = 280.0
@export var rock_spawn_height_above_floor: float = 500.0

@export var attack_cooldown_time: float = 3.0

const SPIT_SCENE = preload("res://hollowfang_spit.tscn")
const SPIKE_SCENE = preload("res://hollowfang_spike.tscn")
const ROCK_SCENE = preload("res://hollowfang_rock.tscn")
# Same rock_gate.tscn dialog_marker.gd's own cutscene already used — moved
# here (see drop_entrance_gate()) so both that cutscene AND the
# CaveDisruptorArenaZone safety-net trigger below share one implementation
# instead of duplicating the instantiate/position/boss_ref dance.
const ROCK_GATE_SCENE = preload("res://rock_gate.tscn")
const ROCK_GATE_X_OFFSET: float = 0.0
const ROCK_GATE_Y_OFFSET: float = -8.0
const BODY_SIZE: float = 512.0
const TELEGRAPH_TINT: Color = Color(1.5, 0.6, 0.6)
const BITE_PULLBACK_DIST: float = 20.0
# How far Charge Bite's 1st and 3rd targets get pulled in from the trigger
# box's raw edges toward center — see _compute_charge_targets().
const CHARGE_TARGET_INSET: float = 50.0
# Extra windup pullback distance for Charge Bite's FIRST lunge only (added
# on top of BITE_PULLBACK_DIST) — hits 2/3 keep the normal shared pullback.
const CHARGE_FIRST_PULLBACK_EXTRA: float = 50.0
# Tail's raised wind-up angle during its telegraph. The landed angle isn't a
# constant — it's computed per-swing via atan2 toward wherever
# TailSlamTriggerZone currently sits, so it still lands correctly if the
# zone gets repositioned later.
const TAIL_RAISED_ANGLE: float = -0.96  # ~-55 degrees

enum State {
	IDLE, TELEGRAPH_BITE, BITE,
	RETREAT, TELEGRAPH_CHARGE, CHARGE_BITE,
	TELEGRAPH_SPIT, SPIT,
	WARN_TAIL_SLAM, TELEGRAPH_TAIL, TAIL_SLAM, CHARGE_HOLD, CHARGE_RETURN, BITE_HOLD, BITE_RETURN, BITE_STUNNED,
	TELEGRAPH_EJECT, EJECT_HOLD, EJECT_SPIKES,
	TELEGRAPH_CAVE, CAVE_SLAM_RISE, CAVE_SLAM_STRIKE, RECOVER
}

var hp: float
var state: State = State.IDLE
var _state_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _last_attack: int = -1
var _hit_this_attack: bool = false
# Set/cleared by BiteTriggerZone (a fixed detection box in front of the
# boss, right side) — while true, Bite becomes one of the eligible picks in
# _tick_idle(), and re-fires every time the cooldown clears for as long as
# Elana keeps standing in it
# (same "stay in the zone, get hit again" shape as base_enemy.gd's
# AttackZone, just driving a specific attack instead of the generic one).
var _elana_in_bite_trigger: bool = false
# Same shape as _elana_in_bite_trigger, but for SpitTriggerZone → Spit.
var _elana_in_spit_trigger: bool = false
# The current volley's still-unresolved spit projectiles and/or whatever
# Swarmers they hatched — Spit can't fire again while this is non-empty.
var _spit_volley_pending: Array = []
# Head's resting local position, captured at _ready() so it always follows
# wherever the Head node is placed in the editor. The windup/lunge below
# animate the Head relative to this, then ease back to it afterward.
var _head_home_pos: Vector2 = Vector2.ZERO
# Fixed down-right diagonal, 150px — not aimed at the player.
var _bite_lunge_offset: Vector2 = Vector2(1, 1).normalized() * 150.0
# Same shape as _elana_in_bite_trigger, but for TailSlamTriggerZone → Tail Slam.
var _elana_in_tail_trigger: bool = false
# Tail's resting position/rotation, captured at _ready() (follows wherever
# it's placed in the editor). The swing's landed pose is recomputed fresh
# each time the attack starts, from wherever TailSlamTriggerZone's actual
# CollisionShape2D sits — both position AND rotation are animated during
# the slam so it lands exactly on the box regardless of the tail's own
# length or how far the box is from the hinge (a pure rotation-only swing
# can only ever reach as far as the tail is long).
var _tail_home_pos: Vector2 = Vector2.ZERO
var _tail_home_rotation: float = 0.0
var _tail_landed_local_pos: Vector2 = Vector2.ZERO
var _tail_landed_angle: float = 0.0
# Tail hits everyone caught in its box, not just whoever triggers
# body_entered first — this tracks who's already been hit *this* swing (so
# a body re-entering doesn't get double-hit) separately from Bite's
# single-target _hit_this_attack.
var _tail_hit_bodies: Array = []
# Same shape as _elana_in_bite_trigger, but for ChargeBiteTriggerZone → the
# 3-hit Charge Bite combo below.
var _elana_in_charge_trigger: bool = false
# 3 local-space head targets (left/mid/right of the trigger box, computed
# fresh each time the combo starts), which lunge of the 3 we're on, and the
# pullback direction for the current one's windup.
var _charge_targets: Array = []
var _charge_step: int = 0
var _charge_pullback_dir: Vector2 = Vector2.ZERO
# Set explicitly alongside _charge_pullback_dir at each hit's windup start
# (not re-derived from _charge_step inside the per-frame visual update) —
# deeper on the 1st hit only, plain BITE_PULLBACK_DIST for hits 2/3.
var _charge_pullback_dist: float = 0.0
# Where the windup pulls back FROM — the previous lunge's landing spot
# (or _head_home_pos for the very first bite), not the original resting
# position, so bites 2 and 3 only retreat a little from wherever the head
# just struck instead of snapping all the way back home each time.
var _charge_pullback_origin: Vector2 = Vector2.ZERO
# Where CHARGE_RETURN's explicit timed lerp starts from — captured the
# instant it begins (should equal the last bite's landing spot, since
# CHARGE_HOLD freezes the head there beforehand).
var _charge_return_start_pos: Vector2 = Vector2.ZERO
# Same idea as _charge_return_start_pos, but for plain Bite's BITE_RETURN.
var _bite_return_start_pos: Vector2 = Vector2.ZERO
# Same shape as _elana_in_bite_trigger, but for EjectSpikesTriggerZone →
# Eject Spikes.
var _elana_in_eject_trigger: bool = false
# No dedicated trigger zone for Cave Disruptor — it's a periodic random
# proc instead (see _pick_attack()), not something to isolate-and-test by
# walking into a box like the other 5.
var _attacks_since_cave_disruptor: int = 0
# Which of the cave_disruptor_slam_count slams we're on, and the rock-spawn
# countdown/counter — ticked during both CAVE_SLAM_RISE and
# CAVE_SLAM_STRIKE so rocks keep falling continuously through the whole
# multi-slam phase, not just during one half of each slam.
var _cave_slam_step: int = 0
var _cave_rock_timer: float = 0.0
var _spiky_dot_timer: float = 0.0
var _cave_rocks_spawned: int = 0
# Root body's resting local position, captured at _ready() same as
# _head_home_pos/_tail_home_pos — _start_drop_push() animates from/back to
# this rather than a hardcoded offset, so it still works if the boss is ever
# repositioned in the editor.
var _body_home_pos: Vector2 = Vector2.ZERO
# Every convex piece _build_convex_body_collision() generates, so Drop Push
# can toggle the whole solid body's collision on/off as one unit — see
# _set_body_collision_enabled().
var _body_collision_pieces: Array[CollisionPolygon2D] = []
# Reentrancy guard for _start_drop_push() — same idea as _roaring.
var _drop_pushing: bool = false
# True during the warmup (start_drop_push_sequence()) leading up to the
# actual push — kept separate from _drop_pushing (which only covers the
# push motion itself) so nothing else can start mid-warmup either.
var _drop_push_pending: bool = false
# Safety net, not the primary mechanism — the Tween chain in
# _start_drop_push() is expected to always finish and clear _drop_pushing
# itself. Ticked down independently in _physics_process() while _drop_pushing
# is true; if it ever reaches 0 (tween somehow never completed — e.g. killed
# by something external, or an idle/physics-frame stall), forces the body
# back home and clears the stuck state instead of leaving Hollowfang parked
# off at the recoil position indefinitely.
var _drop_push_watchdog_timer: float = 0.0
const DROP_PUSH_WATCHDOG_TIMEOUT: float = 3.0
# The entrance rock_gate this boss has spawned, if any — see
# drop_entrance_gate(). A live-node reference, not a boolean, specifically
# so a broken/freed gate is correctly detected as "gone" and a replacement
# can spawn on the next cutscene trigger.
var _entrance_gate: Node = null
# True while play_roar_shake()'s jitter coroutine has exclusive control of
# _head.position — see the guard at the top of _update_head_bite_visual().
var _roaring: bool = false
# Same "★★★" floating label charger.gd uses for its own stun, shown while
# BITE_STUNNED is active.
var _bite_stun_indicator: Label = null
# Public (not _-prefixed like its siblings) — elana.gd's Bulwark reflect
# code (`attacker.on_hit(-attacker.direction, ...)`) assumes every member
# of the "enemies" group has this, since every base_enemy.gd-derived enemy
# does. Hollowfang doesn't extend that base, so it needs its own.
var direction: int = 1
# Same mix-based flash-overlay shader vine_gate.gd/ore_node.gd already use —
# preserves the sprite's actual art instead of a modulate multiply, which
# would just zero out whichever color channels the flash tint doesn't share
# (e.g. a straight Color.RED modulate would crush the head's blue to black).
var _flash_material: ShaderMaterial

@onready var _body_sprite: AnimatedSprite2D = $AnimatedSprite2D
# Keyframes Hurtbox/CollisionPolygon2D:polygon per attack (one Animation
# resource per name, matching _body_sprite's SpriteFrames animation names) —
# see _play_body_anim(). How many keyframes each one has (a single static
# pose, or several tracking the pose through the attack) is decided by hand
# in the editor's Animation panel, not by this script.
@onready var _collision_anim: AnimationPlayer = $CollisionAnimationPlayer
@onready var _head: Node2D = $Head
@onready var _tail: Node2D = $Tail
@onready var _hp_bg: ColorRect = $HPBar/Background
@onready var _hp_fill: ColorRect = $HPBar/Fill

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	add_to_group("bosses")
	# SpikyZone/SpikyZone2 are plain unscripted Area2D children — nothing to
	# call add_to_group() from their own _ready() the way spike.gd/vine_gate.gd
	# do for themselves, so it has to happen here instead. Without this, Ant
	# Queen's death reward (elana.gd's take_damage() checks attacker.is_in_
	# group("hazards")) silently never matched either zone even though both
	# are passed as the attacker on hit.
	$SpikyZone.add_to_group("hazards")
	$SpikyZone2.add_to_group("hazards")
	_build_convex_body_collision()
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = preload("res://hit_flash.gdshader")
	_body_sprite.material = _flash_material
	_head_home_pos = _head.position
	_tail_home_pos = _tail.position
	_tail_home_rotation = _tail.rotation
	_body_home_pos = position
	$BiteTriggerZone.body_entered.connect(_on_bite_trigger_zone_body_entered)
	$BiteTriggerZone.body_exited.connect(_on_bite_trigger_zone_body_exited)
	$Head/BiteZone.body_entered.connect(_on_bite_zone_body_entered)
	$SpitTriggerZone.body_entered.connect(_on_spit_trigger_zone_body_entered)
	$SpitTriggerZone.body_exited.connect(_on_spit_trigger_zone_body_exited)
	$TailSlamTriggerZone.body_entered.connect(_on_tail_trigger_zone_body_entered)
	$TailSlamTriggerZone.body_exited.connect(_on_tail_trigger_zone_body_exited)
	$Tail/TailHitZone.body_entered.connect(_on_tail_hit_zone_body_entered)
	$ChargeBiteTriggerZone.body_entered.connect(_on_charge_trigger_zone_body_entered)
	$ChargeBiteTriggerZone.body_exited.connect(_on_charge_trigger_zone_body_exited)
	$EjectSpikesTriggerZone.body_entered.connect(_on_eject_trigger_zone_body_entered)
	$EjectSpikesTriggerZone.body_exited.connect(_on_eject_trigger_zone_body_exited)
	$SpikyZone.body_entered.connect(_on_spiky_zone_body_entered)
	# HeadCollision (Head/HeadCollision) rests inside the root body's own
	# silhouette and shares layer bit 1 with the root's own collision_mask —
	# without this, the root's own move_and_slide() treats its own head's
	# solid body as an obstacle and pushes itself away from it every physics
	# frame (a self-collision recovery feedback loop), which is what was
	# actually dragging the whole boss off position, not Drop Push itself.
	# Registered on both bodies — added on just the root, she still started
	# each load nudged slightly forward from the very first physics frames,
	# before anything else had a chance to settle.
	add_collision_exception_with($Head/HeadCollision)
	$Head/HeadCollision.add_collision_exception_with(self)

func _on_bite_trigger_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_bite_trigger = true

func _on_bite_trigger_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_bite_trigger = false

func _on_spit_trigger_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_spit_trigger = true

func _on_spit_trigger_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_spit_trigger = false

func _on_charge_trigger_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_charge_trigger = true

func _on_charge_trigger_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_charge_trigger = false

func _on_eject_trigger_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_eject_trigger = true

func _on_eject_trigger_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_eject_trigger = false

func _on_tail_trigger_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_tail_trigger = true

func _on_tail_trigger_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_tail_trigger = false

# Real collision-based hit detection, same shape as Bite's — anything the
# swinging tail actually touches during TAIL_SLAM takes the hit, once per
# swing. Includes friendly fire on spawned enemies, same as Bite.
func _on_tail_hit_zone_body_entered(body: Node) -> void:
	if state != State.TAIL_SLAM or body in _tail_hit_bodies:
		return
	if body.is_in_group("player"):
		_tail_hit_bodies.append(body)
		body.take_damage(tail_damage, false, self)
		if body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(0, tail_knockup_y))
		if body.has_method("add_camera_trauma"):
			body.add_camera_trauma(0.6)
	elif body != self and body.is_in_group("enemies") and body.has_method("on_hit"):
		_tail_hit_bodies.append(body)
		body.on_hit(0, tail_damage, false)
		# base_enemy.gd has no public apply_knockback() like elana.gd — its
		# own hit_handler.gd sets _pending_knockback directly the same way,
		# so this matches the existing enemy-side knockback convention.
		if "_pending_knockback" in body:
			body._pending_knockback = Vector2(0, tail_knockup_y)

# SpikyZone — see the @export declarations above. No state check at all
# (unlike every other hit zone in this file), since this isn't tied to an
# attack — it's just always dangerous to touch. Knockback distance is
# converted to a velocity via a short fixed duration, matching how every
# other knockback call in this file specifies a speed, not a raw distance.
const SPIKY_KNOCKBACK_DURATION: float = 0.15

func _on_spiky_zone_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# $SpikyZone, NOT self — take_damage()'s Bulwark reflect only excludes
	# attackers that aren't in the "enemies" group (the existing comment
	# there: "Environmental hazards... aren't attackers"). Passing self
	# (Hollowfang, who IS in "enemies") made Bulwark reflect this hazard's
	# own damage back onto the boss herself — enough repeated hits could
	# actually kill her via her own spikes, which then unlocked/reset the
	# boss camera (reset_boss_camera() on death), reading as the camera
	# randomly jumping to the pre-fight default bounds.
	body.take_damage(spiky_damage, false, $SpikyZone)
	if body.has_method("apply_knockback"):
		var away_dir: Vector2 = (body.global_position - global_position).normalized()
		var speed: float = spiky_knockback_dist / SPIKY_KNOCKBACK_DURATION
		body.apply_knockback(away_dir * speed, SPIKY_KNOCKBACK_DURATION)

# Polled every physics frame (see _physics_process) rather than
# body_entered/exited — ticks damage on a fixed interval for as long as
# Elana is still overlapping, instead of only once per fresh entry.
func _tick_spiky_dot(delta: float) -> void:
	# get_overlapping_bodies() errors outright (not just an empty result) if
	# monitoring is off — guard against that instead of only relying on
	# visible, since hiding the node in the editor doesn't touch monitoring.
	if not $SpikyZone2.monitoring:
		return
	_spiky_dot_timer -= delta
	if _spiky_dot_timer > 0.0:
		return
	for body in $SpikyZone2.get_overlapping_bodies():
		if body.is_in_group("player"):
			# $SpikyZone2, NOT self — see _on_spiky_zone_body_entered()'s
			# comment for why self (Bulwark-reflectable) was the actual bug.
			# Matters even more here: this ticks every second while in
			# contact, so the reflected damage compounded far faster than
			# the single-hit SpikyZone.
			body.take_damage(spiky_dot_damage, false, $SpikyZone2)
			_spiky_dot_timer = spiky_dot_tick_interval
			break

# Public — called once by dialog_marker.gd's Boss 1 Drop Entrance cutscene
# (BOSS1_DROP_ENTRANCE), not self-triggered by SpikyZone2 contact anymore.
# Awaitable: the caller awaits this so it can hold GameData.in_cutscene
# until the whole delay/shake/push sequence actually finishes. Builds up
# instead of pushing immediately: a beat, then a violent screen shake timed
# to run right up to the moment the real push begins (drop_push_shake_delay
# + _duration == drop_push_trigger_delay at default values — 2s in, 3s of
# shake, push at 5s).
func start_drop_push_sequence(body: Node) -> void:
	_drop_push_pending = true
	await get_tree().create_timer(drop_push_shake_delay).timeout
	if not _is_drop_push_sequence_still_valid(body):
		_drop_push_pending = false
		return
	_play_violent_shake(body, drop_push_shake_duration)
	await get_tree().create_timer(drop_push_trigger_delay - drop_push_shake_delay).timeout
	_drop_push_pending = false
	if not _is_drop_push_sequence_still_valid(body):
		return
	await _start_drop_push(body)

# Elana's frozen (GameData.in_cutscene) for the whole sequence now that it's
# cutscene-driven, so leaving-the-zone is no longer a real cancellation path
# — this just guards against the boss dying or another attack somehow
# starting mid-sequence.
func _is_drop_push_sequence_still_valid(body: Node) -> bool:
	if not is_instance_valid(self) or not is_instance_valid(body) or hp <= 0:
		return false
	return state == State.IDLE

# Repeatedly re-tops-up camera trauma to max every 0.1s for duration, rather
# than one add_camera_trauma() call — a single call decays to near-zero in
# under half a second (SHAKE_DECAY, elana.gd's own shake system), nowhere
# near enough to read as "violent" for multiple seconds straight.
func _play_violent_shake(body: Node, duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed < duration:
		if not is_instance_valid(body) or not body.has_method("add_camera_trauma"):
			return
		body.add_camera_trauma(1.0)
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

# See DROP_PUSH_WATCHDOG_TIMEOUT — a safety net, not the expected path. The
# whole sequence normally takes pullback + pullback_hold + lunge + hold +
# return (~1.7s at default values), comfortably inside the 3s timeout.
func _tick_drop_push_watchdog(delta: float) -> void:
	if not _drop_pushing:
		return
	_drop_push_watchdog_timer -= delta
	if _drop_push_watchdog_timer <= 0.0:
		position = _body_home_pos
		# Back to the normal resting state — solid again, same as the tween's
		# own final step. Leaving this disabled (as an earlier version of
		# this did) is exactly what let Elana walk straight through her.
		_set_body_collision_enabled(true)
		_drop_pushing = false

# Toggles every piece _build_convex_body_collision() generated as one unit.
# Drop Push uses this so the recoil leg of the motion is purely visual
# (collision off — can't drag Elana backward while easing the body through/
# near her) and only the forward thrust leg actually solidifies, so the
# physical push and the explicit apply_knockback() below land together.
func _set_body_collision_enabled(enabled: bool) -> void:
	for piece in _body_collision_pieces:
		if is_instance_valid(piece):
			piece.disabled = not enabled

# Whole root body recoils left (windup, collision OFF), holds, then thrusts
# straight back to _body_home_pos (the actual push — collision back ON
# right as the thrust starts, so it's still solid once she's home). A Tween
# rather than the manual await-loop _head/_tail visuals use elsewhere in
# this file, since this is a simple one-shot sequence with no per-frame
# state to react to mid-animation. apply_knockback() fires in the same
# callback that re-enables collision, both timed to the instant the forward
# thrust begins — computed away from Hollowfang's center (same idea
# SpikyZone's own knockback above already uses), not a fixed axis, so it
# still reads as "pushed toward the arena" regardless of which side she's on.
func _start_drop_push(body: Node) -> void:
	# Awaited by start_drop_push_sequence() now (the cutscene needs to know
	# when the whole motion is actually done, not just started), via
	# `await tween.finished` at the end below.
	_drop_pushing = true
	_drop_push_watchdog_timer = DROP_PUSH_WATCHDOG_TIMEOUT
	_set_body_collision_enabled(false)
	# Captured NOW, before anything moves — not re-derived from global_position
	# later inside the callback below. drop_push_pullback_dist (220px) is
	# bigger than SpikyZone2's own 112px offset from center, so by the time
	# the callback used to run, the recoil had already carried the root PAST
	# Elana's position — "away from Hollowfang's current position" then
	# pointed backward from her actual stance, pushing her toward the tail
	# instead of the arena. Her true resting-stance direction is fixed here
	# instead, before the recoil can throw it off.
	var push_dir: Vector2 = (body.global_position - global_position).normalized()
	var pullback_target: Vector2 = _body_home_pos - Vector2(drop_push_pullback_dist, 0)
	var tween := create_tween()
	# Explicit physics-frame processing — position is a physics-relevant
	# property and every other per-frame write in this file (Head/Tail
	# easing) happens from _physics_process() too; create_tween() defaults to
	# idle-frame processing, which would step this animation out of lockstep
	# with move_and_slide() running every physics frame regardless of state.
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "position", pullback_target, drop_push_pullback_time)
	tween.tween_interval(drop_push_pullback_hold_time)
	tween.tween_callback(func():
		_set_body_collision_enabled(true)
		if is_instance_valid(body):
			if body.has_method("take_damage"):
				body.take_damage(drop_push_damage, false, self)
			if body.has_method("apply_knockback"):
				var speed: float = drop_push_knockback_dist / drop_push_lunge_time
				body.apply_knockback(push_dir * speed, drop_push_lunge_time)
	)
	tween.tween_property(self, "position", _body_home_pos, drop_push_lunge_time)
	tween.tween_callback(func(): _drop_pushing = false)
	await tween.finished

# Real collision-based hit detection for Bite AND Charge Bite (same
# hitbox, same head, just different targeting) — whatever the head's
# hitbox actually touches during the lunge takes the hit, once per lunge.
func _on_bite_zone_body_entered(body: Node) -> void:
	if (state != State.BITE and state != State.CHARGE_BITE) or _hit_this_attack:
		return
	var dmg = bite_damage if state == State.BITE else charge_bite_damage
	if body.is_in_group("player"):
		_hit_this_attack = true
		body.take_damage(dmg, false, self)
		if body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(bite_knockback_x * direction, bite_knockback_y))
		if body.has_method("add_camera_trauma"):
			body.add_camera_trauma(0.6)
	elif body != self and body.is_in_group("enemies") and body.has_method("on_hit"):
		# Friendly fire — lets the head's own lunge kill whatever it spawned
		# (e.g. a Swarmer standing too close), same on_hit() interface every
		# enemy already exposes for weapon/spell damage.
		_hit_this_attack = true
		body.on_hit(0, dmg, false)

# Polled fallback for Charge Bite's repeat-lunge structure — see the
# CHARGE_BITE state-expiry comment in _physics_process for why the
# body_entered signal alone can miss lunges 2/3.
func _check_bite_zone_overlap() -> void:
	if _hit_this_attack:
		return
	for body in $Head/BiteZone.get_overlapping_bodies():
		_on_bite_zone_body_entered(body)
		if _hit_this_attack:
			break

# Windup pullback (telegraph) then a snap-forward lunge (active window),
# easing back to rest the rest of the time — called unconditionally every
# frame so every other state (including Recover) just settles the head
# back home as a no-op.
func _update_head_bite_visual(delta: float) -> void:
	# CHARGE_HOLD (frozen in place) and CHARGE_RETURN (explicit timed lerp
	# in _physics_process) both fully own _head.position themselves — the
	# generic "ease home" default below would otherwise fight them. Same
	# reason for _roaring — play_roar_shake()'s jitter would get fought
	# (and likely fully overwritten) by this function's own per-frame
	# lerp-to-home otherwise.
	if _roaring or state == State.CHARGE_HOLD or state == State.CHARGE_RETURN or state == State.BITE_HOLD or state == State.BITE_RETURN or state == State.BITE_STUNNED:
		return
	var target = _head_home_pos
	var rate = 10.0
	match state:
		State.TELEGRAPH_BITE:
			target = _head_home_pos - _bite_lunge_offset.normalized() * BITE_PULLBACK_DIST
			rate = 6.0
		State.BITE:
			target = _head_home_pos + _bite_lunge_offset
			rate = 18.0
		State.TELEGRAPH_CHARGE:
			target = _charge_pullback_origin - _charge_pullback_dir * _charge_pullback_dist
			rate = 8.0
		State.CHARGE_BITE:
			if _charge_step < _charge_targets.size():
				target = _charge_targets[_charge_step]
			rate = 20.0
		State.TELEGRAPH_EJECT, State.EJECT_HOLD, State.EJECT_SPIKES:
			# Same duck target through all three phases (wind down, hold
			# before firing, hold after firing) — right edge of the body at
			# its vertical center, derived from the collision polygon's own
			# bounding box (not a hardcoded offset) so it stays correct if
			# the body's ever resized/repositioned later. Since the target
			# doesn't change across EJECT_HOLD/EJECT_SPIKES, the head just
			# settles there and stays — no separate "freeze" logic needed.
			target = _body_duck_target()
			rate = 7.0
	_head.position = _head.position.lerp(target, clamp(delta * rate, 0.0, 1.0))

# Same "unconditional every frame, settles home as a no-op otherwise" shape
# as _update_head_bite_visual — telegraph raises the tail, the active swing
# rotates it down onto _tail_landed_angle (computed once when the swing
# starts, see _tick_idle), everything else eases it back to rest.
func _update_tail_slam_visual(delta: float) -> void:
	var target_rot = _tail_home_rotation
	var target_pos = _tail_home_pos
	var rate = 10.0
	match state:
		State.TELEGRAPH_TAIL:
			target_rot = TAIL_RAISED_ANGLE
			rate = 5.0
		State.TAIL_SLAM:
			target_rot = _tail_landed_angle
			target_pos = _tail_landed_local_pos
			rate = 16.0
		# Cave Disruptor stomps at HF's own base, not a distant box — pure
		# rotation is fine here (no translation needed, unlike TAIL_SLAM
		# above, since the target is right next to the hinge already).
		# target_pos stays _tail_home_pos throughout all 3 of these states.
		State.TELEGRAPH_CAVE, State.CAVE_SLAM_RISE:
			target_rot = TAIL_RAISED_ANGLE
			rate = 6.0
		State.CAVE_SLAM_STRIKE:
			target_rot = cave_disruptor_stomp_angle
			rate = 20.0
	var t = clamp(delta * rate, 0.0, 1.0)
	_tail.rotation = lerp_angle(_tail.rotation, target_rot, t)
	_tail.position = _tail.position.lerp(target_pos, t)

# Root position gets the same "unconditionally home unless actively
# animating" treatment _head/_tail already get above — hard-pinned, not
# eased, since unlike Head/Tail nothing should ever legitimately leave it
# mid-frame outside Drop Push's own tween. Added after her root position
# was observed drifting forward from her authored full_map placement right
# from the start of the fight, before Drop Push ever ran — move_and_slide()
# performs its own initial-overlap recovery even at zero velocity, so if her
# collision happens to sit slightly embedded in nearby terrain at her
# placed spot, the engine can nudge her out of it on its own. Re-asserting
# the true position every frame makes that (or any other stray nudge)
# self-correct immediately instead of silently sticking.
func _anchor_body_position() -> void:
	if not _drop_pushing:
		position = _body_home_pos

func _update_hp_bar() -> void:
	_hp_fill.size.x = clamp(hp / float(max_hp), 0.0, 1.0) * _hp_bg.size.x

func _get_target() -> Node:
	return get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	_update_hp_bar()
	_update_head_bite_visual(delta)
	_update_tail_slam_visual(delta)
	_tick_spiky_dot(delta)
	_tick_drop_push_watchdog(delta)
	match state:
		State.IDLE:
			_tick_idle()
		# Semi-opaque red ColorRect on TailSlamTriggerZone flashes
		# tail_warn_flash_count times over tail_warn_duration before the
		# actual telegraph/swing begins — a heads-up on WHERE it's about to
		# land, separate from (and before) the tail's own windup.
		State.WARN_TAIL_SLAM:
			_state_timer -= delta
			var elapsed: float = tail_warn_duration - _state_timer
			var toggle_interval: float = tail_warn_duration / (tail_warn_flash_count * 2.0)
			var toggle_index: int = int(elapsed / toggle_interval)
			$TailSlamTriggerZone/WarnFlash.visible = (toggle_index % 2 == 0)
			if _state_timer <= 0.0:
				$TailSlamTriggerZone/WarnFlash.visible = false
				_start_tail_slam()
		State.TELEGRAPH_BITE, State.TELEGRAPH_CHARGE, State.TELEGRAPH_SPIT, \
		State.TELEGRAPH_TAIL, State.TELEGRAPH_EJECT, State.TELEGRAPH_CAVE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_launch_telegraphed_attack()
		State.BITE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				# A whiffed bite (never landed on anything) has a chance to
				# leave the head stuck out at the lunge point, stunned — a
				# real punish window, unlike the normal 1s hold every bite
				# gets regardless of hit/miss.
				if not _hit_this_attack and randf() < bite_miss_stun_chance:
					state = State.BITE_STUNNED
					_state_timer = bite_stun_duration
					_show_bite_stun_indicator()
				else:
					state = State.BITE_HOLD
					_state_timer = 1.0
		# Same idea as Charge Bite's CHARGE_HOLD — freeze at the landed spot
		# instead of letting the generic "ease back toward home" default
		# start dragging the head back the instant the lunge ends.
		State.BITE_HOLD:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.BITE_RETURN
				_state_timer = 1.5
				_bite_return_start_pos = _head.position
		# Stuck at the lunge point (frozen, same as BITE_HOLD) for the full
		# bite_stun_duration instead of the normal 1s hold, then eases home
		# via the same BITE_RETURN every other bite already uses.
		State.BITE_STUNNED:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.BITE_RETURN
				_state_timer = 1.5
				_bite_return_start_pos = _head.position
		# Explicit progress-based lerp, same shape as CHARGE_RETURN — reliably
		# takes the full 1.5s rather than the generic per-frame rate decay's
		# exponential approach.
		State.BITE_RETURN:
			_state_timer -= delta
			var t = 1.0 - clamp(_state_timer / 1.5, 0.0, 1.0)
			_head.position = _bite_return_start_pos.lerp(_head_home_pos, t)
			if _state_timer <= 0.0:
				_start_recover()
		State.CHARGE_BITE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				# Signal-based hit detection (_on_bite_zone_body_entered, via
				# body_entered) only fires on a fresh overlap — if Elana never
				# actually left BiteZone between two of the combo's 3 lunges
				# (a 20px pullback often isn't enough to separate at melee
				# range), lunges 2/3 landed with zero damage even though
				# _hit_this_attack had already reset for each. This explicit
				# check at the moment each lunge finishes catches that case
				# too, reusing the exact same hit logic.
				_check_bite_zone_overlap()
				_charge_step += 1
				state = State.CHARGE_HOLD
				_state_timer = 0.3
		# A dead-still beat at the landed spot before deciding what's next —
		# without this, the generic "ease back toward home" default in
		# _update_head_bite_visual() would start dragging the head back
		# immediately, with no hold at all.
		State.CHARGE_HOLD:
			_state_timer -= delta
			if _state_timer <= 0.0:
				if _charge_step < _charge_targets.size():
					_charge_pullback_origin = _charge_targets[_charge_step - 1]
					_charge_pullback_dir = (_charge_targets[_charge_step] - _charge_pullback_origin).normalized()
					_charge_pullback_dist = BITE_PULLBACK_DIST
					_start_telegraph(State.TELEGRAPH_CHARGE, charge_windup_time)
				else:
					state = State.CHARGE_RETURN
					_state_timer = 1.5
					_charge_return_start_pos = _head.position
		# Explicit progress-based lerp (not the generic per-frame rate decay)
		# so this reliably takes the full ~1.5s requested, rather than an
		# exponential approach that only approximately settles by then.
		State.CHARGE_RETURN:
			_state_timer -= delta
			var t = 1.0 - clamp(_state_timer / 1.5, 0.0, 1.0)
			_head.position = _charge_return_start_pos.lerp(_head_home_pos, t)
			if _state_timer <= 0.0:
				_start_recover()
		State.RETREAT:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_charge_combo()
		State.SPIT:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_recover()
		State.TAIL_SLAM:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_recover()
		# Holds the ducked position before firing — see EJECT_HOLD note
		# above for why no separate freeze logic is needed here.
		State.EJECT_HOLD:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_fire_eject_spikes()
				state = State.EJECT_SPIKES
				_state_timer = eject_active_time
		# Now holds the ducked position AFTER firing, before Recover eases
		# the head back to _head_home_pos.
		State.EJECT_SPIKES:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_recover()
		State.CAVE_SLAM_RISE:
			_state_timer -= delta
			_tick_cave_rock_spawn(delta)
			if _state_timer <= 0.0:
				state = State.CAVE_SLAM_STRIKE
				_state_timer = cave_disruptor_strike_time
				_pulse_cave_disruptor_knockup()
		# Rocks keep spawning through both halves of each slam (rise + strike)
		# — see _tick_cave_rock_spawn(). The knockup itself fires once, right
		# as the strike begins (the "impact" moment), not continuously.
		State.CAVE_SLAM_STRIKE:
			_state_timer -= delta
			_tick_cave_rock_spawn(delta)
			if _state_timer <= 0.0:
				_cave_slam_step += 1
				if _cave_slam_step < cave_disruptor_slam_count:
					state = State.CAVE_SLAM_RISE
					_state_timer = cave_disruptor_rise_time
				else:
					_start_recover()
		State.RECOVER:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.IDLE
	move_and_slide()
	# After move_and_slide(), not before — it's move_and_slide() itself
	# (specifically its initial-overlap recovery step, which runs even at
	# zero velocity) that's the suspected source of the drift this is
	# guarding against, so this needs to be the last write to position each
	# frame, not something move_and_slide() can still nudge afterward.
	_anchor_body_position()

func _tick_idle() -> void:
	if _attack_cooldown > 0.0:
		return
	# No attacks while any cutscene owns control (camera pan, Drop Push's
	# own cutscene, dialogue, etc.) — Elana can be frozen/mid-animation
	# during these, so nothing should be able to start hitting her.
	if GameData.in_cutscene:
		return
	# Drop Push (including its warmup) is exclusive with the normal attack
	# cycle — mutual exclusion goes both ways, see the state == State.IDLE
	# check _is_drop_push_sequence_still_valid() does on its side.
	if _drop_pushing or _drop_push_pending:
		return
	# No fixed priority order — if Elana's standing in more than one
	# trigger zone's overlap, every zone she's actually inside gets an
	# equal-odds roll instead of whichever one happens to be checked first
	# always winning. Build the list of zones she's currently in, then pick
	# uniformly among them.
	var eligible: Array = []
	if _elana_in_bite_trigger:
		eligible.append({"last_attack": 0, "start": func(): _start_telegraph(State.TELEGRAPH_BITE, bite_telegraph_time)})
	if _elana_in_spit_trigger and _spit_volley_ready():
		eligible.append({"last_attack": 2, "start": func(): _start_telegraph(State.TELEGRAPH_SPIT, 0.7)})
	if _elana_in_charge_trigger:
		eligible.append({"last_attack": 1, "start": _start_charge_combo})
	if _elana_in_eject_trigger:
		eligible.append({"last_attack": 4, "start": func(): _start_telegraph(State.TELEGRAPH_EJECT, eject_telegraph_time)})
	if _elana_in_tail_trigger:
		eligible.append({"last_attack": 3, "start": _start_tail_slam_warning})
	if not eligible.is_empty():
		# Cave Disruptor still gets first crack at whichever attack is about
		# to fire, same as before — checked only once something's actually
		# eligible this tick, never unconditionally (this function runs
		# every physics frame regardless of whether Elana's anywhere near
		# the boss, so rolling with nothing eligible would let it fire out
		# of nowhere).
		if _maybe_start_cave_disruptor():
			return
		var pick: Dictionary = eligible[randi() % eligible.size()]
		direction = 1
		_last_attack = pick["last_attack"]
		_attacks_since_cave_disruptor += 1
		pick["start"].call()
	# No trigger-zone attack eligible — Hollowfang stays passive rather than
	# falling back to a proximity-based random pick. Attacks only start once
	# Elana is actually standing in one of the 5 attack zones (see the
	# eligible-list build above); Cave Disruptor still gets checked first
	# whenever something else IS eligible, same as before.

# Checked before every attack start (trigger-zone or random pick alike —
# see _tick_idle()) once at least cave_disruptor_min_attacks_between
# attacks have happened since the last one: rolls cave_disruptor_base_chance
# (or cave_disruptor_half_hp_chance at/below half HP) to preempt whatever
# was about to fire. Returns true (and the caller must return immediately)
# if it did.
func _maybe_start_cave_disruptor() -> bool:
	if _attacks_since_cave_disruptor < cave_disruptor_min_attacks_between:
		return false
	var chance = cave_disruptor_half_hp_chance if hp <= max_hp * 0.5 else cave_disruptor_base_chance
	if randf() >= chance:
		return false
	_attacks_since_cave_disruptor = 0
	_last_attack = 5
	_start_cave_disruptor()
	return true

# Entry point for both the trigger-zone path and the random pick — shows
# the WarnFlash heads-up on TailSlamTriggerZone before anything else
# happens (WARN_TAIL_SLAM's countdown in _physics_process calls the actual
# _start_tail_slam() once it finishes).
func _start_tail_slam_warning() -> void:
	state = State.WARN_TAIL_SLAM
	_state_timer = tail_warn_duration
	$TailSlamTriggerZone/WarnFlash.visible = true

# Computes where the tail's hit zone needs to land (position + angle) so
# it lands exactly on TailSlamTriggerZone regardless of distance from the
# hinge — shared by both the trigger-zone path and the random pick, same
# reason _start_charge_combo() below exists as a shared helper (previously
# only the trigger-zone branch set this up, so a randomly-picked Tail Slam
# would have swung with stale/empty target data).
func _start_tail_slam() -> void:
	var box_pos: Vector2 = $TailSlamTriggerZone/CollisionShape2D.global_position
	_tail_landed_angle = (box_pos - _tail.global_position).angle()
	# Land the hit zone's actual center on the box, not just the tip of
	# a fixed-length rotation — a hinge-only swing can only ever reach
	# as far out as the tail is long, so it'd fall short/overshoot
	# whenever the box isn't exactly that distance away.
	var hit_offset: Vector2 = $Tail/TailHitZone/CollisionShape2D.position
	_tail_landed_local_pos = to_local(box_pos - hit_offset.rotated(_tail_landed_angle))
	_start_telegraph(State.TELEGRAPH_TAIL, tail_telegraph_time)

# Shared setup for Charge Bite's 3-hit combo, used by both the trigger-zone
# path and the random-picked Retreat path — previously only the trigger-zone
# branch called this, so a randomly-picked Retreat entered CHARGE_BITE with
# an empty/stale _charge_targets array and silently whiffed or lunged at
# leftover coordinates.
func _start_charge_combo() -> void:
	_compute_charge_targets()
	_charge_step = 0
	_charge_pullback_origin = _head_home_pos
	_charge_pullback_dir = (_charge_targets[0] - _head_home_pos).normalized()
	_charge_pullback_dist = BITE_PULLBACK_DIST + CHARGE_FIRST_PULLBACK_EXTRA
	_start_telegraph(State.TELEGRAPH_CHARGE, charge_windup_time)

func _start_cave_disruptor() -> void:
	_start_telegraph(State.TELEGRAPH_CAVE, cave_disruptor_telegraph_time)

# Fires once per slam, right as the strike begins (see CAVE_SLAM_RISE's
# timer-expiry in _physics_process) — everyone currently inside
# CaveDisruptorArenaZone gets knocked straight up, no damage. Player uses
# the same apply_knockback() every other attack's knockback goes through;
# enemies get _pending_knockback set directly and guarded, matching the
# established convention (base_enemy.gd has no public apply_knockback()).
func _pulse_cave_disruptor_knockup() -> void:
	# Shakes the camera on every strike regardless of whether Elana is
	# actually inside the zone — it's the tail pounding the cave floor, not
	# a hit reaction, so it should read the same way play_roar_shake()'s
	# camera trauma does.
	_shake_player_camera(0.5)
	for body in $CaveDisruptorArenaZone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(0, cave_disruptor_knockup_y))
		elif body != self and body.is_in_group("enemies") and "_pending_knockback" in body:
			body._pending_knockback = Vector2(0, cave_disruptor_knockup_y)

# Shared lookup for the player's camera-trauma system (elana.gd) — used for
# attack-impact shakes that aren't conditioned on actually hitting Elana
# (bite's lunge-launch, each Cave Disruptor tail pound), unlike the
# hit-reactive add_camera_trauma() calls in _on_bite_zone_body_entered()/
# _on_tail_hit_zone_body_entered() which only fire when the attack connects.
func _shake_player_camera(amount: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("add_camera_trauma"):
		player.add_camera_trauma(amount)

# Drives both the sprite frame and the Hurtbox's CollisionPolygon2D off a
# single source — CollisionAnimationPlayer's matching animation (same name
# as the SpriteFrames one) now keys AnimatedSprite2D:frame itself, timed to
# match each frame's real duration/speed from SpriteFrames. Deliberately
# NOT calling _body_sprite.play() here anymore — that starts its own
# internal auto-advance, which would fight this animation over the same
# frame property every tick. Setting .animation (not .play()) just selects
# which SpriteFrames sub-animation frame indices resolve against, without
# starting its playback.
func _play_body_anim(anim_name: String) -> void:
	_body_sprite.animation = anim_name
	if _collision_anim.has_animation(anim_name):
		_collision_anim.play(anim_name)
	else:
		# No collision animation for this attack yet — fall back to letting
		# the sprite drive its own frames normally rather than freezing on
		# frame 0 with nothing advancing it.
		_body_sprite.play(anim_name)

# Ticked from both CAVE_SLAM_RISE and CAVE_SLAM_STRIKE so rocks keep
# falling continuously through the whole multi-slam phase rather than only
# during one half of each slam. Spawns up to rock_count total, in bursts of
# rock_burst_min..rock_burst_max at once (not always a lone rock) so
# several can land close together, not just one-by-one. Gap between bursts
# is randomized (rock_spawn_interval_min/max), not a fixed beat.
func _tick_cave_rock_spawn(delta: float) -> void:
	if _cave_rocks_spawned >= rock_count:
		return
	_cave_rock_timer -= delta
	if _cave_rock_timer > 0.0:
		return
	_cave_rock_timer = randf_range(rock_spawn_interval_min, rock_spawn_interval_max)
	var burst_size: int = min(randi_range(rock_burst_min, rock_burst_max), rock_count - _cave_rocks_spawned)
	for i in burst_size:
		_spawn_cave_rock()
	_cave_rocks_spawned += burst_size

# Spawns at a random X position across CaveDisruptorArenaZone's actual
# width, falling from above straight down to the zone's bottom edge (the
# placeholder "arena floor" — there's no real arena yet) where it explodes.
func _spawn_cave_rock() -> void:
	var bounds: Rect2 = _zone_bounds($CaveDisruptorArenaZone/CollisionShape2D)
	var floor_y: float = bounds.end.y
	var spawn_x: float = randf_range(bounds.position.x, bounds.end.x)
	var rock = ROCK_SCENE.instantiate()
	# get_parent().to_local(...) — NOT self.to_local(...). The rock becomes a
	# child of get_parent() (the boss's own parent, a sibling relationship),
	# not a child of the boss itself like Head/Tail are — self.to_local()
	# would resolve into the boss's own local space instead, which is only
	# correct for Head/Tail's targets (_compute_charge_targets(),
	# _start_tail_slam()) precisely because those two really are children of
	# the boss. Using the wrong one here is what made rocks spawn far from
	# the actual box whenever the boss itself sits away from its parent's
	# origin. Setting global_position directly would have the same "not
	# parented yet" unreliability problem noted elsewhere this session.
	rock.position = get_parent().to_local(Vector2(spawn_x, floor_y - rock_spawn_height_above_floor))
	rock.target_y = floor_y
	rock.fall_speed = rock_fall_speed
	rock.damage = rock_damage
	rock.explosion_radius = rock_explosion_radius
	get_parent().call_deferred("add_child", rock)

# Left/mid/right of the trigger box's actual CollisionShape2D, in the same
# local space Head's own .position uses (root's local space) — matches
# to_local() usage everywhere else this session for runtime-computed
# targets.
func _compute_charge_targets() -> void:
	var shape_node: CollisionShape2D = $ChargeBiteTriggerZone/CollisionShape2D
	var center: Vector2 = shape_node.global_position
	var half_width: float = shape_node.shape.size.x / 2.0
	# 1st and 3rd both pulled 50px toward center from the trigger box's raw
	# edges — narrows the combo's spread a bit rather than lunging all the
	# way out to the box's actual corners.
	_charge_targets = [
		to_local(center + Vector2(-half_width + CHARGE_TARGET_INSET, 0)),
		to_local(center),
		to_local(center + Vector2(half_width - CHARGE_TARGET_INSET, 0)),
	]

func _start_telegraph(next_state: State, duration: float) -> void:
	state = next_state
	_state_timer = duration
	modulate = TELEGRAPH_TINT

func _start_retreat() -> void:
	state = State.RETREAT
	_state_timer = 0.4
	modulate = TELEGRAPH_TINT

func _launch_telegraphed_attack() -> void:
	modulate = Color.WHITE
	_hit_this_attack = false
	match state:
		State.TELEGRAPH_BITE:
			state = State.BITE
			_state_timer = 0.35
			_shake_player_camera(0.5)
			_play_body_anim("bite_attack")
		State.TELEGRAPH_CHARGE:
			state = State.CHARGE_BITE
			_state_timer = charge_active_time
			# Also re-fires for hits 2/3 (CHARGE_HOLD re-enters TELEGRAPH_CHARGE
			# per remaining combo step) — play() on an already-playing animation
			# of the same name is a no-op in Godot, not a restart, so this is
			# safe to call once per hit rather than only on the first.
			_play_body_anim("charge_attack")
		State.TELEGRAPH_SPIT:
			# state set BEFORE firing, not after — _fire_spit_volley() checks
			# state == State.SPIT on every shot (including the first, which
			# runs synchronously up to its first await, before this function
			# returns), so it needs to already be correct by then.
			state = State.SPIT
			_state_timer = 1.2
			_fire_spit_volley()
		State.TELEGRAPH_TAIL:
			state = State.TAIL_SLAM
			_state_timer = tail_active_time
			_tail_hit_bodies.clear()
			_play_body_anim("tail_slam")
		State.TELEGRAPH_EJECT:
			state = State.EJECT_HOLD
			_state_timer = eject_pre_fire_hold_time
		State.TELEGRAPH_CAVE:
			_cave_slam_step = 0
			_cave_rocks_spawned = 0
			_cave_rock_timer = randf_range(rock_spawn_interval_min, rock_spawn_interval_max)
			state = State.CAVE_SLAM_RISE
			_state_timer = cave_disruptor_rise_time
			_play_body_anim("cave_disruptor")

# Fires one shot at a time (spit_count of them, spit_fire_interval apart)
# instead of all at once — each shot re-aims fresh at the target's CURRENT
# position right when IT fires, not a single snapshot taken when the volley
# starts, so a fast-moving player actually shifts where later shots in the
# volley go. Not awaited by its caller (_launch_telegraphed_attack()) — the
# SPIT state's own _state_timer (1.2s) covers the whole staggered sequence
# (spit_count - 1 intervals, 0.6s at default values, plus travel time)
# independently of this coroutine.
func _fire_spit_volley() -> void:
	_spit_volley_pending.clear()
	for i in spit_count:
		var target = _get_target()
		if not target:
			return
		if not is_instance_valid(self) or state != State.SPIT:
			return
		# Head's own local position relative to the shared parent (root's
		# position + Head's offset from root), not the root/belly's own
		# position — same "local position matched to the future shared parent"
		# pattern used for every other runtime-spawned node this session.
		var head_root_pos = position + _head.position
		var spit = SPIT_SCENE.instantiate()
		var spread = deg_to_rad(randf_range(-15.0, 15.0))
		var aim_dir = (target.global_position - _head.global_position).rotated(spread).normalized()
		spit.aim_direction = aim_dir
		spit.damage = spit_damage
		spit.source = self
		spit.position = head_root_pos + aim_dir * 60.0
		spit.resolved.connect(_on_spit_resolved.bind(spit))
		_spit_volley_pending.append(spit)
		get_parent().call_deferred("add_child", spit)
		if i < spit_count - 1:
			await get_tree().create_timer(spit_fire_interval).timeout

# Spikes launch from wherever the head has ducked to (target above pulls it
# toward the body's own collision center during the telegraph) out to
# random points scattered across EjectSpikesTriggerZone's actual box —
# "eject spikes to the middle part at random spots", not aimed at the
# player.
func _fire_eject_spikes() -> void:
	var shape_node: CollisionShape2D = $EjectSpikesTriggerZone/CollisionShape2D
	var center: Vector2 = shape_node.global_position
	var half_size: Vector2 = shape_node.shape.size / 2.0
	var launch_global_pos: Vector2 = _head.global_position
	# Local position matched to the shared future parent, same pattern as
	# _fire_spit_volley()'s head_root_pos.
	var launch_local_pos: Vector2 = position + _head.position
	for i in spike_count:
		var target_global = center + Vector2(
			randf_range(-half_size.x, half_size.x),
			randf_range(-half_size.y, half_size.y)
		)
		var aim_dir = (target_global - launch_global_pos).normalized()
		var spike = SPIKE_SCENE.instantiate()
		spike.aim_direction = aim_dir
		spike.damage = spike_damage
		spike.source = self
		spike.position = launch_local_pos + aim_dir * 20.0
		get_parent().call_deferred("add_child", spike)

# A resolved spit stops counting; whatever it hatched starts counting in
# its place. Spit stays gated until this whole list drains empty.
func _on_spit_resolved(swarmer: Node, spit: Node) -> void:
	_spit_volley_pending.erase(spit)
	if swarmer:
		_spit_volley_pending.append(swarmer)

func _spit_volley_ready() -> bool:
	_spit_volley_pending = _spit_volley_pending.filter(func(e): return is_instance_valid(e))
	return _spit_volley_pending.is_empty()

func _start_recover() -> void:
	state = State.RECOVER
	_state_timer = 0.5
	_attack_cooldown = attack_cooldown_time
	# Single choke point every attack path (Bite, Charge Bite, Spit, Tail
	# Slam, Eject Spikes, Cave Disruptor) converges through before returning
	# to IDLE — one place to hand the sprite back to idle instead of adding
	# an "idle" call at each attack's own individual end point.
	_play_body_anim("idle")

# Called by the Head child node when it takes a hit — the shared HP pool,
# not a separate one on the head itself.
func apply_boss_damage(damage: int) -> void:
	if hp <= 0:
		return
	hp -= damage
	GameData.spawn_damage_number(damage, _head.global_position, Color(1.0, 0.9, 0.2))
	_flash_hit()
	if hp <= 0:
		_die()

func _flash_hit() -> void:
	_flash_material.set_shader_parameter("flash_amount", 1.0)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self):
		_flash_material.set_shader_parameter("flash_amount", 0.0)

# Public — used by the boss-arena reveal cutscene (dialog_marker.gd) to
# bound the camera's horizontal follow to the arena instead of locking it
# outright. Uses CaveDisruptorArenaZone as the stand-in for the real arena
# (there isn't one yet).
# Shared by get_arena_bounds(), get_camera_bounds(), and _spawn_cave_rock()
# — turns any box-shaped trigger zone's CollisionShape2D into a world-space
# Rect2, so the center/half-size math only lives in one place.
func _zone_bounds(shape_node: CollisionShape2D) -> Rect2:
	var center: Vector2 = shape_node.global_position
	var half_size: Vector2 = shape_node.shape.size / 2.0
	return Rect2(center - half_size, half_size * 2.0)

# Right edge of the body collider at its vertical center, derived from
# $CollisionShape2D's own polygon bounding box — used by Eject Spikes' duck
# target above. Replaces the old `$CollisionShape2D.shape.size` read from
# when that node was a plain RectangleShape2D-backed CollisionShape2D
# instead of the CollisionPolygon2D it is now (matching the traced sprite
# silhouette, same as Hurtbox's own CollisionPolygon2D).
# $CollisionShape2D's concave polygon (matching the traced sprite
# silhouette, see Hurtbox's own CollisionPolygon2D) is fine for an Area2D
# (Hurtbox) doing pure overlap detection, but Godot's move_and_slide()
# collision resolution doesn't handle a concave solid collider well — a
# player embedded in one of its "dents" gets shoved out unpredictably (a
# large, instant-looking pop) the moment anything re-triggers physics
# resolution, instead of a clean push. Disabling that single concave shape
# and decomposing the same polygon into several convex pieces (Godot's own
# Geometry2D utility) keeps the exact same overall silhouette while giving
# the physics engine shapes it can actually resolve correctly.
# Removes consecutive near-duplicate points (distance below MIN_EDGE_LEN) —
# a hand-edited/traced polygon like this one can easily have two points
# sitting almost on top of each other, creating a near-zero-length edge.
# decompose_polygon_in_convex() can turn that into a convex piece that's
# fine by area but still has one degenerate edge, which is enough to break
# move_and_slide()'s collision-normal math (the actual NaN-velocity source
# — see _build_convex_body_collision()). Cleaning the source polygon before
# decomposition instead of only filtering pieces after.
const MIN_EDGE_LEN: float = 2.0

func _clean_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var cleaned := PackedVector2Array()
	for p in poly:
		if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_to(p) >= MIN_EDGE_LEN:
			cleaned.append(p)
	# Wrap-around edge (last point back to first) needs the same check.
	if cleaned.size() > 1 and cleaned[0].distance_to(cleaned[cleaned.size() - 1]) < MIN_EDGE_LEN:
		cleaned.remove_at(cleaned.size() - 1)
	return cleaned

func _build_convex_body_collision() -> void:
	var concave_polygon: PackedVector2Array = _clean_polygon($CollisionShape2D.polygon)
	$CollisionShape2D.disabled = true
	var pieces = Geometry2D.decompose_polygon_in_convex(concave_polygon)
	var kept := 0
	for piece in pieces:
		var area: float = _polygon_area(piece)
		# A degenerate piece (fewer than 3 points, or effectively zero area —
		# both possible outputs of decomposing a hand-edited polygon with
		# near-duplicate/collinear points) can make move_and_slide()'s
		# collision-separation math divide by a near-zero normal, producing
		# NaN velocity that then poisons global_position permanently (NaN
		# never self-corrects) — matches the reported "everything goes
		# blank" bug exactly. Skipping bad pieces instead of trusting the
		# decomposition output unconditionally. Confirmed via a one-off debug
		# dump that all 49 pieces here are clean (strictly convex, healthy
		# area) — this filter is now just a defensive backstop, not the
		# active fix (the real NaN source turned out to be elsewhere).
		if piece.size() < 3 or abs(area) < 1.0:
			continue
		var convex_shape := CollisionPolygon2D.new()
		convex_shape.polygon = piece
		add_child(convex_shape)
		_body_collision_pieces.append(convex_shape)
		kept += 1

# Shoelace formula — used only to reject degenerate decomposition output
# above (near-zero-area slivers), not for anything gameplay-visible.
func _polygon_area(poly: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return area / 2.0

func _body_duck_target() -> Vector2:
	var poly: PackedVector2Array = $CollisionShape2D.polygon
	var min_x: float = poly[0].x
	var max_x: float = poly[0].x
	var min_y: float = poly[0].y
	var max_y: float = poly[0].y
	for p in poly:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	return Vector2(max_x, (min_y + max_y) / 2.0)

func get_arena_bounds() -> Rect2:
	return _zone_bounds($CaveDisruptorArenaZone/CollisionShape2D)

# Same shape as get_arena_bounds(), but reads a separate, manually-editable
# CameraBoundsZone instead of CaveDisruptorArenaZone — lets the camera's
# horizontal range be tuned independently of the Cave Disruptor
# knockup/rock-drop area, since they don't need to match.
func get_camera_bounds() -> Rect2:
	return _zone_bounds($CameraBoundsZone/CollisionShape2D)

const ROAR_SHAKE_DURATION: float = 0.5
const ROAR_SHAKE_MAGNITUDE: float = 8.0

# Public — used by the boss-arena reveal cutscene (dialog_marker.gd) during
# the pan-left hold, as if the roar itself is rattling the head. Pure
# visual jitter around _head_home_pos, no gameplay effect (doesn't touch
# hp/attacks/state) — safe to call any time the boss is IDLE.
func play_roar_shake() -> void:
	# Reentrancy guard (a second overlapping call would let the first call's
	# finish clear _roaring out from under the still-running second jitter
	# loop) plus the actual "safe when IDLE" precondition above — BITE_HOLD/
	# BITE_RETURN/BITE_STUNNED/CHARGE_HOLD/CHARGE_RETURN all write
	# _head.position directly every physics frame themselves (not gated by
	# _roaring, unlike the generic idle lerp in _update_head_bite_visual()),
	# so jittering during any of them would fight that write instead of
	# riding alongside it.
	if _roaring or state in [State.CHARGE_HOLD, State.CHARGE_RETURN, State.BITE_HOLD, State.BITE_RETURN, State.BITE_STUNNED]:
		return
	_roaring = true
	var elapsed: float = 0.0
	while elapsed < ROAR_SHAKE_DURATION:
		_head.position = _head_home_pos + Vector2(
			randf_range(-ROAR_SHAKE_MAGNITUDE, ROAR_SHAKE_MAGNITUDE),
			randf_range(-ROAR_SHAKE_MAGNITUDE, ROAR_SHAKE_MAGNITUDE)
		)
		await get_tree().create_timer(0.04).timeout
		elapsed += 0.04
	_head.position = _head_home_pos
	_roaring = false

# Same "★★★" floating label charger.gd's own self-stun uses. Timed off
# bite_stun_duration directly rather than await-ing that duration itself,
# so it can't drift out of sync if bite_stun_duration is tuned later.
func _show_bite_stun_indicator() -> void:
	if is_instance_valid(_bite_stun_indicator):
		return
	_bite_stun_indicator = GameData.make_stun_indicator()
	_head.add_child(_bite_stun_indicator)
	await get_tree().create_timer(bite_stun_duration).timeout
	if is_instance_valid(_bite_stun_indicator):
		_bite_stun_indicator.queue_free()
		_bite_stun_indicator = null

func _die() -> void:
	GameData.gain_xp(xp_reward)
	GameData.reset_boss_camera()
	boss_died.emit()
	queue_free()

# Body Hurtbox — armored, high defense. Standard on_hit/on_elemental_hit
# interface (same shape hit_handler.gd's is), routed through the shared
# apply_boss_damage() rather than its own separate hp.
func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	var final_damage = GameData.calc_damage(float(damage), float(body_defense))
	apply_boss_damage(final_damage)

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

# Generic chain_projectile.gd hook, same one charger.gd uses — the chain
# hit still lands (damage goes through on_hit() above regardless), but the
# actual grapple/pull-in never starts. A 512px boss getting reeled in by a
# chain hook wouldn't make sense anyway, and chain_projectile.gd's pull
# writes directly to is_stunned/_pending_knockback — base_enemy.gd fields
# Hollowfang doesn't declare (extends CharacterBody2D directly) — so
# without this, every pull attempt on it would also error.
func blocks_chain_pull() -> bool:
	return true

# Public — called by dialog_marker.gd's Boss 1 Drop Entrance cutscene
# (BOSS1_DROP_ENTRANCE), which now always re-fires on every fresh trigger-
# zone entry (no one-time flag on the cutscene side either — see
# dialog_marker.gd). Guarded by an actual live-node check (_entrance_gate),
# not a plain "was one ever dropped" flag — a warhammer can break the gate
# open once the boss is dead, and if the cutscene ever fires again after
# that (or after a scene reload, where _entrance_gate naturally resets to
# null on a fresh instance), a stale "already dropped" boolean would
# permanently block a replacement from ever spawning even though the
# entrance is standing wide open. pos is the raw spot to seal (already
# offset applied here, callers don't need to know ROCK_GATE_Y_OFFSET).
func drop_entrance_gate(pos: Vector2) -> void:
	if is_instance_valid(_entrance_gate):
		return
	var gate = ROCK_GATE_SCENE.instantiate()
	# rock_gate.tscn's root node is always named "RockGate" by default — every
	# dynamically-spawned gate would share that exact same name unless
	# renamed. vine_gate.gd's own _ready() (inherited here) checks
	# GameData.is_removed(scene_path, name) and queue_free()s itself if a
	# gate with that name was ever marked removed before (e.g. a previous
	# entrance gate broken open with a warhammer earlier in the same
	# session) — so a shared name meant every FRESH gate silently
	# self-destroyed the instant its own _ready() ran, one frame after
	# being added, regardless of this function working perfectly. Renamed
	# before it's ever added to the tree so its own removal record can't
	# collide with any other gate's.
	gate.name = "HollowfangEntranceGate"
	# call_deferred, not a direct add_child — same reason every other
	# runtime-spawned node in this file uses it (_spawn_cave_rock(),
	# _fire_spit_volley(), _fire_eject_spikes()). position (local), not
	# global_position, computed here BEFORE deferring — safe to set
	# immediately on a not-yet-parented node, unlike global_position which
	# depends on a transform hierarchy that doesn't exist until it's
	# actually in the tree.
	gate.position = get_tree().current_scene.to_local(pos + Vector2(ROCK_GATE_X_OFFSET, ROCK_GATE_Y_OFFSET))
	gate.boss_ref = self
	_entrance_gate = gate
	get_tree().current_scene.call_deferred("add_child", gate)

# hollowfang_spike.gd/hollowfang_spit.gd exclude their own spawning body from
# terrain collision (source == self) so they don't instantly "land" on the
# boss they were just fired from — but they spawn right next to Head, well
# inside HeadCollision's own separate solid body, which that plain
# `body == source` check doesn't cover. Both scripts call this instead, so
# any current or future solid sub-part (just the head for now) gets excluded
# the same way without needing to know about it individually.
func owns_body(body: Node) -> bool:
	return body == self or body == $Head/HeadCollision

# Opt-in hook for short-range targeting systems that pick a target by
# distance to plain global_position (e.g. elana.gd's Electric Herb bolt +
# chain lightning, both of which use a ~125-150px range check). A single
# center point (originally $CollisionShape2D's) still isn't enough for a
# creature this size — head to tail spans 800px+, well beyond any short-
# range check no matter which single point is picked. ElecTarget1-5 are
# plain Marker2D nodes placed by hand in the editor — elana.gd picks
# whichever is closest, so electric can connect near any part of the boss
# instead of only near one fixed spot.
func get_targeting_points() -> Array:
	return [
		$Head/ElecTarget1.global_position, $ElecTarget2.global_position, $Head/ElecTarget3.global_position,
		$ElecTarget4.global_position, $ElecTarget5.global_position,
	]
