extends CharacterBody2D

# Boss 3 — THE BROODSPAWNER (renamed 2026-08-20 from Broodmother; see
# project backlog for the full design doc reference). extends
# CharacterBody2D directly — same "too different a shape for enemy.gd" call
# Hollowfang/Elemander made, no ordinary melee at all, every attack is a
# named special. Creature-only scope for this build (no arena/plug/cave
# route/entrance cutscene yet — same precedent Hollowfang's own creature
# build set).
#
# Two states:
#   UP (default) — spits eggs at intervals (become swarm-hatching eggs on
#     terrain contact) and periodically summons a line of 8 floor-eggs.
#     Vulnerable web anchors are up during this phase; destroying all of
#     them forces her DOWN.
#   DOWN — grounded, actively attacks (Venom Bite/Leg Pierce/Poison Spit,
#     randomly picked), no eggs/anchors. Auto-returns UP after a fixed
#     duration, knocking everything back around her on the way up. Fresh
#     anchors spawn again once back UP, so the cycle repeats.
#
# Physically confined to web ground, per-layer, PURELY by hazard label
# (2026-08-20, reworked 2026-08-21 into per-layer physics bits, reworked
# AGAIN 2026-08-21 same session into this — user explicit requirement,
# verbatim: "spider will not collide to any terrain unless its hazard is
# webFloor1-4" / "i want to remove collision first on webwall. and that
# thing on layer mask" / "have collision with the hazard type that was set
# to collide"). root collision_mask is permanently 0 — Godot's real physics
# engine plays NO role in stopping her anymore, for floors or walls. Instead
# _apply_gravity() manually reads the actual "hazard" custom-data value on
# the tile at her feet every frame (via terrain_path, see
# _get_hazard_at_feet()) and only stops her falling if it exactly matches
# WEBFLOOR_HAZARD_NAMES[_current_floor_layer] OR WEBBRIDGE_HAZARD_NAMES[
# _current_floor_layer] (2026-08-21, user request — webBridgeN tiles count
# as real ground for layer N exactly like webFloorN does) — nothing else
# counts, not a physics polygon, not any other tile, nothing.
# _current_floor_layer (default 0/"webFloor1" from _ready()) is changed by
# _set_active_floor_layer() whenever she ascends/descends (see the "Layer
# Jumping" export group).
# webWall collision was removed in this same pass and has no replacement
# yet — nothing currently blocks her horizontally at all.
#
# Not physically solid to anyone (2026-08-20 fix): root collision_layer = 0.
# Originally copied Hollowfang's collision_layer = 3, but that's specific to
# HIS design — his body IS the arena floor, meant to be stood on. Broodspawner
# was never meant to work that way; bit 1 of that value is the shared terrain
# layer, which let Elana and enemies stand on top of her. Zeroed out so
# nobody's move_and_slide() ever treats her as solid — everyone (Elana,
# enemies) passes straight through her body. Her own collision_mask above is
# unrelated (what SHE stands on), untouched by this.

# The one and only authority for whether she can stand somewhere (2026-08-21
# — see the header comment above for the full history of why this replaced
# the physics-bit system entirely). No physics_layer/collision_mask
# involvement left at all for floors.
# Capitalized "webFloor1"/etc, NOT all-lowercase "webfloor1" (2026-08-21 fix)
# -- string comparison is case-sensitive, and the real painted tiles use
# capital F (confirmed via GRAVITY CHECK log: actual_hazard="webFloor1"
# never matched the all-lowercase expected_hazard this const used to have,
# even though everything else was working correctly by that point). Matches
# the "webFloor"/"webWall" capitalization convention already established
# earlier this session for the original single (pre-per-layer) tag.
# Layers 2-4's real capitalization hasn't been confirmed the same way yet
# (no painted tiles for them at time of writing) -- assumed to follow the
# same "webFloorN" convention, fix if that turns out wrong once painted.
const WEBFLOOR_HAZARD_NAMES: Array[String] = ["webFloor1", "webFloor2", "webFloor3", "webFloor4"]
# Second valid tag per layer (2026-08-21, user request: "add behaviour for
# tiles tagged as webBridge1 with webFloor1 and so on... spider can walk on
# them too when active") -- webBridgeN counts as real ground for layer N
# exactly the same as webFloorN does, checked alongside it in
# _apply_gravity(). Same capitalization convention/caveat as
# WEBFLOOR_HAZARD_NAMES above -- not yet confirmed against a real painted
# webBridge tile.
const WEBBRIDGE_HAZARD_NAMES: Array[String] = ["webBridge1", "webBridge2", "webBridge3", "webBridge4"]

@export var max_hp: int = 1200
@export var defense: int = 50
@export var xp_reward: int = 300
# Bulwark's reflect code (elana.gd's take_damage()) assumes every member of
# the "enemies" group has this, since every base_enemy.gd-derived enemy
# does — Hollowfang and Elemander both declare their own for the same
# reason (2026-08-20 fix: missing here caused a crash on Venom Bite landing
# a hit while Bulwark was active).
var direction: int = 1

@export_group("Arena References")
# ArenaBox/ArenaFloorZone are independent siblings placed directly in the
# level scene (2026-08-20, user request — "make it independent") rather
# than children of this scene. She now actually moves during DOWN (chasing/
# lunging/knockback); these represent fixed room geometry — the arena
# trigger and the floor line eggs pop up along — and shouldn't track her
# position. Wire these NodePaths per-placement in the editor after
# instancing her (drag the sibling nodes in from the level scene's tree).
@export var arena_box_path: NodePath
@export var arena_floor_zone_path: NodePath
# 4-layer arena support (2026-08-21, user design) — each entry is a wide
# Area2D+CollisionShape2D (RectangleShape2D) spanning one vertical platform
# layer's full playable space, same independent-sibling convention as
# ArenaBox/ArenaFloorZone above. Order doesn't matter — layers are looked up
# by whichever one's bounds actually contain a given position, not by index
# meaning "higher."
@export var platform_layer_paths: Array[NodePath] = []
# The level's Terrain TileMap (2026-08-21, user requirement: "SPIDER COLLIDES
# WITH TERRAIN. ONLY IF HAZARD IS WEBFLOOR1-4... dont collide by other
# terrain aside fom that hazard value"). Needed to read a tile's actual
# "hazard" custom-data value at runtime -- see _get_hazard_at_feet(). Wire
# to the same "Terrain" TileMap node terrain_hazards.gd is attached to.
@export var terrain_path: NodePath

@export_group("Web Anchors")
@export var anchor_count: int = 4
# TEMPORARY for testing (2026-08-21, user explicit: "temporarily") — how
# many of the anchor_count strands need to be cut before she drops DOWN.
# Set back to match anchor_count (4) to restore "all of them" later.
@export var anchors_required_to_fall: int = 1
# Fallback layout only, used per-index if a given WebAnchorPointN marker is
# missing — evenly spaced along a horizontal line (2026-08-20, "make anchor
# points more like a line" — was a circle before that).
@export var anchor_fallback_spacing: float = 200.0
@export var anchor_fallback_y: float = 180.0

@export_group("UP - Spit Eggs")
# Disabled 2026-08-20, user request ("for now") — re-enable when ready.
@export var spit_enabled: bool = false
@export var spit_interval: float = 10.0
@export var spit_egg_hatch_time: float = 10.0
# Aimed at Elana's general direction (2026-08-20, superseding the earlier
# "bottom-half fan"/"only downwards" asks) — not a laser-precise lock onto
# her exact spot, randomized within this full spread each spit.
@export var spit_aim_spread_deg: float = 50.0

@export_group("UP - Floor Eggs")
# Disabled 2026-08-20, user request ("for now") — re-enable when ready.
@export var floor_eggs_enabled: bool = false
@export var floor_egg_interval: float = 20.0
@export var floor_egg_hatch_time: float = 7.0
# Spread is normally driven by ArenaFloorZone's actual width (see
# _do_floor_eggs()) — this is only the fallback if that node's ever missing.
@export var floor_egg_spacing: float = 60.0

@export_group("DOWN")
@export var down_duration: float = 150.0
@export var down_attack_gap: float = 2.5
@export var down_to_up_knockback: float = 300.0
@export var down_to_up_knockback_radius: float = 232.0
@export var down_to_up_windup: float = 1.0
# Landing (UP->DOWN transition) — 2026-08-20, user request.
@export var down_landing_stun: float = 2.0
@export var down_landing_knockback: float = 300.0
@export var down_landing_knockback_radius: float = 232.0
@export var down_chase_speed: float = 90.0
# Stops closing the gap once within this horizontal distance (2026-08-20,
# user request — no need to walk until their bodies are centered on top of
# each other, just close enough to stay in attack range).
@export var down_chase_stop_distance: float = 260.0
# Holds still for this long after any attack finishes before chasing
# resumes (2026-08-20, user request) — without it, chase logic re-engages
# the instant _is_using_attack clears, reading as the lunge continuing
# straight into a walk.
@export var down_post_attack_pause: float = 0.5

@export_group("Layer Jumping")
# FULL REWORK 2026-08-21, user design ("remake this shit... real velocity
# jump when going up... enable the target layer collision at the highest
# point of the jump... for descend, remove collision of current layer, then
# enable the target layer"). Replaces the earlier fully-scripted position-
# teleport system (which guessed a landing Y via layer_jump_landing_overshoot
# — see git history) with real gravity: _current_floor_layer (see
# _set_active_floor_layer()) tracks which layer she's meant to be able to
# land on, and _apply_gravity() manually checks the actual hazard label at
# her feet each frame to decide whether to stop her (see the header comment
# — no physics_layer/collision_mask involvement left for this at all,
# reworked a second time same session away from an earlier per-layer-bit
# version).
# - Ascending (target layer is physically higher/higher index): dips DOWN
#   first as a scripted anticipation crouch (layer_jump_ascend_dip_distance
#   over layer_jump_ascend_dip_duration, unchanged from before), then a REAL
#   upward velocity push (layer_jump_ascend_base_velocity plus
#   layer_jump_ascend_velocity_increment per extra layer crossed) with every
#   floor bit
#   disabled so she passes clean through whatever she's climbing past — only
#   webWall can stop her. The instant she crests (velocity.y goes from
#   negative to >= 0), the target layer's floor bit turns on and real gravity
#   takes over from there — see _do_ascend_jump().
# - Descending (target layer is physically lower/lower index): no scripted
#   movement at all, just swaps which floor bit is active and lets real
#   gravity carry her down — see _do_descend_jump().
# - The initial UP->DOWN drop (_go_down()) uses the same _do_descend_jump()
#   as any other descend now, targeting Platform Layer 1 (index 0) — no
#   longer a separate scripted-duration fall.
@export var layer_jump_ascend_dip_distance: float = 20.0
@export var layer_jump_ascend_dip_duration: float = 0.2
# Scales with how many layers she's crossing (2026-08-22, user design,
# retuned twice same session -- current values: base 680 for a 1-layer jump,
# 880 for 2 layers, 1080 for 3 layers). Actual push is base + increment ×
# (layers_crossed - 1), computed fresh each ascend in _do_ascend_jump()
# (target_layer - _current_floor_layer, captured before anything else
# changes _current_floor_layer).
@export var layer_jump_ascend_base_velocity: float = 680.0
@export var layer_jump_ascend_velocity_increment: float = 200.0
# Safety cutoffs, not tuned gameplay feel -- just guard against her never
# reaching a peak (ascend_timeout) or never actually landing because a
# target layer's floor isn't painted yet (fall_timeout), so a transition
# can't leave her permanently stuck mid-air with chase/attacks locked out.
@export var layer_jump_ascend_timeout: float = 2.0
@export var layer_jump_fall_timeout: float = 3.0
# Debounces the jump trigger (2026-08-21, user design) -- instead of jumping
# the instant a layer mismatch is seen, the mismatched layer gets remembered
# and this much time has to pass with Elana STILL on that same layer before
# she actually commits to the jump. If Elana moves to yet another layer
# during the wait, the remembered layer/timer both reset to the new one and
# the wait starts over -- repeats until Elana holds still on one layer for a
# full uninterrupted window. Stops her flickering/re-triggering off Elana
# briefly crossing layers. See _pending_jump_target_layer/_pending_jump_timer
# and _apply_horizontal_movement().
@export var layer_jump_detection_delay: float = 2.0

@export_group("Venom Bite")
@export var venom_bite_enabled: bool = false
# Windup is now pullback + a brief motionless hold before the lunge fires
# (2026-08-20, user request).
@export var venom_bite_windup: float = 0.2
@export var venom_bite_windup_hold: float = 0.1
# Bumped further back on windup, and the lunge covers more ground
# (2026-08-20, user request).
@export var venom_bite_windup_pullback: float = 20.0
@export var venom_bite_lunge_speed: float = 420.0
@export var venom_bite_lunge_time: float = 0.05
@export var venom_bite_damage: int = 14
@export var venom_bite_poison_damage: int = 3
@export var venom_bite_poison_ticks: int = 4
@export var venom_bite_knockback: float = 200.0
# Mini stun on hit (2026-08-20, user request) — elana.gd's own public
# apply_stun(duration).
@export var venom_bite_stun: float = 0.5

@export_group("Leg Pierce")
# Disabled 2026-08-20, user request — only Venom Bite for now.
@export var leg_pierce_enabled: bool = true
@export var leg_pierce_windup: float = 0.3
@export var leg_pierce_windup_pullback: float = 10.0
# Rotation swing replaces the earlier vertical rise/drop entirely
# (2026-08-20, user request: "ignore the slam position i said earlier") —
# LegPierceZone rotates to this angle during the windup, then back to its
# original rotation during the slam.
@export var leg_pierce_rotate_angle_deg: float = -40.0
# Shifts LegPierceZone itself backward (opposite facing) during the windup,
# alongside the rotation, then back to rest during the slam — 2026-08-20,
# user request ("move the leg to the left on windup").
@export var leg_pierce_windup_zone_shift: float = 25.0
@export var leg_pierce_slam_time: float = 0.2
# How far forward of her original (pre-windup) spot she ends up once the
# slam lands — 2026-08-20, user request: undo the windup pullback and then
# some, instead of just snapping back to where she started.
@export var leg_pierce_slam_forward_shift: float = 15.0
@export var leg_pierce_slam_camera_shake: float = 0.4
@export var leg_pierce_damage: int = 20
@export var leg_pierce_knockback: float = 220.0
# Was a hardcoded -120 inline, not even tunable — bumped and exposed
# (2026-08-21, user request: "make it prominent, I don't see it much").
@export var leg_pierce_knockup: float = 320.0

@export_group("Poison Spit")
# Disabled 2026-08-20, user request — only Venom Bite for now.
@export var poison_spit_enabled: bool = false
@export var poison_spit_windup: float = 0.7
@export var poison_spit_count: int = 4
@export var poison_spit_spread_deg: float = 40.0

const SPIT_EGG_SCENE = preload("res://broodspawner_spit_egg.tscn")
const FLOOR_EGG_SCENE = preload("res://broodspawner_floor_egg.tscn")
const WEB_STRAND_SCENE = preload("res://web_strand.tscn")
const POISON_PROJECTILE_SCENE = preload("res://broodspawner_poison_projectile.tscn")
const CHARGER_SCENE = preload("res://charger.tscn")
const SHIELD_BEARER_SCENE = preload("res://shield_bearer.tscn")
const WARRIOR_ANT_SCENE = preload("res://warrior_ant.tscn")
const NORMAL_ENEMY_SCENE = preload("res://enemy.tscn")
# Outermost to innermost on each side, mirrored — matches the user's exact
# spec: "charger shielder warrior normalEnemy _____ normalEnemy warrior
# shielder charger" read left to right across all 8 positions.
const FLOOR_EGG_TYPES: Array[PackedScene] = [CHARGER_SCENE, SHIELD_BEARER_SCENE, WARRIOR_ANT_SCENE, NORMAL_ENEMY_SCENE]

const TINT_BASE: Color = Color(1.0, 1.0, 1.0, 1.0)
const TINT_DOWN: Color = Color(0.85, 0.6, 0.75, 1.0)
const TINT_VENOM_BITE: Color = Color(0.6, 0.9, 0.4, 1.0)
const TINT_LEG_PIERCE: Color = Color(0.8, 0.4, 0.3, 1.0)
const TINT_POISON_SPIT: Color = Color(0.5, 0.8, 0.3, 1.0)

var hp: float
# Gated behind ArenaBox (see _ready()'s body_entered hookup below) — she
# doesn't spit or lay floor eggs until Elana actually walks into the arena,
# per the user's explicit instruction (2026-08-20). One-shot latch, not
# re-checked on exit, so the fight doesn't pause if she steps back out.
var _arena_triggered: bool = false
var _spit_timer: float = 0.0
var _floor_egg_timer: float = 0.0
var _is_down: bool = false
var _down_timer: float = 0.0
var _down_attack_cooldown: float = 0.0
var _is_using_attack: bool = false
var _anchors_remaining: int = 0
# 2026-08-20 additions — see _go_down()/_tick_down()/_go_up() below.
var _down_stun_timer: float = 0.0
# Set to down_post_attack_pause whenever an attack finishes (see
# _start_random_down_attack()) — ticked/consumed in
# _apply_horizontal_movement() below.
var _post_attack_pause_timer: float = 0.0
# Guards _go_up() against re-entry: _tick_down() keeps calling it every
# frame once _down_timer <= 0, and _is_down only flips false at the very
# END of _go_up()'s own 1s windup await — without this, dozens of parallel
# _go_up() coroutines would fire (one per frame during that windup), each
# redundantly applying the knockback and respawning a full set of anchors.
var _is_going_up: bool = false
# Captured once in _ready() — where she returns to when going back UP,
# since chasing (DOWN phase) moves her away from her placed position.
var _origin_position: Vector2 = Vector2.ZERO
# 2026-08-21 additions — see _apply_horizontal_movement()/_do_layer_jump()
# below. Resolved once in _ready() from platform_layer_paths.
var _platform_layers: Array[Node] = []
# Guards against re-entry the same way _is_using_attack/_is_going_up do —
# also disables gravity/move_and_slide() for the duration (see
# _apply_gravity()/_physics_process()) so the scripted arc has total,
# uncontested control over her position.
var _is_jumping: bool = false
# Guards the real-physics ascend/descend (2026-08-21 rework) the same way
# _is_jumping/_is_using_attack/_is_going_up guard everything else -- blocks
# chase/attacks/another jump from firing mid-transition (see
# _apply_horizontal_movement()/_tick_down()). Deliberately NOT checked by
# _apply_gravity()/_physics_process()'s move_and_slide() skip the way
# _is_jumping is -- during a layer transition we WANT real gravity and real
# collision running every frame, that's the entire point of this system.
var _is_layer_transitioning: bool = false
# True only during ascend's rising phase specifically, before the peak's been
# reached (2026-08-21) -- _tick_layer_transition() checks this to know
# whether it's still watching for the peak or already watching for a
# landing. False for the whole descend (no rise phase at all) and false
# again for ascend's own fall-after-peak.
var _is_ascending: bool = false
# Which layer _tick_layer_transition() should enable once ascend's peak is
# reached (2026-08-21) -- descend doesn't need this, it enables its target
# immediately.
var _layer_transition_target: int = -1
# How long the current phase (rising, or falling/waiting to land) has been
# going, ticked in _tick_layer_transition() -- compared against
# layer_jump_ascend_timeout/layer_jump_fall_timeout as a safety cutoff so a
# transition can't leave her stuck mid-air forever. Reset to 0 whenever the
# phase changes.
var _layer_transition_elapsed: float = 0.0
# Tracks whichever layer index _set_active_floor_layer() last set, -1 if none
# (2026-08-21 rework) -- her own "current layer" no longer needs to be
# geometrically guessed from her position via _get_layer_index_for_position()
# the way Elana's still is; the game already knows directly, since it's the
# thing that chose which floor bit is active. Sidesteps the whole class of
# boundary-edge bugs this session hit repeatedly (landing exactly on a shared
# zone edge reading as the wrong layer, "-1" at a zone's own boundary, etc.)
# for her side of the comparison at least.
var _current_floor_layer: int = -1
# Debounced jump-trigger state (2026-08-21, see layer_jump_detection_delay
# above for the full design). -1 means nothing's currently being watched.
var _pending_jump_target_layer: int = -1
var _pending_jump_timer: float = 0.0
# Manual replacement for CharacterBody2D's built-in is_on_floor() (2026-08-21
# -- her collision_mask is permanently 0 now, so the real physics engine
# never sets this on its own anymore). Set every frame in _apply_gravity()
# based purely on whether the hazard label at her feet matches
# _current_floor_layer's expected string -- read by _tick_layer_transition()
# in place of is_on_floor().
var _is_on_real_floor: bool = false
# Same source/pattern base_enemy.gd and elana.gd both use (project default,
# not a made-up value) — var, not const, since ProjectSettings.get_setting()
# is a method call and can't be a constant expression.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var _hp_bg: ColorRect = $HPBar/Background
@onready var _hp_fill: ColorRect = $HPBar/Fill
# Was a plain ColorRect until 2026-08-20 (user request: "make body color
# rect to polygon too") — now a Polygon2D nested inside her root
# CollisionPolygon2D, same pattern LegPierceZone already uses. Polygon2D is
# a CanvasItem too, so every existing "_color_rect.modulate = ..." tint
# call below works completely unchanged.
@onready var _color_rect: Polygon2D = $CollisionPolygon2D/Polygon2D
@onready var _body_shape: CollisionPolygon2D = $CollisionPolygon2D
@onready var _venom_bite_zone: Area2D = $VenomBiteZone
@onready var _leg_pierce_zone: Area2D = $LegPierceZone
@onready var _arena_box: Node = get_node_or_null(arena_box_path)
@onready var _arena_floor_zone: Node = get_node_or_null(arena_floor_zone_path)
@onready var _terrain: TileMap = get_node_or_null(terrain_path)

func _ready() -> void:
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	add_to_group("enemies")
	add_to_group("bosses")
	hp = max_hp
	_origin_position = global_position
	_spit_timer = spit_interval
	_floor_egg_timer = floor_egg_interval
	_spawn_anchors()
	if _arena_box != null:
		_arena_box.body_entered.connect(_on_arena_box_body_entered)
	else:
		push_warning("Broodspawner: arena_box_path not wired — she'll never start fighting (spit/floor eggs stay dormant).")
	for p in platform_layer_paths:
		var layer_node := get_node_or_null(p)
		if layer_node != null:
			_platform_layers.append(layer_node)
	if _platform_layers.is_empty():
		push_warning("Broodspawner: no platform_layer_paths wired — she'll only chase horizontally, never jump between layers.")
	if _terrain == null:
		push_warning("Broodspawner: terrain_path not wired — floor detection (_get_hazard_at_feet()) can't read any tile, she'll fall through everything.")
	# Default floor is webfloor1 from the moment she loads, while still UP
	# (2026-08-21, user request: "set it while on UP so we dont set anything
	# new first until it sets on a floor") -- previously _current_floor_layer
	# only ever became 0 the first time _go_down() ran _do_descend_jump(0);
	# setting it here instead means that's no longer a "first assignment,"
	# it's already correct and intentional before she ever goes DOWN at all.
	# Inert while UP either way (_apply_gravity() zeroes velocity.y unless
	# _is_down), this just makes it true from the start instead of by
	# coincidence of a leftover static collision_mask value in the .tscn.
	_set_active_floor_layer(0)
	# NOTE: the auto-sync that used to live here (copying CollisionPolygon2D's
	# polygon/position onto LegPierceZone's Polygon2D every _ready()) was
	# removed 2026-08-21 — same mistake as the body sync below, just caught
	# later: once the user hand-reshaped the visual into its own distinct
	# shape, this was silently overwriting that work back to match the
	# collision polygon on every single Play. Visual and collision are
	# independently authored now, same as the body already was.
	# NOTE: the equivalent sync for her own body was removed 2026-08-20 —
	# once real hand-drawn body art existed (the main Polygon2D plus
	# Polygon2D2/3/4 leg-segment pieces layered under CollisionPolygon2D),
	# copying CollisionPolygon2D's plain bounding polygon over _color_rect
	# every _ready() was overwriting that art with a rectangle. Body visual
	# and body collision are independently authored now — LegPierceZone's
	# sync above is unaffected, it never had extra decorative siblings.

# ArenaBox (independent sibling in the level scene, not a child of this
# scene — see arena_box_path above) is the trigger for when she actually
# starts fighting — spit eggs and floor-egg laying stay dormant (see
# _tick_up()'s early-return) until Elana walks into it, per the user's
# explicit instruction
# (2026-08-20). One-shot latch, not un-set on exit.
func _on_arena_box_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_arena_triggered = true

func _physics_process(delta: float) -> void:
	# Stuck-in-tile recovery removed (2026-08-21) -- it relied on a real
	# physics shape-overlap query, which can never find anything now that
	# collision_mask is permanently 0. Getting physically embedded in
	# something isn't possible under the fully-manual hazard-only floor
	# system this session ended on -- see the header comment.
	_update_facing()
	_apply_gravity(delta)
	# Ascend peak-detection / either direction's landing-detection (2026-08-21,
	# see _tick_layer_transition()'s own comment) -- runs before
	# _apply_horizontal_movement() below so a transition that finishes THIS
	# frame is already cleared in time for that frame's jump-trigger check,
	# same ordering _apply_gravity() needs relative to move_and_slide().
	_tick_layer_transition(delta)
	_apply_horizontal_movement(delta)
	_update_hp_bar()
	if _is_down:
		_tick_down(delta)
	else:
		_tick_up(delta)
	# Skipped only for the handful of remaining fully-scripted moves gated by
	# _is_jumping (the ascend's anticipation dip, attack lunges/windups) --
	# those write global_position directly every step. move_and_slide() still
	# runs every other frame purely to apply velocity to position (horizontal
	# chase, vertical gravity) -- it has nothing to actually collide with
	# anymore (collision_mask is permanently 0), all real stopping happens
	# manually in _apply_gravity() via the hazard-label check instead.
	if not _is_jumping:
		move_and_slide()

# Real gravity (2026-08-20, user request), but only while DOWN — UP means
# she's up off the web, safe and summoning, and isn't meant to need ground
# under her at all; DOWN means she's actually landed, which is when
# standing on real web ground matters. Floor detection is fully manual now
# (2026-08-21 -- see the header comment) -- is_on_floor() is never checked
# anywhere in this file anymore, since her collision_mask is permanently 0
# and Godot's real physics has nothing to collide with. Instead this reads
# the hazard label at her feet directly (_get_hazard_at_feet()) and only
# holds her in place if it exactly matches
# WEBFLOOR_HAZARD_NAMES[_current_floor_layer] -- nothing else, ever.
# _is_on_real_floor is the tracked replacement for is_on_floor(), read by
# _tick_layer_transition() below. This function doesn't check
# _is_layer_transitioning — gravity is meant to apply normally throughout an
# ascend/descend, that's the whole point of the real-physics rework.
func _apply_gravity(delta: float) -> void:
	if _is_jumping:
		velocity.y = 0.0
		return
	if _is_down:
		var expected_floor: String = ""
		var expected_bridge: String = ""
		if _current_floor_layer >= 0 and _current_floor_layer < WEBFLOOR_HAZARD_NAMES.size():
			expected_floor = WEBFLOOR_HAZARD_NAMES[_current_floor_layer]
			expected_bridge = WEBBRIDGE_HAZARD_NAMES[_current_floor_layer]
		var actual_hazard: String = _get_hazard_at_feet()
		var was_on_real_floor: bool = _is_on_real_floor
		_is_on_real_floor = expected_floor != "" and (actual_hazard == expected_floor or actual_hazard == expected_bridge)
		if _is_on_real_floor and not was_on_real_floor:
			print("[Broodspawner] FLOOR COLLISION: pos=%s hazard=\"%s\"" % [global_position, actual_hazard])
		if not _is_on_real_floor:
			velocity.y += gravity * delta
		elif velocity.y > 0.0:
			velocity.y = 0.0
	else:
		_is_on_real_floor = false
		velocity.y = 0.0

# Chases Elana horizontally while DOWN, once the landing stun's worn off
# and she's not mid-attack (2026-08-20, user request). Stops closing the
# gap once within down_chase_stop_distance — no need to walk until their
# bodies are centered on top of each other, just close enough to stay in
# range (2026-08-20, user request). Explicitly driven every frame — never
# left at whatever an external system last wrote — which doubles as the
# same anti-slide protection the old blanket velocity.x=0 fix provided (see
# the git history), just no longer blocking this intentional movement.
# Venom Bite's lunge moves her via direct global_position writes instead of
# velocity, so it's unaffected by this being zeroed during _is_using_attack.
# _post_attack_pause_timer (2026-08-20, user request) holds her still for a
# beat after an attack finishes, so chasing doesn't re-engage the instant
# _is_using_attack clears and read as the attack sliding straight into a walk.
func _apply_horizontal_movement(delta: float) -> void:
	if _post_attack_pause_timer > 0.0:
		_post_attack_pause_timer -= delta
	if _is_down and _down_stun_timer <= 0.0 and _post_attack_pause_timer <= 0.0 and not _is_using_attack and not _is_going_up and not _is_jumping and not _is_layer_transitioning:
		var elana = get_tree().get_first_node_in_group("player")
		if elana != null:
			# Layer jump takes priority over the normal horizontal chase
			# (2026-08-21, user design) — if Elana's on a different
			# platform_layer_paths zone than she is, jump there instead of
			# walking (real velocity ascend / real-gravity descend, see
			# _do_ascend_jump()/_do_descend_jump() — full rework 2026-08-21,
			# user design: "remake this shit... real velocity jump when
			# going up... enable the target layer collision"). Calling an
			# async func without awaiting it still runs its body synchronously
			# up to its first await, so whichever guard flag it sets first
			# (_is_layer_transitioning for descend, _is_jumping for ascend's
			# dip phase — either way the combined guard above covers it) is
			# already true before this function returns, same frame — can't
			# re-trigger itself next frame (same re-entry-guard pattern
			# _go_up() needed fixing for earlier).
			if not _platform_layers.is_empty():
				var elana_layer: int = _get_layer_index_for_position(elana.global_position)
				# Her own layer is read directly from _current_floor_layer
				# now (2026-08-21) instead of re-deriving it geometrically —
				# see that var's declaration comment.
				if elana_layer != -1 and _current_floor_layer != -1 and elana_layer != _current_floor_layer:
					# Debounced (2026-08-21, user design, see
					# layer_jump_detection_delay's declaration comment) --
					# doesn't jump the instant a mismatch is seen. Remembers
					# which layer Elana's on and waits; only jumps if she's
					# STILL on that same layer once the delay elapses. If she
					# moves to a different layer mid-wait, the remembered
					# layer/timer reset to the new one and the wait restarts.
					if elana_layer != _pending_jump_target_layer:
						_pending_jump_target_layer = elana_layer
						_pending_jump_timer = 0.0
					else:
						_pending_jump_timer += delta
						if _pending_jump_timer >= layer_jump_detection_delay:
							_pending_jump_target_layer = -1
							_pending_jump_timer = 0.0
							velocity = Vector2.ZERO
							# Higher index = physically higher up (PlatformLayer1
							# is index 0/lowest, PlatformLayer4 is index
							# 3/highest) -- ascend vs descend picked by
							# comparing indices, not Y positions directly,
							# matching every other layer-index comparison
							# already in this file.
							if elana_layer > _current_floor_layer:
								_do_ascend_jump(elana_layer)
							else:
								_do_descend_jump(elana_layer)
							return
				else:
					# No mismatch (or an invalid layer reading) -- nothing
					# left to debounce, clear any pending watch.
					_pending_jump_target_layer = -1
					_pending_jump_timer = 0.0
			if abs(elana.global_position.x - global_position.x) <= down_chase_stop_distance:
				velocity.x = 0.0
			else:
				velocity.x = down_chase_speed * direction
		else:
			velocity.x = 0.0
	else:
		velocity.x = 0.0

# Which platform_layer_paths zone (index into _platform_layers) contains
# the given world position, or -1 if none do (2026-08-21) — pure geometry
# against each zone's own RectangleShape2D bounds, not a physics/overlap
# query. Deliberately NOT using Area2D detection here: her own
# collision_layer is 0 (nothing detects her physically, see the header
# comment up top), so a zone's body_entered/get_overlapping_bodies() would
# never see her — this works identically for both Elana and her own
# position without needing to touch that.
func _get_layer_index_for_position(pos: Vector2) -> int:
	for i in _platform_layers.size():
		var zone: Node = _platform_layers[i]
		if zone == null:
			continue
		var shape_node: CollisionShape2D = zone.get_node_or_null("CollisionShape2D")
		if shape_node == null or not (shape_node.shape is RectangleShape2D):
			continue
		var rect_shape: RectangleShape2D = shape_node.shape
		var local_pos: Vector2 = zone.to_local(pos) - shape_node.position
		var half_size: Vector2 = rect_shape.size / 2.0
		if abs(local_pos.x) <= half_size.x and abs(local_pos.y) <= half_size.y:
			return i
	return -1

# Sets which single platform layer's floor she's currently allowed to land
# on (2026-08-21 full rework — see the header comment for the whole design).
# -1 means none at all, so she can't rest on anything -- used while rising
# mid-ascend (see _do_ascend_jump()). No collision_mask/physics_layer
# involvement anymore -- this just updates _current_floor_layer, which
# _apply_gravity() reads every frame to decide (purely from the hazard
# label at her feet) whether to stop her.
func _set_active_floor_layer(layer_index: int) -> void:
	_current_floor_layer = layer_index

# Ascending (2026-08-21, simplified per user request -- "why check per
# frame in a loop... just do the check simple" -- moved the peak/landing
# checks into _tick_layer_transition(), called from _physics_process() which
# already runs every frame regardless, instead of a dedicated await-loop
# living in here). Same anticipation dip as before (scripted, via
# _move_for(), _is_jumping true so it still bypasses gravity/collision for
# that brief moment), then a REAL upward velocity push with the floor target
# set to -1 (_set_active_floor_layer(-1)) so nothing can stop her rise --
# there's no wall collision anymore either (removed this same session), so
# she's fully airborne/unstoppable until the peak. This function itself
# just sets up the state and returns immediately -- _apply_gravity()/
# move_and_slide() (already running every frame) do the actual rising and
# falling; _tick_layer_transition() watches for the peak and the landing.
func _do_ascend_jump(target_layer: int) -> void:
	# Captured before anything below changes _current_floor_layer -- this is
	# how many layers she's actually crossing (2026-08-22, see
	# layer_jump_ascend_base_velocity's declaration comment).
	var layers_crossed: int = target_layer - _current_floor_layer
	_is_jumping = true
	velocity = Vector2.ZERO
	await _move_for(Vector2(0, 1), layer_jump_ascend_dip_distance, layer_jump_ascend_dip_duration)
	_is_jumping = false
	if not is_instance_valid(self):
		return
	_is_layer_transitioning = true
	_is_ascending = true
	_layer_transition_target = target_layer
	_layer_transition_elapsed = 0.0
	_set_active_floor_layer(-1)
	velocity.y = -(layer_jump_ascend_base_velocity + layer_jump_ascend_velocity_increment * (layers_crossed - 1))

# Descending (2026-08-21, same simplification as ascend above) — no scripted
# movement, no loop, no velocity push: just enables the target layer's floor
# bit and returns immediately. Gravity (already running every frame via
# _apply_gravity(), completely independent of this function) does the actual
# falling on its own; _tick_layer_transition() just watches for when she
# lands. Also used by _go_down() for the initial UP->DOWN drop, targeting
# layer 0.
func _do_descend_jump(target_layer: int) -> void:
	_is_layer_transitioning = true
	_is_ascending = false
	_layer_transition_target = target_layer
	_layer_transition_elapsed = 0.0
	_set_active_floor_layer(target_layer)

# Raw hazard label of the tile she's actually resting on, sampled just below
# her origin toward her feet ("" if nothing there, or terrain_path isn't
# wired). Used by _apply_gravity()'s floor check and
# _tick_layer_transition()'s floor-collision log.
func _get_hazard_at_feet() -> String:
	if _terrain == null:
		return ""
	var feet_pos: Vector2 = global_position + Vector2(0, 4.0)
	var cell: Vector2i = _terrain.local_to_map(_terrain.to_local(feet_pos))
	var tile_data: TileData = _terrain.get_cell_tile_data(0, cell)
	return tile_data.get_custom_data("hazard") if tile_data else ""

# Checked once per physics frame from _physics_process() -- reads
# _is_on_real_floor/velocity.y as set by _apply_gravity() this same frame
# (runs right after it, see _physics_process()). Two phases: while
# _is_ascending, watches for the peak (velocity.y crossing from negative to
# >= 0) and enables the target floor the instant it happens; otherwise
# (descend, or ascend after its peak), watches for an actual landing.
# _current_floor_layer always equals _layer_transition_target throughout
# this second phase (set the instant it starts, by _do_descend_jump() or by
# the peak branch just above), so _is_on_real_floor being true here already
# GUARANTEES the hazard matched -- _apply_gravity() computed it against the
# same _current_floor_layer this same frame. No separate mismatch check
# needed anymore (2026-08-21, simplified once floor detection became fully
# hazard-driven -- an earlier version of this had to actively push her
# through mismatched tiles, back when real physics collision could still
# stop her on the wrong thing). Either phase gives up after its own timeout
# so a transition can never leave her stuck mid-air with chase/attacks
# locked out forever.
func _tick_layer_transition(delta: float) -> void:
	if not _is_layer_transitioning:
		return
	_layer_transition_elapsed += delta
	if _is_ascending:
		if velocity.y >= 0.0 or _layer_transition_elapsed >= layer_jump_ascend_timeout:
			_set_active_floor_layer(_layer_transition_target)
			_is_ascending = false
			_layer_transition_elapsed = 0.0
	else:
		if _is_on_real_floor or _layer_transition_elapsed >= layer_jump_fall_timeout:
			_is_layer_transitioning = false

# Keeps direction facing Elana while DOWN and not mid-attack (locks for the
# duration of an attack once one starts) — 2026-08-20, user request:
# "spider becomes directional once it landed." Flips VenomBiteZone/
# LegPierceZone via scale.x rather than moving the zone's own position —
# they were authored assuming she's facing right, with their actual offset
# living on their CHILD CollisionShape2D/ColorRect nodes (the Area2D itself
# sits at local (0,0)), so mirroring the Area2D's own .position did nothing
# (bug found 2026-08-20: "make the collision flip to the other side").
# scale.x = -1 flips the whole local coordinate space under the zone —
# shape, collision detection, and visual all together — in one step.
func _update_facing() -> void:
	if not _is_down or _is_using_attack:
		return
	var elana = get_tree().get_first_node_in_group("player")
	if elana == null:
		return
	direction = 1 if elana.global_position.x >= global_position.x else -1
	# scale.x only mirrors what's INSIDE each zone (its children/collision
	# shape) — a zone's own .position relative to her body is unaffected by
	# its own scale, so it needs mirroring separately (2026-08-20 fix:
	# "flip everything properly" — LegPierceZone's root gained a nonzero
	# authored position (104, 0) and was staying pinned to one side while
	# only its insides flipped). abs()*direction is a no-op for either zone
	# if its own root position is still (0,0), so this is safe regardless
	# of whether an offset like that ever gets added.
	_venom_bite_zone.scale.x = direction
	_venom_bite_zone.position.x = abs(_venom_bite_zone.position.x) * direction
	_leg_pierce_zone.scale.x = direction
	_leg_pierce_zone.position.x = abs(_leg_pierce_zone.position.x) * direction
	# Her whole body silhouette flips too (2026-08-21, user request: "flip
	# all the visuals too") — _body_shape IS the root CollisionPolygon2D,
	# so scaling it mirrors everything nested inside in one step: the main
	# body Polygon2D, the decorative Polygon2D2/3/4 leg-segment pieces, AND
	# her own collision polygon shape (her hitbox mirrors to match facing
	# too, not just the art). Sits at local (0,0) on her own body, so no
	# position-mirroring needed here unlike the two attack zones above.
	_body_shape.scale.x = direction

func _update_hp_bar() -> void:
	_hp_fill.size.x = clamp(hp / float(max_hp), 0.0, 1.0) * _hp_bg.size.x

# ── UP state ──────────────────────────────────────────────────────────────

func _tick_up(delta: float) -> void:
	if not _arena_triggered:
		return
	if spit_enabled:
		_spit_timer -= delta
		if _spit_timer <= 0.0:
			_spit_timer = spit_interval
			_do_spit()
	if floor_eggs_enabled:
		_floor_egg_timer -= delta
		if _floor_egg_timer <= 0.0:
			_floor_egg_timer = floor_egg_interval
			_do_floor_eggs()

func _do_spit() -> void:
	# General direction toward Elana, not a precise lock onto her exact spot
	# (2026-08-20) — random offset within spit_aim_spread_deg each time.
	# Falls back to straight down if she can't be found at all.
	var elana = get_tree().get_first_node_in_group("player")
	var base_dir: Vector2 = Vector2.DOWN
	if elana != null:
		base_dir = (elana.global_position - global_position).normalized()
	var half_spread: float = deg_to_rad(spit_aim_spread_deg) / 2.0
	var spit_dir: Vector2 = base_dir.rotated(randf_range(-half_spread, half_spread))
	var egg = SPIT_EGG_SCENE.instantiate()
	egg.direction = spit_dir
	egg.hatch_time = spit_egg_hatch_time
	egg.global_position = global_position
	get_parent().call_deferred("add_child", egg)

func _do_floor_eggs() -> void:
	# ArenaFloorZone (independent sibling in the level scene, not a child of
	# this scene — see arena_floor_zone_path above) defines the actual
	# ground line eggs pop up along — resizing/repositioning it in the
	# editor automatically rescales the spread below. Falls back to the old
	# self-relative spacing if it's ever unwired/missing, same defensive
	# pattern terrain_hazards.gd uses for its optional overlay layers.
	var center: Vector2 = global_position
	var half_width: float = floor_egg_spacing * FLOOR_EGG_TYPES.size()
	if _arena_floor_zone != null:
		var shape_node: CollisionShape2D = _arena_floor_zone.get_node_or_null("CollisionShape2D")
		if shape_node != null and shape_node.shape is RectangleShape2D:
			center = _arena_floor_zone.global_position
			half_width = shape_node.shape.size.x / 2.0
	for side in [-1, 1]:
		for i in FLOOR_EGG_TYPES.size():
			# i=0 is outermost (charger), i=3 is innermost (normal enemy) —
			# outermost sits at the zone's edge, innermost closest to center.
			var t: float = float(FLOOR_EGG_TYPES.size() - i) / float(FLOOR_EGG_TYPES.size())
			var egg = FLOOR_EGG_SCENE.instantiate()
			egg.hatch_time = floor_egg_hatch_time
			egg.enemy_scene = FLOOR_EGG_TYPES[i]
			egg.global_position = center + Vector2(side * half_width * t, 0.0)
			get_parent().call_deferred("add_child", egg)

func _spawn_anchors() -> void:
	# WebAnchorPointNa/WebAnchorPointNb (real Marker2D pairs in
	# broodspawner.tscn, named 1 through anchor_count, user-adjustable in
	# editor) — each pair spawns one thin web_strand connecting them
	# (2026-08-20, "8 points paired into 4 strands" per the user's own
	# proposition, replacing the old single-point-per-anchor system).
	# Falls back to a short evenly-spaced horizontal segment per index if a
	# pair's markers are missing. global_position/rotation are set directly
	# before the deferred add_child — same established pattern every other
	# spawn function in this file already uses (_do_spit(), _do_floor_eggs(),
	# _do_poison_spit()).
	_anchors_remaining = anchor_count
	var fallback_start_x: float = -anchor_fallback_spacing * (anchor_count - 1) / 2.0
	for i in anchor_count:
		var marker_a := get_node_or_null("WebAnchorPoint%da" % (i + 1))
		var marker_b := get_node_or_null("WebAnchorPoint%db" % (i + 1))
		var point_a: Vector2
		var point_b: Vector2
		if marker_a != null and marker_b != null:
			point_a = marker_a.global_position
			point_b = marker_b.global_position
		else:
			var center_x: float = fallback_start_x + anchor_fallback_spacing * i
			point_a = global_position + Vector2(center_x - 40.0, anchor_fallback_y)
			point_b = global_position + Vector2(center_x + 40.0, anchor_fallback_y)
		var strand = WEB_STRAND_SCENE.instantiate()
		strand.boss_ref = self
		strand.set_length(point_a.distance_to(point_b))
		strand.global_position = (point_a + point_b) / 2.0
		strand.rotation = (point_b - point_a).angle()
		get_parent().call_deferred("add_child", strand)

# Called by web_strand.gd when one of hers is destroyed.
func on_anchor_destroyed() -> void:
	_anchors_remaining -= 1
	# TEMPORARY (2026-08-21, see anchors_required_to_fall above) — triggers
	# once that many have been cut, not necessarily all anchor_count of them.
	var destroyed: int = anchor_count - _anchors_remaining
	if destroyed >= anchors_required_to_fall and not _is_down:
		_go_down()

# ── DOWN state ────────────────────────────────────────────────────────────

func _go_down() -> void:
	_is_down = true
	_is_going_up = false
	_down_timer = down_duration
	_down_attack_cooldown = down_attack_gap
	_color_rect.modulate = TINT_DOWN
	# Initial drop (2026-08-21, converted to the real-gravity descend system
	# same session as the ascend/descend rework — see "Layer Jumping" export
	# group comment) — enables Platform Layer 1's floor bit; real gravity
	# carries her down to it from wherever she was UP, same as any other
	# descend. _do_descend_jump() itself no longer waits for the landing
	# (simplified 2026-08-21 — see _tick_layer_transition()), so this waits
	# here instead, specifically because the stun/knockback below needs to
	# fire at her actual landing spot, not the instant the descend starts.
	# _tick_down() already no-ops while _is_layer_transitioning is true, same
	# guard the between-layer descends rely on, so nothing else needs to wait
	# on this explicitly. Falls back to the old organic-gravity behavior
	# below if no layers are wired.
	if not _platform_layers.is_empty():
		_do_descend_jump(0)
		while _is_layer_transitioning:
			await get_tree().physics_frame
	# Stun + landing knockback (2026-08-20, user request) now fire once
	# she's actually landed, not from her UP-phase position mid-air — same
	# AOE pattern _go_up()'s own transition knockback already uses.
	_down_stun_timer = down_landing_stun
	for body in _nearby_bodies(down_landing_knockback_radius):
		if body.is_in_group("player") and body.has_method("apply_knockback"):
			var away: Vector2 = (body.global_position - global_position)
			var away_dir: Vector2 = away.normalized() if away.length() > 0.0 else Vector2.RIGHT
			body.apply_knockback(away_dir * down_landing_knockback + Vector2(0.0, -150.0), 0.4)

func _tick_down(delta: float) -> void:
	# Timer is frozen while an attack coroutine is mid-flight (windup/lunge/
	# await chain) so _go_up() can never fire concurrently with one — that
	# would race _is_using_attack/tint state between two coroutines.
	# _is_going_up guards _go_up() itself against re-entry — see its own
	# declaration comment above (2026-08-20 fix: this used to get called
	# once per frame for the whole 1s windup, spawning dozens of parallel
	# coroutines). _is_jumping/_is_layer_transitioning (2026-08-21) keep an
	# attack from starting mid-leap between layers, same reasoning.
	if _is_using_attack or _is_going_up or _is_jumping or _is_layer_transitioning:
		return
	if _down_stun_timer > 0.0:
		_down_stun_timer -= delta
	_down_timer -= delta
	if _down_timer <= 0.0:
		_is_going_up = true
		_go_up()
		return
	if _down_stun_timer > 0.0:
		return
	_down_attack_cooldown -= delta
	if _down_attack_cooldown <= 0.0:
		_down_attack_cooldown = down_attack_gap
		_start_random_down_attack()

func _start_random_down_attack() -> void:
	# Pool built from whichever attacks are currently enabled (2026-08-20,
	# user request — Leg Pierce/Poison Spit disabled for now, only Venom
	# Bite) instead of a fixed randi() % 3. If nothing's enabled, this is a
	# no-op — _down_attack_cooldown just resets and tries again next gap.
	var pool: Array[int] = []
	if venom_bite_enabled:
		pool.append(0)
	if leg_pierce_enabled:
		pool.append(1)
	if poison_spit_enabled:
		pool.append(2)
	if pool.is_empty():
		return
	_is_using_attack = true
	var choice: int = pool[randi() % pool.size()]
	match choice:
		0:
			await _do_venom_bite()
		1:
			await _do_leg_pierce()
		2:
			await _do_poison_spit()
	if is_instance_valid(self):
		_color_rect.modulate = TINT_DOWN
		_is_using_attack = false
		_post_attack_pause_timer = down_post_attack_pause

# Shared chunked-movement helper (2026-08-20) — moves this node dist units
# in dir over duration seconds, awaiting in small steps (same technique the
# venom bite lunge already used before this). Used for both attacks' shared
# "wind back opposite her facing" telegraph. Not used for the lunge itself,
# which still needs its own loop to layer a hit-check on top each step.
# No wall-blocking anymore (2026-08-21) -- webWall collision was removed
# entirely this same session, per direct request; nothing currently stops
# her horizontally at all.
func _move_for(dir: Vector2, dist: float, duration: float) -> void:
	if duration <= 0.0:
		global_position += dir * dist
		return
	# Fixed integer frame count + lerp-to-target instead of accumulating a
	# float "elapsed"/incrementally adding per-frame movement (2026-08-21 fix,
	# take 3 -- same reasoning as _do_layer_jump(), see its comment). Fixing
	# start/target up front and lerping by frame/total_frames means t reaches
	# EXACTLY 1.0 on the real last iteration with no possible float drift, and
	# a fixed target also avoids compounding rounding error from repeatedly
	# adding dir*speed*step onto a moving global_position.
	var start: Vector2 = global_position
	var target: Vector2 = start + dir * dist
	var total_frames: int = max(1, roundi(duration * Engine.physics_ticks_per_second))
	for frame in range(1, total_frames + 1):
		await get_tree().physics_frame
		if not is_instance_valid(self):
			return
		var t: float = float(frame) / float(total_frames)
		global_position = start.lerp(target, t)

func _do_venom_bite() -> void:
	_color_rect.modulate = TINT_VENOM_BITE
	# Winds back opposite her facing direction during the windup (2026-08-20,
	# user request), holds motionless briefly, then lunges forward in that
	# same facing direction (not re-aimed at Elana's live position anymore)
	# onto VenomBiteZone.
	await _move_for(Vector2(-direction, 0), venom_bite_windup_pullback, venom_bite_windup)
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(venom_bite_windup_hold).timeout
	if not is_instance_valid(self):
		return
	var lunge_dir: Vector2 = Vector2(direction, 0)
	var lunge_time: float = venom_bite_lunge_time
	var hit_done := false
	# VenomBiteZone (real Area2D+CollisionShape2D in broodspawner.tscn) is a
	# child of her own body, so it moves with her automatically as
	# global_position is updated each step of the lunge below; overlap is
	# just checked fresh every step instead of hand-computed distance math.
	# Fixed integer frame count + lerp-to-target (2026-08-21 fix, take 3 --
	# same reasoning as _do_layer_jump()/_move_for(), see their comments).
	var lunge_start: Vector2 = global_position
	var lunge_target: Vector2 = lunge_start + lunge_dir * venom_bite_lunge_speed * lunge_time
	var total_frames: int = max(1, roundi(lunge_time * Engine.physics_ticks_per_second))
	for frame in range(1, total_frames + 1):
		await get_tree().physics_frame
		if not is_instance_valid(self):
			return
		var t: float = float(frame) / float(total_frames)
		global_position = lunge_start.lerp(lunge_target, t)
		if not hit_done:
			for body in _venom_bite_zone.get_overlapping_bodies():
				if body.is_in_group("player"):
					hit_done = true
					body.take_damage(venom_bite_damage, false, self)
					if body.has_method("apply_player_poison"):
						body.apply_player_poison(venom_bite_poison_damage, venom_bite_poison_ticks)
					# Knockback added 2026-08-20, user request — she didn't
					# knock back on hit before, unlike Leg Pierce. No upward
					# pop here (unlike Leg Pierce's) — pure horizontal, per
					# user request.
					if body.has_method("apply_knockback"):
						body.apply_knockback(lunge_dir * venom_bite_knockback, 0.4)
					# Mini stun added 2026-08-20, user request.
					if body.has_method("apply_stun"):
						body.apply_stun(venom_bite_stun)
					break

func _do_leg_pierce() -> void:
	_color_rect.modulate = TINT_LEG_PIERCE
	# rest_position/rest_rotation already reflect whichever way she's
	# currently facing (see _update_facing()'s mirroring, locked for this
	# whole attack since it early-returns while _is_using_attack is true).
	var body_start: Vector2 = global_position
	var pullback_target: Vector2 = body_start + Vector2(-direction, 0) * leg_pierce_windup_pullback
	var forward_target: Vector2 = body_start + Vector2(direction, 0) * leg_pierce_slam_forward_shift
	var rest_rotation: float = _leg_pierce_zone.rotation
	# Multiplied by direction (2026-08-21 fix) — LegPierceZone's scale.x
	# mirrors when facing flips (see _update_facing()), which also mirrors
	# the visual handedness of any rotation applied on top of it. A flat
	# angle with no direction factor only ever looks right for ONE facing
	# side; multiplying by direction compensates for the mirror so the
	# swing reads the same both ways (flipping the raw export value instead
	# was the wrong fix — it just moved the same bug to the other side).
	var swing_rotation: float = rest_rotation + deg_to_rad(leg_pierce_rotate_angle_deg) * direction
	var rest_zone_position: Vector2 = _leg_pierce_zone.position
	var shifted_zone_position: Vector2 = rest_zone_position + Vector2(-direction, 0) * leg_pierce_windup_zone_shift
	# Windup: only the body pulls back now (2026-08-21, user request) —
	# LegPierceZone itself doesn't move or rotate at all during windup
	# anymore. Both the backward shift AND the raise happen together in the
	# first half of the slam phase below instead.
	# Fixed integer frame count (2026-08-21 fix, take 3 -- same reasoning as
	# _do_layer_jump()/_move_for(), see their comments).
	var windup_total_frames: int = max(1, roundi(leg_pierce_windup * Engine.physics_ticks_per_second))
	for windup_frame in range(1, windup_total_frames + 1):
		await get_tree().physics_frame
		if not is_instance_valid(self):
			return
		var t: float = float(windup_frame) / float(windup_total_frames)
		global_position = body_start.lerp(pullback_target, t)
	if not is_instance_valid(self):
		return
	# Slam: the raise (rotate + shift backward) AND the slam-down (rotate +
	# shift back to rest) both happen within leg_pierce_slam_time now
	# (2026-08-21, user request: "do raise and slam in the slam duration" /
	# "include the shift backwards ... in the slam") — first half raises
	# (rotates to swing_rotation AND shifts to shifted_zone_position),
	# second half slams down (rotates back to rest_rotation AND shifts back
	# to rest_zone_position). Body advance (to forward_target) still
	# animates smoothly across the whole duration. Damage only applies once
	# fully back down, right at the very end — not for the whole motion.
	# Fixed integer frame count (2026-08-21 fix, take 3 -- same reasoning as
	# _do_layer_jump()/_move_for(), see their comments).
	var slam_total_frames: int = max(1, roundi(leg_pierce_slam_time * Engine.physics_ticks_per_second))
	for slam_frame in range(1, slam_total_frames + 1):
		await get_tree().physics_frame
		if not is_instance_valid(self):
			return
		var t: float = float(slam_frame) / float(slam_total_frames)
		if t < 0.5:
			var raise_t: float = t / 0.5
			_leg_pierce_zone.rotation = lerp(rest_rotation, swing_rotation, raise_t)
			_leg_pierce_zone.position = rest_zone_position.lerp(shifted_zone_position, raise_t)
		else:
			var slam_t: float = (t - 0.5) / 0.5
			_leg_pierce_zone.rotation = lerp(swing_rotation, rest_rotation, slam_t)
			_leg_pierce_zone.position = shifted_zone_position.lerp(rest_zone_position, slam_t)
		global_position = pullback_target.lerp(forward_target, t)
	_leg_pierce_zone.rotation = rest_rotation
	_leg_pierce_zone.position = rest_zone_position
	# Camera shake on impact (2026-08-20, user request) — same
	# elana.add_camera_trauma() convention elemental_golem.gd's own Ground
	# Slam already uses.
	var elana = get_tree().get_first_node_in_group("player")
	if elana and elana.has_method("add_camera_trauma"):
		elana.add_camera_trauma(leg_pierce_slam_camera_shake)
	for body in _leg_pierce_zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			body.take_damage(leg_pierce_damage, false, self)
			var away: Vector2 = (body.global_position - global_position)
			# Upward pop is intentional here (2026-08-20, confirmed), unlike
			# Venom Bite's — kept as-is, made more prominent 2026-08-21.
			var away_dir: Vector2 = away.normalized() if away.length() > 0.0 else Vector2.RIGHT
			body.apply_knockback(away_dir * leg_pierce_knockback + Vector2(0.0, -leg_pierce_knockup), 0.4)

func _do_poison_spit() -> void:
	_color_rect.modulate = TINT_POISON_SPIT
	await get_tree().create_timer(poison_spit_windup).timeout
	if not is_instance_valid(self):
		return
	var elana = get_tree().get_first_node_in_group("player")
	var base_dir: Vector2 = Vector2.RIGHT
	if elana:
		base_dir = (elana.global_position - global_position).normalized()
	var half_spread: float = deg_to_rad(poison_spit_spread_deg) / 2.0
	for i in poison_spit_count:
		var t: float = (float(i) / float(poison_spit_count - 1)) if poison_spit_count > 1 else 0.5
		var angle_offset: float = lerp(-half_spread, half_spread, t)
		var proj = POISON_PROJECTILE_SCENE.instantiate()
		proj.aim_direction = base_dir.rotated(angle_offset)
		proj.global_position = global_position
		get_parent().call_deferred("add_child", proj)

func _go_up() -> void:
	_color_rect.modulate = TINT_BASE
	await get_tree().create_timer(down_to_up_windup).timeout
	if not is_instance_valid(self):
		return
	for body in _nearby_bodies(down_to_up_knockback_radius):
		if body.is_in_group("player") and body.has_method("apply_knockback"):
			var away: Vector2 = (body.global_position - global_position)
			var away_dir: Vector2 = away.normalized() if away.length() > 0.0 else Vector2.RIGHT
			body.apply_knockback(away_dir * down_to_up_knockback + Vector2(0.0, -150.0), 0.4)
	_is_down = false
	_is_going_up = false
	# Repositions back to wherever she started (2026-08-20, user request:
	# "reposition back to up state") — chasing during DOWN moves her away
	# from her placed spot, and web anchors/floor eggs/ArenaFloorZone are
	# all positioned relative to her, so she needs to actually be back home
	# before _spawn_anchors() runs again below.
	global_position = _origin_position
	_spawn_anchors()

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

# ── Damage / death ────────────────────────────────────────────────────────

# Generic hook elana.gd's plunge-attack path checks before falling back to
# its own raw enemy.hp -= damage logic (see elana.gd's _on_plunge_land()
# comment: "lets a target fully replace the normal plunge-damage path with
# its own custom reaction"). Without this, a plunge attack on her would
# mutate hp directly and, on a kill, run its OWN generic death handling
# instead of _die() — skipping reset_boss_camera() entirely and leaving the
# boss camera lock stuck on forever (2026-08-20 fix, found while
# investigating the slide-on-hit bug above). Routes through the exact same
# on_hit()/apply_boss_damage()/_die() pipeline every other hit uses.
func on_plunge_hit(_attacker: Node, hit_direction: int, damage: int) -> bool:
	on_hit(hit_direction, damage)
	return true

func apply_boss_damage(damage: int) -> void:
	if hp <= 0:
		return
	hp -= damage
	GameData.spawn_crit_aware_damage_number(damage, global_position)
	_flash_hit()
	if hp <= 0:
		_die()

func _flash_hit() -> void:
	var base: Color = TINT_DOWN if _is_down else TINT_BASE
	_color_rect.modulate = Color.WHITE
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		_color_rect.modulate = base

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	var final_damage = GameData.calc_damage(float(damage), float(defense))
	apply_boss_damage(final_damage)

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

func _die() -> void:
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	GameData.gain_xp(xp_reward)
	GameData.reset_boss_camera()
	queue_free()

# Same reasoning as Hollowfang's/Elemander's blocks_chain_pull() — a boss
# this size getting reeled in by Chain Claw wouldn't make sense, and
# chain_projectile.gd's pull writes to is_stunned/_pending_knockback,
# base_enemy.gd fields this script (extends CharacterBody2D directly)
# doesn't declare.
func blocks_chain_pull() -> bool:
	return true
