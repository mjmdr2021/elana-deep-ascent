extends CharacterBody2D

# Boss 2 — Elemander, "The Cycling Seal" (Room & Boss doc Section 6.6).
# Corrupted lizard, resistance-cycling identity: active_elements tracks
# whichever element(s) its currently-running attack(s) use (added when an
# attack starts, held through its punish window) — a matching element
# resists 80%, non-matching lands normal, and plain physical is reduced by
# body_defense same as any other enemy. Phase 1 only ever has one attack (and
# therefore one resisted element) active; Phase 2 can have two at once, which
# is why this is a set rather than a single String. extends CharacterBody2D
# directly, not enemy.gd/base_enemy.gd, same call Hollowfang made — a boss
# state machine doesn't fit the shared patrol/chase shape, and this one
# barely moves either.
#
# v1 scope: creature + HP + resist-cycling damage rules + Frost Beam (first
# of 3 attacks) + one shared trigger zone for all of them. Fire Dash,
# Electric Storm, the arena, and the death sequence are still open — same
# "creature first, everything else later" split noted in the bosses backlog
# for Hollowfang.

enum State { IDLE, FROST_BEAM_WINDUP, FROST_BEAM, FROST_BEAM_WINDOW, FROST_BEAM_RECOVERY }

@export var max_hp: int = 600
@export var body_defense: int = 45
@export var xp_reward: int = 300

const BODY_WIDTH: float = 200.0
const BODY_HEIGHT: float = 512.0
# Doc: "Elemental, matching its current element: 80% resist (~20% through)."
const ELEMENT_MATCH_MULT: float = 0.2

# Single trigger zone shared by all attacks — entering it rolls one via
# _start_random_attack(), same "walk in to force something" convenience
# Hollowfang's per-attack zones give, just not one dedicated box per attack
# this time.
var _elana_in_attack_trigger: bool = false

# Weighted, not a flat uniform pick — ratio between these decides the odds
# (e.g. all at 1.0 = even split; set one to 0.0 to fully exclude it, like
# testing one attack in isolation without the others interrupting).
@export var frost_beam_weight: float = 1.0
@export var fire_dash_weight: float = 0.0  # 2026-08-30, temp: isolated Frost Beam testing -- flip back to 1.0 when done
@export var electric_storm_weight: float = 0.0  # 2026-08-30, temp: isolated Frost Beam testing -- flip back to 1.0 when done

# Shared across all 4 attacks (Frost Beam, Fire Dash, Electric Storm, Wind
# Gust) — a brief hold right at the very end of each, after everything else
# (including any punish window) is already done, before _active_attacks
# actually drops to 0 and a new attack can be picked. Room for a
# return-to-idle animation to play once real art exists; for now it's just
# a pause. Frost Beam is state-machine-driven rather than a coroutine like
# the other 3, so it gets its own dedicated FROST_BEAM_RECOVERY sub-state
# (see _tick_frost_beam_recovery()) instead of a plain await.
@export var attack_recovery_pause: float = 0.5

# ── Punish Window Occur Chance (PWOC) ───────────────────────────────────────
# The resist-window phase (frozen jaw / overheat / paralysis) is no longer
# guaranteed every time an attack fires — each attack type has its own
# independent chance, starting at 0%, that only pays off the roll from
# BEFORE this occurrence (not the bump below, which is for next time):
#   - Whichever attack just fired: if its roll succeeded, its chance resets
#     to 0%; if it failed, its chance goes up by PUNISH_WINDOW_CHANCE_GAIN
#     (banked for the next time this specific attack comes up).
#   - Every OTHER attack's chance decays by PUNISH_WINDOW_CHANCE_DECAY
#     (floored at 0%) — it wasn't its turn, so its threat cools off a bit.
# Net effect: an attack that keeps recurring back-to-back compounds toward
# a near-guaranteed punish window; one that goes a while between turns
# decays back down.
const PUNISH_WINDOW_CHANCE_GAIN: float = 0.3
const PUNISH_WINDOW_CHANCE_DECAY: float = 0.05
var _punish_window_chance: Dictionary = {
	"frost_beam": 0.0,
	"fire_dash": 0.0,
	"electric_storm": 0.0,
}
# Which attack ids launched together as one "round" (Phase 2 pairs two;
# Phase 1 is always just the one) — set by _launch_attack_round(), read by
# _roll_punish_window() below so the "-5% to everyone else" step only fires
# once per round instead of once per attack, even though two paired Phase 2
# attacks finish their active phase at different natural times.
var _current_round_ids: Array = []
var _round_resolved_ids: Array = []

# Call once per attack, right when its active phase ends and it's deciding
# whether to enter the resist-window. Returns whether THIS occurrence gets
# the window (rolled against attack_id's chance as it stood before this
# call). Always updates attack_id's own chance for next time; the "-5% to
# everyone not in this round" step only runs once the LAST attack in the
# current round resolves — in Phase 1 a round is always just the one attack,
# so that happens immediately and this behaves exactly as before there.
func _roll_punish_window(attack_id: String) -> bool:
	var proc: bool = randf() < _punish_window_chance[attack_id]
	_punish_window_chance[attack_id] = 0.0 if proc else clamp(_punish_window_chance[attack_id] + PUNISH_WINDOW_CHANCE_GAIN, 0.0, 1.0)
	_round_resolved_ids.append(attack_id)
	if _round_resolved_ids.size() >= _current_round_ids.size():
		for id in _punish_window_chance.keys():
			if not id in _current_round_ids:
				_punish_window_chance[id] = max(0.0, _punish_window_chance[id] - PUNISH_WINDOW_CHANCE_DECAY)
	return proc

# ── Frost Beam (doc's "Frost Zap") ──────────────────────────────────────────
# FrostBeamEndPoint (small circle Area2D) is the tracking mechanism: hidden
# and not moving at all except during the windup (see below), where it
# continuously teleports onto Elana's live position — so the instant the
# beam actually appears, it's already sitting exactly where she was at that
# moment. Once active it switches to a capped-speed chase instead. Contact
# is "touching the endpoint" OR "touching the line connecting head to
# endpoint" (frost_beam_width is real hit-test thickness again, not just
# cosmetic) — either counts.
@export var frost_beam_windup_time: float = 0.5
@export var frost_beam_endpoint_speed: float = 60.0  # px/sec, active-phase chase speed only
@export var frost_beam_duration: float = 10.0            # active beam-chase time
@export var frost_beam_width: float = 14.0                # Line2D thickness AND hit-test width
@export var frost_beam_tick_damage: int = 6
@export var frost_beam_tick_interval: float = 0.3
@export var frost_beam_freeze_contact_time: float = 2.0  # continuous contact needed to freeze
@export var frost_beam_freeze_duration: float = 2.0
@export var frost_beam_freeze_immune_duration: float = 2.0  # after thawing, can't re-freeze for this long
@export var frost_beam_slow_factor: float = 0.5
@export var frost_beam_slow_duration: float = 3.0        # re-applied every touching frame, so it
															# only actually runs out 3s after the LAST touch
@export var frost_beam_window_duration: float = 10.0

# ── Fire Dash ────────────────────────────────────────────────────────────────
# Unlike Frost Beam, this whole attack is one linear sequence (windup ->
# 4 warning+dash passes -> window) rather than something that needs
# continuous per-frame tracking, so it's written as a single await-chained
# coroutine (_run_fire_dash()) instead of a per-frame ticker — same pattern
# dialog_marker.gd's cutscenes and Hollowfang's Drop Push sequence already
# use. _active_attacks (incremented/decremented at its start/end) is what
# keeps it mutually exclusive with new idle rolls; `state`/_physics_process's
# match is Frost Beam's own concern only, nothing here needs it.
@export var fire_dash_windup_time: float = 0.6
@export var fire_dash_pullback_distance: float = 80.0
@export var fire_dash_pullback_time: float = 0.3
@export var fire_dash_warning_time: float = 1.0   # total warning duration, blinks the whole time
@export var fire_dash_warning_flash_interval: float = 0.15  # on/off toggle rate during the warning
@export var fire_dash_sweep_time: float = 0.35
@export var fire_dash_gap_time: float = 0.5       # delay before the next warning starts
@export var fire_dash_damage: int = 15
# Pushed in the same direction the dash is currently sweeping (matching
# charger.gd's own dash-knockback convention), not away from Elemander —
# getting hit reads as being carried along by the impact, same idea.
@export var fire_dash_knockback_x: float = 150.0
@export var fire_dash_knockback_y: float = -70.0  # slight upward pop
# Phase 3 hits harder than even the original pre-nerf values above — read
# live at the point of a landed hit (not captured at the sweep's start like
# pass_count/warning_time) since a knockback is a one-shot instant event,
# not something that needs to stay consistent across an already-running
# attack.
@export var phase3_fire_dash_knockback_x: float = 380.0
@export var phase3_fire_dash_knockback_y: float = -170.0
@export var fire_dash_window_duration: float = 8.0
# How long the molten overlay cells stay painted before reverting.
@export var fire_patch_duration: float = 5.0
@export var fire_dash_pass_count: int = 4
const FIRE_DASH_TINT: Color = Color(1.6, 0.5, 0.3, 1.0)
# Must match terrain_hazards.gd's own layer indices — 0 is the real floor
# (read-only here, just to copy which tile is at a cell), 1 and 2 are the
# invisible overlays added via the editor (Inspector -> Layers -> Add
# Element).
const TERRAIN_TILE_LAYER: int = 0
const MOLTEN_OVERLAY_LAYER: int = 1
const SLIPPERY_OVERLAY_LAYER: int = 2
# Stand-in "frozen ground" tile for water cells Frost Beam freezes over —
# source 0, atlas (11, 5): same source the water tile itself is in, already
# has real collision (unlike water) and is already tagged "slippery" in the
# hazard layer. No dedicated ice art exists yet, this is a placeholder.
const FROZEN_WATER_SOURCE_ID: int = 0
const FROZEN_WATER_ATLAS_COORDS: Vector2i = Vector2i(11, 5)
const FROZEN_WATER_ALT_TILE: int = 0
@export var frost_beam_slippery_duration: float = 15.0
# Elana's origin isn't at her feet — same offset idea terrain_hazards.gd's
# own FEET_OFFSET uses, so the endpoint aims low instead of at her center.
const FROST_BEAM_ENDPOINT_FEET_OFFSET: float = 20.0

# ── Electric Storm ───────────────────────────────────────────────────────────
# 1s windup (yellow tint, held through the whole storm and its punish
# window). After windup, every water tile in the room electrifies at once
# (see _electrify_all_water()) for the storm's duration. Bolts themselves
# have no telegraph, no collision box — a hand-rolled distance check (same
# convention Hollowfang's own non-physical attacks use) against a straight
# vertical strike, same as Cave Disruptor's chaos framing but lightning
# instead of rocks. Each bolt lands at a random X within the shared
# AttackTriggerZone's own bounds (not a fixed radius around Elemander), so
# it only ever rains where the trigger zone actually is.
@export var electric_storm_windup_time: float = 1.0
# Registered via _set_attack_tint() (not written to _body_sprite.modulate
# directly) -- same as every attack's tint now, so Phase 2 can blend two of
# these together instead of one overwriting another. See
# _refresh_body_tint()'s own comment for how this actually reaches the
# sprite.
const ELECTRIC_STORM_TINT: Color = Color(1.0, 0.85, 0.1, 1.0)
@export var electric_storm_duration: float = 10.0
@export var electric_storm_bolt_count: int = 30
@export var electric_storm_bolt_width: float = 40.0   # hit-test width, X-distance only
@export var electric_storm_bolt_damage: int = 10
@export var electric_storm_bolt_flash_time: float = 0.15
@export var electric_storm_window_duration: float = 8.0
const ELECTRIC_STORM_BOLT_HEIGHT: float = 700.0
# Fourth overlay layer, same manual step as the other two (Inspector ->
# Layers -> Add Element) — must match terrain_hazards.gd's own constant.
# Only ever painted onto actual "surface"=="water" cells (see
# _electrify_all_water()); terrain_hazards.gd treats any tile present here
# as electrified, same "any tile present = active" rule the other overlays
# use.
const ELECTRIFIED_OVERLAY_LAYER: int = 3
# Same 3-frame sprite chain elana.gd's own _draw_elec_bolt() tiles along her
# elec bolt/chain lightning — reused here instead of duplicating that whole
# technique, just tiled vertically (fixed straight-down angle) instead of
# at an arbitrary angle between two points.
const ELECTRIC_BOLT_FRAMES = [
	"res://projectiles/electric_bolt1.png",
	"res://projectiles/electric_bolt2.png",
	"res://projectiles/electric_bolt3.png",
]
const ELECTRIC_BOLT_NATIVE_WIDTH: float = 24.0
const ELECTRIC_BOLT_NATIVE_HEIGHT: float = 16.0
const ELECTRIC_BOLT_TINT: Color = Color(1.6, 1.5, 0.3, 1.0)
# Built once in _ready() (_build_electric_bolt_frames()) and reused for
# every one of the 30 bolts a storm fires, rather than rebuilding the same
# SpriteFrames resources from scratch 30 times per storm.
var _electric_bolt_full_frames: SpriteFrames
var _electric_bolt_leftover_frames: SpriteFrames

# ── Wind Gust ─────────────────────────────────────────────────────────────────
# Not part of the shared weighted pool the other 3 attacks share — a
# dedicated WindGustTriggerZone fires this directly (see _tick_idle()),
# active in every phase, independent of the Phase 2/3 pairing logic. Pure
# spacing/utility attack: no damage, no element, no punish window, just
# shoves her back toward the other side of the arena.
@export var wind_gust_windup_time: float = 2.0
@export var phase3_wind_gust_windup_time: float = 1.5
# Elemander faces left, so "backward" is +X (same convention Fire Dash's own
# pullback uses) — combined with a small -Y so it reads as "flies up and
# back" over the full windup, one tween instead of two separate movements.
@export var wind_gust_pullback_offset: Vector2 = Vector2(100.0, -60.0)
@export var wind_gust_visual_sweep_time: float = 1.0
@export var wind_gust_visual_span: float = 700.0  # how far right of/left of Elemander the sweep starts/ends
# How far above/below its base height the gust visual weaves while it
# sweeps — up/down/up/down, 4 equal segments across wind_gust_visual_sweep_time.
@export var wind_gust_visual_wave_amplitude: float = 40.0
# Continuous drag speed (px/sec), leftward + a bit upward — reapplied every
# physics frame for wind_gust_drag_duration (see _drag_player_backward())
# rather than one impulse computed from a fixed distance, so it can't get
# cut short by a single wall-collision frame and reads as an actual
# sustained pull.
@export var wind_gust_drag_velocity: Vector2 = Vector2(-650.0, -110.0)
# Same up/down/up/down wave the visual rides, but on the actual pull — 2
# full sine cycles across wind_gust_drag_duration, added on top of
# wind_gust_drag_velocity.y (not replacing it), so the net drag still
# trends upward overall while wobbling through it.
@export var wind_gust_drag_wave_amplitude: float = 300.0
@export var wind_gust_drag_duration: float = 1.5
var _elana_in_wind_gust_trigger: bool = false

# ── Phase 3 boosts ───────────────────────────────────────────────────────────
# Phase 3 (<=15% hp) runs the exact same pairing/rotation as Phase 2 — see
# _start_random_attack() ("phase >= 2" already covers phase 3 too, no extra
# code needed there — just these three attacks individually boosted, plus a
# shorter punish window across the board (see _window_duration()). Replaces
# an earlier standalone "Unibeam" attack that was scrapped for hitting way
# too hard.
@export var phase3_frost_beam_width: float = 24.0            # up from the default 14
@export var phase3_frost_beam_endpoint_radius: float = 30.0  # up from the scene's baked 20
@export var phase3_fire_dash_pass_count: int = 6              # up from fire_dash_pass_count's 4
@export var phase3_fire_dash_warning_time: float = 0.5        # half of fire_dash_warning_time's default 1.0
@export var phase3_electric_storm_bolt_width: float = 70.0    # hit-test width, up from electric_storm_bolt_width's 40
# Multiplies the electric bolt's glow footprint (line-light thickness/energy
# + radial impact burst) only — NOT the sprite segments themselves, which
# stay at native pixel size regardless of phase. Scaling pixel art up
# introduces "mixels" (the pixel grid stops lining up); the glow is how
# "bigger bolt" gets communicated instead.
@export var phase3_electric_glow_scale: float = 1.8
const PHASE_3_PUNISH_WINDOW_REDUCTION: float = 1.0

var hp: float
var state: State = State.IDLE
# Set of elements currently "matching" for the 80% resist — a Dictionary
# used as a set (String -> true) rather than a single String, since Phase 2
# can have two attacks (and therefore two resisted elements) active at once.
var active_elements: Dictionary = {}
# Phase 1 (default): single attacks, cycling resist, same as always.
# Phase 2 (<=50% hp): attacks pair up — see _start_random_attack().
# Phase 3 (<=15% hp): same pairing as Phase 2, just with Frost Beam/Fire
# Dash/Electric Storm individually boosted (see the Phase 3 boosts block
# above) and a shorter punish window (_window_duration()).
var phase: int = 1
const PHASE_2_HP_RATIO: float = 0.5
const PHASE_3_HP_RATIO: float = 0.15
# How many attacks (Frost/Fire/Electric) are currently mid-sequence —
# _tick_idle() only rolls a new one once this is back to 0.
# Replaces the old "state == IDLE" gate now that Phase 2 can run two attacks
# concurrently; `state` itself is dedicated to Frost Beam's own
# windup/active/window sub-phase from here on, since Fire Dash/Electric
# Storm are self-contained coroutines that never needed per-frame state
# dispatch in the first place.
var _active_attacks: int = 0
# Public (not _-prefixed) — elana.gd's Bulwark reflect code
# (`attacker.on_hit(-attacker.direction, ...)`) assumes every member of the
# "enemies" group has this, since every base_enemy.gd-derived enemy does.
# Elemander doesn't extend that base (same call Hollowfang made), so it
# needs its own — same fix hollowfang.gd's own `direction` var is for.
var direction: int = 1

var _frost_beam_timer: float = 0.0
# Sentinel so the very first cell of a fresh Frost Beam always paints, even
# if it happens to match whatever cell the endpoint last sat on at the end
# of a PREVIOUS Frost Beam (reset in _start_frost_beam()).
var _frost_beam_last_slippery_cell: Vector2i = Vector2i(999999, 999999)
var _frost_beam_tick_timer: float = 0.0
var _frost_beam_contact_timer: float = 0.0
# Tracks the endpoint's own body_entered/exited, same shape
# _elana_in_attack_trigger already uses for the AttackTriggerZone.
var _elana_touching_endpoint: bool = false
# Local re-freeze cooldown, entirely separate from elana.gd's shared freeze
# system — covers both the 2s freeze itself and the 2s immunity after
# thawing as one continuous countdown from the moment freeze is applied
# (freeze_duration + freeze_immune_duration), so Frost Beam can't re-freeze
# her again until both have elapsed. Ticks down every physics frame
# regardless of state/contact, same as base_enemy.gd's own
# freeze_immune_timer convention.
var _frost_beam_freeze_lockout_timer: float = 0.0
var _frost_beam_windup_timer: float = 0.0
# Blue for the whole Frost Beam attack (windup through its window, not just
# the windup) — registered via _set_attack_tint(), not .modulate (which
# multiplies on top of the ColorRect's existing brown .color, reading as a
# muddy overlay rather than an actual color change) or a direct .color
# write (which would fight a concurrently-tinting Phase 2 partner instead
# of blending with it).
# 2026-08-30, user explicit: "reinvent this... make the beam and the head
# be together... so the angle of the beam will always be same with angle
# of head" -- dropped the earlier +15deg "looking up while aiming" offset
# entirely (was only ever applied to the head, never the beam's own real
# line, so it created a visible mismatch between where the head appeared
# to look and where the beam was actually going). HeadPivot's own position
# was also collapsed to sit exactly on Head's point (elemander.tscn) so
# the rotation pivot and the beam's real start point are now the same
# physical spot, not just the same angle.
#
# drawn-forward angle = rotation + PI (the art's neutral pose faces LEFT,
# i.e. 180 deg, not the engine's own 0-deg/right default) -- see
# _tick_frost_beam_windup()'s own comment for the full derivation.
const FROST_BEAM_TINT: Color = Color(0.25, 0.55, 1.0, 1.0)
# Base width the glow texture is built at once, in _ready() — stretched via
# scale.x per frame to match the beam's actual current length instead of
# rebuilding the texture every frame (see _update_frost_beam_visual()).
const FROST_BEAM_GLOW_BASE_WIDTH: float = 100.0
const FROST_BEAM_GLOW_ENERGY: float = 2.5  # faint, well under the electric bolt glow's 6-10

@onready var _head: Node2D = $Head
# 2026-08-30, user explicit: "make a new one. i dont want them to be the
# same shit" -- Head itself stays the fixed Frost Beam origin/aim anchor
# (_head.global_position, untouched, never rotates); HeadPivot is a
# genuinely separate child node that owns the actual visual/collision/
# hurtbox and will be what eventually rotates for the head-tilt feature
# (still on hold) -- decoupled so tilting the head doesn't drag the beam's
# own origin point along with it.
@onready var _head_pivot: Node2D = $Head/HeadPivot
# Anchor 2 in the "crank" model (2026-08-30/31, user explicit) -- a real,
# draggable marker positioned wherever the mouth/snout tip actually sits
# in the art, LOCAL to HeadPivot. Its own .position.angle() (the direction
# from the pivot to the mouth, before any rotation) replaces what used to
# be a hardcoded "-PI, assume dead-left" guess -- generalizes correctly to
# wherever the user actually places it, not just a fixed 180deg assumption.
@onready var _mouth_anchor: Node2D = $Head/HeadPivot/MouthAnchor
@onready var _hp_bg: ColorRect = $HPBar/Background
@onready var _hp_fill: ColorRect = $HPBar/Fill
@onready var _frost_beam: Line2D = $FrostBeam
@onready var _frost_beam_glow: PointLight2D = $FrostBeamGlow
@onready var _body_sprite: Sprite2D = $BodyVisual
@onready var _frost_beam_endpoint: Area2D = $FrostBeamEndPoint
@onready var _dash_areas: Array = [$DashArea1, $DashArea2, $DashArea3]
@onready var _dash_collision: Area2D = $ElemanderDashCollision
@onready var _original_position: Vector2 = position
@onready var _debug_raycast_line: Line2D = $DebugRaycastLine

var _fire_dash_hit_this_pass: bool = false

func _ready() -> void:
	# Same is_removed()/mark_removed() persistence pair every other boss
	# uses (Hollowfang, Ant Queen, Elemental Golem, Broodspawner) — missing
	# here until now, so killing him and reloading/re-entering the scene
	# silently respawned him fully alive every time.
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	hp = max_hp
	add_to_group("enemies")
	add_to_group("bosses")
	# 2026-08-30, real hittable head region -- see elemander_head.gd's own
	# header comment for why this forwarding is needed at all. set()
	# instead of a direct property write -- _head_pivot is typed Node2D
	# (its custom script has no class_name), so boss_ref isn't a known
	# member of that static type.
	_head_pivot.set("boss_ref", self)
	_frost_beam.visible = false
	_frost_beam.width = frost_beam_width
	_frost_beam.default_color = Color(0.4, 0.85, 1.0, 0.85)
	_frost_beam_glow.visible = false
	_build_frost_beam_glow_texture()
	_frost_beam_endpoint.global_position = _head.global_position
	_frost_beam_endpoint.visible = false
	$AttackTriggerZone.body_entered.connect(_on_attack_trigger_body_entered)
	$AttackTriggerZone.body_exited.connect(_on_attack_trigger_body_exited)
	$WindGustTriggerZone.body_entered.connect(_on_wind_gust_trigger_body_entered)
	$WindGustTriggerZone.body_exited.connect(_on_wind_gust_trigger_body_exited)
	_frost_beam_endpoint.body_entered.connect(_on_frost_beam_endpoint_body_entered)
	_frost_beam_endpoint.body_exited.connect(_on_frost_beam_endpoint_body_exited)
	_dash_collision.visible = false
	for area in _dash_areas:
		_sync_dash_area_warn_flash(area)
	_build_electric_bolt_frames()

# WarnFlash IS the collision box's color — Godot just has no way to paint a
# CollisionShape2D itself, so this ColorRect is the only way to show one.
# Direct position/size copy of the real shape (no anchors, no offset math)
# so it's a straight rect-for-rect match: resize or move CollisionShape2D
# in the editor and this exactly follows, nothing else to touch.
func _sync_dash_area_warn_flash(area: Area2D) -> void:
	var shape_node: CollisionShape2D = area.get_node("CollisionShape2D")
	var warn_flash: ColorRect = area.get_node("WarnFlash")
	var shape: RectangleShape2D = shape_node.shape
	warn_flash.size = shape.size
	warn_flash.position = shape_node.position - shape.size / 2.0

# Polling instead of body_entered — that signal only fires on a fresh
# boundary crossing, and since the box now starts visible/wherever it last
# sat rather than reliably hidden off to the side, a continued overlap
# (already-touching before the sweep even starts) would never refire it.
# Same fix breakable_floor.gd needed for the exact same reason.
func _check_dash_collision_overlap(right_to_left: bool = true) -> void:
	if _fire_dash_hit_this_pass:
		return
	for body in _dash_collision.get_overlapping_bodies():
		if body.is_in_group("player"):
			_fire_dash_hit_this_pass = true
			if body.has_method("take_damage"):
				body.take_damage(fire_dash_damage, true, self, "fire")
			if body.has_method("apply_knockback"):
				var dir_x: float = -1.0 if right_to_left else 1.0
				var knockback_x: float = phase3_fire_dash_knockback_x if phase >= 3 else fire_dash_knockback_x
				var knockback_y: float = phase3_fire_dash_knockback_y if phase >= 3 else fire_dash_knockback_y
				body.apply_knockback(Vector2(knockback_x * dir_x, knockback_y))
			return

func _on_frost_beam_endpoint_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_touching_endpoint = true

func _on_frost_beam_endpoint_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_touching_endpoint = false

func _on_attack_trigger_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_attack_trigger = true

func _on_attack_trigger_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_attack_trigger = false

func _on_wind_gust_trigger_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_wind_gust_trigger = true

func _on_wind_gust_trigger_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_wind_gust_trigger = false

# ── Phase 2 combo tint blending ─────────────────────────────────────────────
# Each attack that wants to show a tint registers its own color here instead
# of writing straight to _body_sprite.modulate — in Phase 1 there's only
# ever one entry, so this reduces to "show that one color" exactly like
# before. In Phase 2, two attacks can be tinting at once (e.g. Frost Beam's
# blue + Electric Storm's yellow); _refresh_body_tint() averages whatever's
# currently registered instead of the two attacks' own start/end code
# fighting over the same property.
#
# 2026-08-30, user added real sprite art (elemander-sprite-1.png) --
# BodyVisual went from a flat-fill ColorRect (whose .color could be
# directly REPLACED) to a real Sprite2D, which only has .modulate (a
# MULTIPLY tint, same as every other sprite-based enemy in this codebase
# already uses for hit-flash/tint effects). The old header comment here
# used to warn against .modulate specifically because multiplying onto a
# flat ColorRect .color read muddy -- that concern doesn't apply to real
# shaded artwork, so this migrates to the standard modulate approach.
var _active_tints: Dictionary = {}

func _set_attack_tint(attack_id: String, tint: Color) -> void:
	_active_tints[attack_id] = tint
	_refresh_body_tint()

func _clear_attack_tint(attack_id: String) -> void:
	_active_tints.erase(attack_id)
	_refresh_body_tint()

func _refresh_body_tint() -> void:
	if _active_tints.is_empty():
		_body_sprite.modulate = Color.WHITE
		return
	var blended: Color = Color(0, 0, 0, 0)
	for tint in _active_tints.values():
		blended += tint
	blended /= float(_active_tints.size())
	_body_sprite.modulate = blended

func _physics_process(delta: float) -> void:
	if _frost_beam_freeze_lockout_timer > 0.0:
		_frost_beam_freeze_lockout_timer -= delta
	match state:
		State.FROST_BEAM_WINDUP:
			_tick_frost_beam_windup(delta)
		State.FROST_BEAM:
			_tick_frost_beam(delta)
		State.FROST_BEAM_WINDOW:
			_tick_frost_beam_window(delta)
		State.FROST_BEAM_RECOVERY:
			_tick_frost_beam_recovery(delta)
	# Ticked unconditionally, not part of the match above — _active_attacks
	# is the real "is anything in progress" gate now, decoupled from Frost
	# Beam's own state, so a new attack can be rolled even while Frost Beam
	# isn't the (or isn't the only) thing currently running.
	if _active_attacks == 0:
		_tick_idle()
	# No move_and_slide() call at all — not even at zero velocity. Godot's
	# CharacterBody2D auto-depenetrates from any overlapping solid geometry
	# every time move_and_slide() runs, regardless of requested velocity, so
	# calling it unconditionally (Hollowfang's own convention) can still
	# drift the body if its collision shape overlaps terrain. Elemander has
	# no movement/knockback mechanic to support, so skipping the call
	# entirely guarantees it can never move, full stop, no matter what its
	# shape overlaps.
	_update_hp_bar()

func _tick_idle() -> void:
	if GameData.in_cutscene:
		return
	# Checked before the shared pool — Wind Gust isn't a weighted-pool
	# member, it's a dedicated "you got too close" trigger, active in every
	# phase. If both zones happen to overlap, Wind Gust wins.
	if _elana_in_wind_gust_trigger:
		_run_wind_gust()
		return
	if _elana_in_attack_trigger:
		_start_random_attack()

# A weight of 0 on everything (all attacks disabled) just does nothing,
# same as an empty pool would. Phase 2 (phase >= 2) pairs whichever attack
# gets picked with a second one per the fixed rule in _phase2_partner():
# Frost/Fire always pull in Electric Storm, Electric Storm pulls in a
# random Frost-or-Fire.
func _start_random_attack() -> void:
	var pool: Array = [
		{"id": "frost_beam", "weight": frost_beam_weight},
		{"id": "fire_dash", "weight": fire_dash_weight},
		{"id": "electric_storm", "weight": electric_storm_weight},
	]
	var total_weight: float = 0.0
	for entry in pool:
		total_weight += entry["weight"]
	if total_weight <= 0.0:
		return
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	var picked_id: String = ""
	for entry in pool:
		cumulative += entry["weight"]
		if roll < cumulative:
			picked_id = entry["id"]
			break
	if picked_id == "":
		return
	var fired_ids: Array = [picked_id]
	if phase >= 2:
		fired_ids.append(_phase2_partner(picked_id))
	_launch_attack_round(fired_ids)

# Frost Beam or Fire Dash picked -> always pairs with Electric Storm.
# Electric Storm picked -> pairs with a random Frost Beam or Fire Dash.
func _phase2_partner(primary_id: String) -> String:
	match primary_id:
		"frost_beam", "fire_dash":
			return "electric_storm"
		"electric_storm":
			return "frost_beam" if randf() < 0.5 else "fire_dash"
	return ""

# Records which ids are launching together this round (read by
# _roll_punish_window()'s batched decay above) and starts each one. In
# Phase 1, fired_ids is always a single id — this reduces to exactly what
# _start_random_attack() used to do inline.
func _launch_attack_round(fired_ids: Array) -> void:
	_current_round_ids = fired_ids.duplicate()
	_round_resolved_ids = []
	for id in fired_ids:
		match id:
			"frost_beam":
				_start_frost_beam_windup()
			"fire_dash":
				_run_fire_dash()
			"electric_storm":
				_run_electric_storm()

func _start_frost_beam_windup() -> void:
	_active_attacks += 1
	state = State.FROST_BEAM_WINDUP
	_frost_beam_windup_timer = frost_beam_windup_time
	# Blue for the whole attack now, not just the windup — stays registered
	# until Frost Beam actually ends (see the two places that clear it:
	# _tick_frost_beam()'s no-window branch, and _tick_frost_beam_window()'s
	# natural expiry). Registered rather than set directly so it can blend
	# with a concurrently-tinting Phase 2 partner instead of overwriting it.
	_set_attack_tint("frost_beam", FROST_BEAM_TINT)
	# Phase 3 gets a bigger beam/endpoint — Phase 1/2 leaves the scene's
	# baked default sizes alone entirely (no resize call at all), so this
	# only ever changes anything from here on once phase == 3.
	if phase >= 3:
		_resize_frost_beam(phase3_frost_beam_width, phase3_frost_beam_endpoint_radius)

# Endpoint teleports (not the capped chase speed) onto her live position
# every frame of the windup, staying hidden the whole time — so the moment
# the beam actually appears (_start_frost_beam()), it's already sitting
# exactly where she was at that instant, no catch-up needed.
func _tick_frost_beam_windup(delta: float) -> void:
	_frost_beam_windup_timer -= delta
	var target = get_tree().get_first_node_in_group("player")
	if target:
		_frost_beam_endpoint.global_position = target.global_position + Vector2(0, FROST_BEAM_ENDPOINT_FEET_OFFSET)
		# 2026-08-30, head tilt starts telegraphing during the windup too,
		# same reasoning as _update_frost_beam_visual()'s own tilt update --
		# the endpoint already tracks her live position here, invisibly.
		var offset: Vector2 = _frost_beam_endpoint.global_position - _head.global_position
		if offset != Vector2.ZERO:
			# 2026-08-31, "crank" model (user explicit) -- Anchor 1 (the
			# pivot, _head_pivot's own origin) is the same point the beam
			# starts from; Anchor 2 (_mouth_anchor) sits at a fixed local
			# offset from the pivot, on the mouth tip. Rotating the head so
			# that Anchor 1->Anchor 2's direction matches the beam's real
			# direction is exactly what sweeps the mouth onto the beam's
			# line, at any aim angle -- generalizes the earlier hardcoded
			# "-PI, assume dead-left" guess into the real local offset.
			_head_pivot.rotation = offset.angle() - _mouth_anchor.position.angle()
	if _frost_beam_windup_timer <= 0.0:
		_start_frost_beam()

func _start_frost_beam() -> void:
	state = State.FROST_BEAM
	active_elements["frost"] = true
	_frost_beam_timer = frost_beam_duration
	_frost_beam_tick_timer = 0.0
	_frost_beam_contact_timer = 0.0
	_frost_beam_last_slippery_cell = Vector2i(999999, 999999)
	_frost_beam.visible = true
	_frost_beam_endpoint.visible = true

func _tick_frost_beam(delta: float) -> void:
	_tick_frost_beam_endpoint(delta)
	_mark_slippery_at_endpoint()
	_update_frost_beam_visual()
	if _is_elana_touching_beam():
		_apply_frost_beam_contact(delta)
	else:
		_frost_beam_contact_timer = 0.0
	_frost_beam_timer -= delta
	if _frost_beam_timer <= 0.0:
		if _roll_punish_window("frost_beam"):
			_start_frost_beam_window()
		else:
			_frost_beam.visible = false
			_frost_beam_glow.visible = false
			_frost_beam_endpoint.visible = false
			_clear_attack_tint("frost_beam")
			active_elements.erase("frost")
			_start_frost_beam_recovery()

# Paints a trail behind the endpoint as it moves — only when it enters a
# NEW cell (not every frame it just sits still), same "no floor tile = skip"
# and "already painted = leave its existing timer alone" rules the molten
# overlay uses. Each painted cell clears itself independently
# frost_beam_slippery_duration after IT was painted, not all together.
# Unlike molten, this does NOT skip water tiles — Frost Beam freezes over
# water instead, and WaterCheck.is_water() already reads this same overlay
# layer to treat a frozen cell as solid/icy rather than open water for as
# long as the slippery tag lasts, then it thaws back to water on its own
# once that timer clears (same timer, no separate tracking needed).
func _mark_slippery_at_endpoint() -> void:
	var terrain: TileMap = get_tree().current_scene.get_node_or_null("Terrain")
	if terrain == null:
		return
	var cell: Vector2i = terrain.local_to_map(terrain.to_local(_frost_beam_endpoint.global_position))
	if cell == _frost_beam_last_slippery_cell:
		return
	_frost_beam_last_slippery_cell = cell
	var src_id := terrain.get_cell_source_id(TERRAIN_TILE_LAYER, cell)
	if src_id == -1:
		return
	if terrain.get_cell_source_id(SLIPPERY_OVERLAY_LAYER, cell) != -1:
		return  # already slippery here (this trail or an earlier one) — leave its timer running
	var atlas_coords := terrain.get_cell_atlas_coords(TERRAIN_TILE_LAYER, cell)
	var alt_tile := terrain.get_cell_alternative_tile(TERRAIN_TILE_LAYER, cell)
	terrain.set_cell(SLIPPERY_OVERLAY_LAYER, cell, src_id, atlas_coords, alt_tile)

	var was_water := _is_water_tile(terrain, cell)
	if was_water:
		# Swap the real floor to solid ground so she can stand on it instead
		# of swimming through it — WaterCheck.is_water() already treats this
		# cell as non-water for the same duration via the overlay layer
		# above; this is what actually gives it collision. Restored to the
		# real water tile (orig_src/atlas_coords/alt_tile, captured above
		# before this swap) once the freeze clears.
		terrain.set_cell(TERRAIN_TILE_LAYER, cell, FROZEN_WATER_SOURCE_ID, FROZEN_WATER_ATLAS_COORDS, FROZEN_WATER_ALT_TILE)

	_clear_slippery_cell_after_delay(terrain, cell, was_water, src_id, atlas_coords, alt_tile)

func _clear_slippery_cell_after_delay(terrain: TileMap, cell: Vector2i, was_water: bool,
		orig_src: int, orig_atlas: Vector2i, orig_alt: int) -> void:
	await get_tree().create_timer(frost_beam_slippery_duration).timeout
	if not is_instance_valid(terrain):
		return
	terrain.set_cell(SLIPPERY_OVERLAY_LAYER, cell, -1)
	if was_water:
		terrain.set_cell(TERRAIN_TILE_LAYER, cell, orig_src, orig_atlas, orig_alt)

# Only moves (capped chase speed) while the beam is actually active — during
# windup it teleports instead (see _tick_frost_beam_windup()), and it holds
# perfectly still whenever Frost Beam isn't running at all (idle/window).
func _tick_frost_beam_endpoint(delta: float) -> void:
	var target = get_tree().get_first_node_in_group("player")
	if target:
		var feet_pos = target.global_position + Vector2(0, FROST_BEAM_ENDPOINT_FEET_OFFSET)
		_frost_beam_endpoint.global_position = _frost_beam_endpoint.global_position.move_toward(
			feet_pos, frost_beam_endpoint_speed * delta)

# Contact = touching the endpoint circle itself, OR touching the line
# connecting head to endpoint (point-to-segment distance, same hand-rolled
# check Hollowfang's own distance-based attacks use) — either one counts,
# not just the endpoint. Reads _frost_beam.width directly (rather than the
# frost_beam_width export) so Phase 3's bigger beam — see _resize_frost_beam()
# — automatically hit-tests at its actual current visual width, whatever
# that currently is.
func _is_elana_touching_beam() -> bool:
	if _elana_touching_endpoint:
		return true
	var target = get_tree().get_first_node_in_group("player")
	if not target:
		return false
	var closest = Geometry2D.get_closest_point_to_segment(
		target.global_position, _head.global_position, _frost_beam_endpoint.global_position)
	return target.global_position.distance_to(closest) <= _frost_beam.width * 0.5

func _apply_frost_beam_contact(delta: float) -> void:
	var target = get_tree().get_first_node_in_group("player")
	if not target:
		return
	_frost_beam_tick_timer -= delta
	if _frost_beam_tick_timer <= 0.0:
		_frost_beam_tick_timer = frost_beam_tick_interval
		if target.has_method("take_damage"):
			target.take_damage(frost_beam_tick_damage, true, self, "frost")
	# Slow — reapplied every frame she's touching, so apply_slow()'s own
	# max(timer, duration) merge keeps refreshing it back to a full 3s
	# rather than counting down while contact continues; it only actually
	# starts expiring once she stops touching (its last applied value).
	if target.has_method("apply_slow"):
		target.apply_slow(frost_beam_slow_factor, frost_beam_slow_duration, "frost")
	# Freeze — needs frost_beam_freeze_contact_time of unbroken contact, and
	# won't re-trigger while the lockout (freeze + post-thaw immunity) from
	# a previous freeze is still counting down.
	_frost_beam_contact_timer += delta
	if _frost_beam_contact_timer >= frost_beam_freeze_contact_time and _frost_beam_freeze_lockout_timer <= 0.0:
		if target.has_method("apply_freeze"):
			target.apply_freeze(frost_beam_freeze_duration)
		_frost_beam_freeze_lockout_timer = frost_beam_freeze_duration + frost_beam_freeze_immune_duration
		_frost_beam_contact_timer = 0.0

func _update_frost_beam_visual() -> void:
	_frost_beam.global_position = _head.global_position
	_frost_beam.rotation = 0.0
	var offset = _frost_beam_endpoint.global_position - _head.global_position
	_frost_beam.points = PackedVector2Array([Vector2.ZERO, offset])
	# 2026-08-31, "crank" model (user explicit) -- HeadPivot (a genuinely
	# separate node from Head, see elemander_head.gd's own comment) sits at
	# the exact same point the beam starts from (Anchor 1), and rotates so
	# MouthAnchor (Anchor 2, a fixed local offset from the pivot) swings
	# onto the beam's real line -- see _tick_frost_beam_windup()'s own
	# comment for the full explanation.
	if offset != Vector2.ZERO:
		_head_pivot.rotation = offset.angle() - _mouth_anchor.position.angle()

	# Faint continuous glow along the beam — same linear-gradient-light
	# technique as Electric Storm's bolt glow, but built once (FROST_BEAM_
	# GLOW_BASE_WIDTH) and stretched via scale.x every frame instead of
	# rebuilding the texture each time, since the beam's length changes
	# continuously as the endpoint moves (the bolts are one-shot flashes at
	# a fixed length, so rebuilding once each was fine there).
	var length = offset.length()
	_frost_beam_glow.visible = true
	_frost_beam_glow.global_position = _head.global_position + offset * 0.5
	_frost_beam_glow.rotation = offset.angle()
	_frost_beam_glow.scale.x = max(0.01, length / FROST_BEAM_GLOW_BASE_WIDTH)

func _start_frost_beam_window() -> void:
	state = State.FROST_BEAM_WINDOW
	_frost_beam_timer = _window_duration(frost_beam_window_duration)
	_frost_beam.visible = false
	_frost_beam_glow.visible = false
	_frost_beam_endpoint.visible = false
	_head_pivot.rotation = 0.0  # head tilt resets to the untouched idle pose once the beam itself is done aiming

# Window: "jaw frozen shut... frost resisted (80%), fire/elec normal" — no
# separate vulnerable/bonus-damage multiplier, "frost" staying in
# active_elements through this whole window is the entire effect
# (on_elemental_hit() below already reads it). Just a hold before returning
# to idle.
func _tick_frost_beam_window(delta: float) -> void:
	_frost_beam_timer -= delta
	if _frost_beam_timer <= 0.0:
		_clear_attack_tint("frost_beam")
		active_elements.erase("frost")
		_start_frost_beam_recovery()

func _start_frost_beam_recovery() -> void:
	state = State.FROST_BEAM_RECOVERY
	_frost_beam_timer = attack_recovery_pause
	_head_pivot.rotation = 0.0  # head tilt resets to the untouched idle pose once the beam itself is done aiming

func _tick_frost_beam_recovery(delta: float) -> void:
	_frost_beam_timer -= delta
	if _frost_beam_timer <= 0.0:
		state = State.IDLE
		_active_attacks -= 1

# Phase 3's punish windows are the same mechanic as Phase 1/2 (still gated
# by PWOC, still per-attack) — just PHASE_3_PUNISH_WINDOW_REDUCTION shorter,
# floored at 0 so a short enough base duration can't go negative. Called by
# all three attacks' window logic below.
func _window_duration(base: float) -> float:
	return max(0.0, base - PHASE_3_PUNISH_WINDOW_REDUCTION) if phase >= 3 else base

# Widens Frost Beam's Line2D and its endpoint's hit-circle (+ the endpoint's
# separate visual ColorRect, which is sized via fixed offsets rather than
# reading the shape's radius — skipping it would leave the hitbox invisibly
# bigger than what's drawn) for Phase 3. Only ever called when phase >= 3;
# Phase 1/2 leaves the scene's baked default sizes completely untouched.
func _resize_frost_beam(width: float, endpoint_radius: float) -> void:
	_frost_beam.width = width
	var endpoint_shape: CollisionShape2D = _frost_beam_endpoint.get_node("CollisionShape2D")
	if endpoint_shape.shape is CircleShape2D:
		endpoint_shape.shape.radius = endpoint_radius
	var endpoint_visual: ColorRect = _frost_beam_endpoint.get_node("Visual")
	endpoint_visual.offset_left = -endpoint_radius
	endpoint_visual.offset_top = -endpoint_radius
	endpoint_visual.offset_right = endpoint_radius
	endpoint_visual.offset_bottom = endpoint_radius

# ── Wind Gust sequence ───────────────────────────────────────────────────────
# One combined 2s tween (windup + "flies up and back") -> hold -> visual gust
# sweeps right-to-left while Elana gets dragged toward the back of the arena
# at the same moment -> hold for the drag's own duration -> ease back to the
# original spot. No punish window, no tint, no element — this is a pure
# spacing tool, not one of the 3 cycling attacks.
func _run_wind_gust() -> void:
	_active_attacks += 1
	# Captured once here rather than read live, same "finishes naturally"
	# reasoning as the other attacks' own phase3_* lookups.
	var windup_time: float = phase3_wind_gust_windup_time if phase >= 3 else wind_gust_windup_time
	var windup_pos = _original_position + wind_gust_pullback_offset
	var windup_tween = create_tween()
	windup_tween.tween_property(self, "position", windup_pos, windup_time)
	await windup_tween.finished
	if not is_instance_valid(self):
		return

	_sweep_wind_gust_visual()
	await _drag_player_backward()
	if not is_instance_valid(self):
		return

	var return_tween = create_tween()
	return_tween.tween_property(self, "position", _original_position, windup_time * 0.3)
	await return_tween.finished
	if not is_instance_valid(self):
		return

	await get_tree().create_timer(attack_recovery_pause).timeout
	if not is_instance_valid(self):
		return
	_active_attacks -= 1

# Continuous, not a single computed-once impulse — apply_knockback() sets
# velocity fresh every physics frame for the full duration, so a single
# frame of wall/floor collision can't cut the pull short (each following
# frame's call just reasserts it) — this is what "rate of the drag is rate
# of knockback" actually needed to mean for it to read as a sustained pull
# rather than one shove that then gets undone by terrain. Locks her out of
# normal control the same way apply_drag_stun() did (apply_stun()), but
# fighting her own movement wasn't the point here anyway.
func _drag_player_backward() -> void:
	var target = get_tree().get_first_node_in_group("player")
	if not target or not target.has_method("apply_knockback"):
		return
	if target.has_method("apply_stun"):
		target.apply_stun(wind_gust_drag_duration)
	var elapsed := 0.0
	# +0.02 (a bit over one frame) so _knockback_timer never quite reaches 0
	# between this frame's call and the next one landing — no gap for her
	# own movement code to sneak back in for a frame.
	var per_frame_duration: float = get_physics_process_delta_time() + 0.02
	while elapsed < wind_gust_drag_duration:
		if not is_instance_valid(self) or not is_instance_valid(target):
			return
		# 2 full sine cycles across the whole drag (up/down/up/down), added
		# on top of the base vertical pull rather than replacing it — same
		# wave shape the visual gust rides, just applied to her actual
		# velocity instead of a cosmetic tween.
		var progress: float = elapsed / wind_gust_drag_duration
		var wave_y: float = wind_gust_drag_velocity.y + sin(progress * TAU * 2.0) * wind_gust_drag_wave_amplitude
		target.apply_knockback(Vector2(wind_gust_drag_velocity.x, wave_y), per_frame_duration, true)
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

# Purely cosmetic — no collision, no hit detection ("its just for visuals
# tho"). A long ColorRect (WindGustVisual's centered Visual child) tweened
# right-to-left across a wide span centered on Elemander's original spot,
# via the wrapper Node2D's own global_position — same "move the container,
# let the centered child ride along" pattern ElemanderDashCollision already
# uses for its own Visual child. Also weaves up/down/up/down while it
# sweeps, via a SECOND, separate Tween driving global_position:y through 4
# equal segments — kept as its own Tween object rather than one shared
# Tween with set_parallel(), since that would make the 4 Y segments race
# each other instead of chaining in sequence; two independent Tweens
# started together just run alongside each other for free.
func _sweep_wind_gust_visual() -> void:
	var visual: Node2D = $WindGustVisual
	var base_y = _original_position.y
	visual.global_position = Vector2(_original_position.x + wind_gust_visual_span, base_y)
	visual.visible = true

	var x_tween = create_tween()
	x_tween.tween_property(visual, "global_position:x", _original_position.x - wind_gust_visual_span, wind_gust_visual_sweep_time)

	var segment_time = wind_gust_visual_sweep_time / 4.0
	var y_tween = create_tween()
	y_tween.tween_property(visual, "global_position:y", base_y - wind_gust_visual_wave_amplitude, segment_time)
	y_tween.tween_property(visual, "global_position:y", base_y + wind_gust_visual_wave_amplitude, segment_time)
	y_tween.tween_property(visual, "global_position:y", base_y - wind_gust_visual_wave_amplitude, segment_time)
	y_tween.tween_property(visual, "global_position:y", base_y + wind_gust_visual_wave_amplitude, segment_time)

	await x_tween.finished
	if is_instance_valid(visual):
		visual.visible = false

# ── Fire Dash sequence ───────────────────────────────────────────────────────
# Windup (flame tint + scripted fly-back — position tween, not velocity/
# move_and_slide(), so it doesn't reopen the "never physically moves" fix)
# -> body hides -> 4 passes of (pick a random dash area, warning flash,
# ElemanderDashCollision sweeps across it, direction alternating starting
# right-to-left) -> body reappears back at its original spot -> overheat
# punish window (adds "fire" to active_elements), now gated by
# _roll_punish_window() same as the other two attacks, instead of
# guaranteed every time. is_instance_valid(self) guarded after every await,
# same convention dialog_marker.gd's cutscenes use, in case Elemander dies
# partway through (on_hit -> _apply_damage -> _die() -> queue_free() could
# land mid-sequence).
func _run_fire_dash() -> void:
	_active_attacks += 1
	_set_attack_tint("fire_dash", FIRE_DASH_TINT)
	await get_tree().create_timer(fire_dash_windup_time).timeout
	if not is_instance_valid(self):
		return

	# Elemander faces left, so "backwards" (away from its facing) is +X.
	var back_pos = _original_position + Vector2(fire_dash_pullback_distance, 0)
	var pullback_tween = create_tween()
	pullback_tween.tween_property(self, "position", back_pos, fire_dash_pullback_time)
	await pullback_tween.finished
	if not is_instance_valid(self):
		return

	_body_sprite.visible = false
	_head.visible = false
	# The real body/Hurtbox physically relocates to back_pos and sits there
	# invisible for the whole dash — still a live target otherwise (nothing
	# else in this script ever touches these), so melee could still land a
	# hit on an invisible boss sitting off to the side. Disabling both
	# collision shapes here (same .disabled convention ceiling_dropper.gd
	# uses for its own dormant state -- 2026-08-30, both converted from
	# CollisionShape2D to CollisionPolygon2D so the user can trace the real
	# sprite's silhouette; same .disabled property either way) makes the real
	# body genuinely untouchable for the dash's duration, not just hard to
	# see. Restored once she's back in place at the end.
	$CollisionPolygon2D.disabled = true
	$Hurtbox/CollisionPolygon2D.disabled = true

	# Phase 3 does more passes with a shorter warning each — captured once
	# here rather than read live inside the loop, so a phase change landing
	# mid-sequence (a hit crossing 15% while this is already running) can't
	# alter an already-started dash, same "finishes naturally" rule the
	# phase transition itself follows elsewhere.
	var pass_count: int = phase3_fire_dash_pass_count if phase >= 3 else fire_dash_pass_count
	var warning_time: float = phase3_fire_dash_warning_time if phase >= 3 else fire_dash_warning_time

	var right_to_left = true
	for i in pass_count:
		var area: Area2D = _dash_areas[randi() % _dash_areas.size()]
		var warn_flash: ColorRect = area.get_node("WarnFlash")
		await _blink_dash_warning(warn_flash, warning_time)
		if not is_instance_valid(self):
			return

		await _sweep_dash_collision(area, right_to_left)
		if not is_instance_valid(self):
			return
		right_to_left = not right_to_left

		await get_tree().create_timer(fire_dash_gap_time).timeout
		if not is_instance_valid(self):
			return

	_body_sprite.visible = true
	_head.visible = true
	position = _original_position
	$CollisionPolygon2D.disabled = false
	$Hurtbox/CollisionPolygon2D.disabled = false

	# Tint clears after this check regardless of which branch runs — held
	# through the punish window if one opens (previously it reset the
	# instant the dash passes finished, before the window even started, so
	# a won window had zero visual telegraph that "fire" was resisted).
	if _roll_punish_window("fire_dash"):
		active_elements["fire"] = true
		await get_tree().create_timer(_window_duration(fire_dash_window_duration)).timeout
		if not is_instance_valid(self):
			return
		active_elements.erase("fire")
	_clear_attack_tint("fire_dash")
	await get_tree().create_timer(attack_recovery_pause).timeout
	if not is_instance_valid(self):
		return
	_active_attacks -= 1

# Blinks on/off every fire_dash_warning_flash_interval for the given
# warning_time window (Phase 1/2 passes fire_dash_warning_time, Phase 3
# passes the shorter phase3_fire_dash_warning_time — see the caller), ending
# hidden (ready for the sweep). Guards self AND warn_flash individually — the
# loop already returns early via the self check, but warn_flash itself lives
# on a DashArea, a separate node from Elemander, so it gets its own
# is_instance_valid() at the very end in case something unrelated freed just
# that one area mid-blink.
func _blink_dash_warning(warn_flash: ColorRect, warning_time: float) -> void:
	var elapsed := 0.0
	var flash_on := false
	while elapsed < warning_time:
		flash_on = not flash_on
		warn_flash.visible = flash_on
		await get_tree().create_timer(fire_dash_warning_flash_interval).timeout
		if not is_instance_valid(self):
			return
		elapsed += fire_dash_warning_flash_interval
	if is_instance_valid(warn_flash):
		warn_flash.visible = false

# Sweeps ElemanderDashCollision across the given area's full width at that
# area's Y level, right-to-left or left-to-right. Damage polls
# get_overlapping_bodies() every physics frame during the sweep (see
# _check_dash_collision_overlap()), once per pass (_fire_dash_hit_this_pass
# reset here, not per-frame). Uses the CollisionShape2D's own
# global_position, not the Area2D's — the shape has its own local offset
# within the area (same double-offset trap the trigger zone hit earlier),
# so anchoring on the area alone would sweep at the wrong spot entirely.
func _sweep_dash_collision(area: Area2D, right_to_left: bool) -> void:
	var shape_node: CollisionShape2D = area.get_node("CollisionShape2D")
	var shape: RectangleShape2D = shape_node.shape
	var half_width = shape.size.x / 2.0
	var center = shape_node.global_position
	var y = center.y
	var left_x = center.x - half_width
	var right_x = center.x + half_width
	var start_x = right_x if right_to_left else left_x
	var end_x = left_x if right_to_left else right_x

	_spawn_fire_patch(area)

	_fire_dash_hit_this_pass = false
	_dash_collision.global_position = Vector2(start_x, y)
	_dash_collision.visible = true
	var tween = create_tween()
	tween.tween_property(_dash_collision, "global_position:x", end_x, fire_dash_sweep_time)
	while tween.is_valid() and tween.is_running():
		_check_dash_collision_overlap(right_to_left)
		await get_tree().physics_frame
		if not is_instance_valid(self):
			return
	_check_dash_collision_overlap(right_to_left)
	if is_instance_valid(_dash_collision):
		_dash_collision.visible = false

# No raycasting — checks every tile cell that actually overlaps the dash
# area's real collision box (both width AND height, not just a single
# sampled point) directly against the terrain grid, and paints whichever of
# those cells actually have a floor tile onto MOLTEN_OVERLAY_LAYER.
# terrain_hazards.gd treats any tile present there as molten regardless of
# what's on the real floor layer underneath, so this only affects the exact
# cells actually inside the box, nothing else sharing the same tile picture
# elsewhere on the map. If the box is tall enough to span two different
# terrain levels, both get caught naturally — no "which height" guessing.
# Erases the painted cells again after fire_patch_duration.
func _spawn_fire_patch(area: Area2D) -> void:
	var terrain: TileMap = get_tree().current_scene.get_node_or_null("Terrain")
	if terrain == null:
		return
	var shape_node: CollisionShape2D = area.get_node("CollisionShape2D")
	var shape: RectangleShape2D = shape_node.shape
	var half: Vector2 = shape.size / 2.0
	var top_left = shape_node.global_position - half
	var bottom_right = shape_node.global_position + half
	var cell_a: Vector2i = terrain.local_to_map(terrain.to_local(top_left))
	var cell_b: Vector2i = terrain.local_to_map(terrain.to_local(bottom_right))
	# Shows exactly what box got checked — a yellow rectangle outline
	# matching the actual cell range scanned, so "why did it tag the wrong
	# tile" is visible instead of a guess.
	_show_debug_box(top_left, bottom_right)
	var painted: Array = []
	for y in range(min(cell_a.y, cell_b.y), max(cell_a.y, cell_b.y) + 1):
		for x in range(min(cell_a.x, cell_b.x), max(cell_a.x, cell_b.x) + 1):
			var cell := Vector2i(x, y)
			var src_id := terrain.get_cell_source_id(TERRAIN_TILE_LAYER, cell)
			if src_id == -1:
				continue  # no floor tile here at all — nothing to paint
			if _is_water_tile(terrain, cell):
				continue
			terrain.set_cell(MOLTEN_OVERLAY_LAYER, cell, src_id,
				terrain.get_cell_atlas_coords(TERRAIN_TILE_LAYER, cell),
				terrain.get_cell_alternative_tile(TERRAIN_TILE_LAYER, cell))
			painted.append(cell)
	if painted.is_empty():
		return
	await get_tree().create_timer(fire_patch_duration).timeout
	if not is_instance_valid(terrain):
		return
	for cell in painted:
		terrain.set_cell(MOLTEN_OVERLAY_LAYER, cell, -1)

# Same "surface" custom-data layer WaterCheck.is_water() reads (a separate
# layer from "hazard" — water isn't itself a hazard, it's an environmental
# tag). Reads it directly here since the caller already has both the
# terrain reference and the cell coordinate on hand — cheaper than routing
# through that helper's own world-position lookup.
func _is_water_tile(terrain: TileMap, cell: Vector2i) -> bool:
	var data := terrain.get_cell_tile_data(TERRAIN_TILE_LAYER, cell)
	return data != null and data.get_custom_data("surface") == "water"

# Not awaited by the caller — runs independently for 2s so _spawn_fire_patch
# can continue immediately without waiting on the debug visual.
func _show_debug_box(top_left: Vector2, bottom_right: Vector2) -> void:
	_debug_raycast_line.global_position = top_left
	var size = bottom_right - top_left
	_debug_raycast_line.points = PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), Vector2.ZERO
	])
	_debug_raycast_line.visible = true
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(_debug_raycast_line):
		_debug_raycast_line.visible = false

# 1s windup (yellow tint) -> every water tile in the room electrifies at
# once -> electric_storm_bolt_count strikes at randomized intervals that
# average out to roughly fill electric_storm_duration (not perfectly even,
# so it doesn't feel metronomic) -> tint clears, water de-electrifies ->
# paralysis-style punish window, now gated by _roll_punish_window() same as
# the other two attacks, instead of guaranteed every time.
# 2026-08-30, real bug found: SceneTree.create_timer()'s process_always
# param defaults to TRUE -- every await below kept ticking (and the whole
# storm kept advancing -- windup, bolts, punish window) even while
# get_tree().paused was true (hud.gd's own options-menu pause). Every
# create_timer() call in this function now passes false explicitly so the
# whole sequence actually respects pause like everything else does.
func _run_electric_storm() -> void:
	_active_attacks += 1
	_set_attack_tint("electric_storm", ELECTRIC_STORM_TINT)
	await get_tree().create_timer(electric_storm_windup_time, false).timeout
	if not is_instance_valid(self):
		return

	active_elements["elec"] = true
	var terrain: TileMap = get_tree().current_scene.get_node_or_null("Terrain")
	# set_cell()/get_cell_source_id() hard-crash on a layer index that
	# doesn't exist yet — only touch the overlay if the 4th layer has
	# actually been added, so a missing editor step degrades to "no water
	# electrifies" instead of crashing the whole storm.
	var has_electrified_layer := terrain != null and terrain.get_layers_count() > ELECTRIFIED_OVERLAY_LAYER
	var electrified_cells: Array = _electrify_all_water(terrain) if has_electrified_layer else []

	# Phase 3 strikes are harder to dodge (wider hit-test) and flash bigger
	# (glow only — see _flash_electric_bolt(), the sprite itself never
	# scales) — captured once here, same "finishes naturally" reasoning as
	# Fire Dash's own pass_count/warning_time.
	var bolt_hit_width: float = phase3_electric_storm_bolt_width if phase >= 3 else electric_storm_bolt_width
	var bolt_glow_scale: float = phase3_electric_glow_scale if phase >= 3 else 1.0

	var avg_gap: float = electric_storm_duration / float(electric_storm_bolt_count)
	for i in electric_storm_bolt_count:
		var gap: float = randf_range(avg_gap * 0.4, avg_gap * 1.6)
		await get_tree().create_timer(gap, false).timeout
		if not is_instance_valid(self):
			if is_instance_valid(terrain):
				_de_electrify_water(terrain, electrified_cells)
			return
		# Every 5th bolt (5th, 10th, 15th...) aims at Elana's live position
		# instead of a random spot — still no telegraph, but it punishes
		# standing still often enough to keep her actually moving.
		_strike_electric_bolt((i + 1) % 5 == 0, bolt_hit_width, bolt_glow_scale)

	if is_instance_valid(terrain):
		_de_electrify_water(terrain, electrified_cells)

	# "elec" has been in active_elements since the windup ended, for the
	# whole storm — that part's unconditional. Only the extra hold afterward
	# (the actual punish window) is gated by the roll now.
	if _roll_punish_window("electric_storm"):
		await get_tree().create_timer(_window_duration(electric_storm_window_duration), false).timeout
		if not is_instance_valid(self):
			return
	_clear_attack_tint("electric_storm")
	active_elements.erase("elec")
	await get_tree().create_timer(attack_recovery_pause, false).timeout
	if not is_instance_valid(self):
		return
	_active_attacks -= 1

# Scans every used cell on the real floor layer (not just cells near
# Elemander) for the "surface"=="water" tag and paints all of them onto
# ELECTRIFIED_OVERLAY_LAYER at once — the whole room's water goes live
# together, not just water near wherever bolts happen to land.
func _electrify_all_water(terrain: TileMap) -> Array:
	var cells: Array = []
	for cell in terrain.get_used_cells(TERRAIN_TILE_LAYER):
		if _is_water_tile(terrain, cell):
			terrain.set_cell(ELECTRIFIED_OVERLAY_LAYER, cell,
				terrain.get_cell_source_id(TERRAIN_TILE_LAYER, cell),
				terrain.get_cell_atlas_coords(TERRAIN_TILE_LAYER, cell),
				terrain.get_cell_alternative_tile(TERRAIN_TILE_LAYER, cell))
			cells.append(cell)
	return cells

func _de_electrify_water(terrain: TileMap, cells: Array) -> void:
	for cell in cells:
		terrain.set_cell(ELECTRIFIED_OVERLAY_LAYER, cell, -1)

# Picks a random X within the shared AttackTriggerZone's own bounds (not a
# fixed radius around Elemander) — bolts only ever rain where that zone
# actually is. aim_at_elana (every 5th bolt) instead uses her live X,
# clamped into those same bounds so it still only ever lands inside the
# zone even if she's standing right at its edge. Flashes a vertical sprite
# bolt there for electric_storm_bolt_flash_time, and — no lingering
# hitbox, no per-frame polling — deals damage once, instantly, to Elana if
# her X is within hit_width of the strike at this exact moment. Y doesn't
# matter: it's a full-height vertical bolt, anyone under that column gets
# hit regardless of how high up they are. hit_width/glow_scale are passed in
# (Phase 1/2's base values or Phase 3's boosted ones — see the caller)
# rather than read straight off the exports, same reasoning as Fire Dash's
# pass_count/warning_time.
func _strike_electric_bolt(aim_at_elana: bool, hit_width: float, glow_scale: float) -> void:
	var trigger_shape: CollisionShape2D = $AttackTriggerZone/CollisionShape2D
	var trigger_rect: RectangleShape2D = trigger_shape.shape
	var half_width: float = trigger_rect.size.x * 0.5
	var center_x: float = trigger_shape.global_position.x
	var target = get_tree().get_first_node_in_group("player")

	var strike_x: float
	if aim_at_elana and target:
		strike_x = clamp(target.global_position.x, center_x - half_width, center_x + half_width)
	else:
		strike_x = center_x + randf_range(-half_width, half_width)

	var top := Vector2(strike_x, global_position.y - ELECTRIC_STORM_BOLT_HEIGHT * 0.5)
	var bottom := Vector2(strike_x, global_position.y + ELECTRIC_STORM_BOLT_HEIGHT * 0.5)
	_flash_electric_bolt(top, bottom, glow_scale)

	if target and abs(target.global_position.x - strike_x) <= hit_width * 0.5:
		if target.has_method("take_damage"):
			target.take_damage(electric_storm_bolt_damage, true, self, "elec")
		if target.has_method("apply_shock"):
			target.apply_shock(GameData.SHOCK_STUN_DURATION)

# Same segmented-sprite-chain technique elana.gd's _draw_elec_bolt() uses,
# just fixed to a straight-down angle instead of an arbitrary one — reuses
# the cached frames from _build_electric_bolt_frames() rather than rebuilding
# them per bolt. Each segment is its own fire-and-forget AnimatedSprite2D
# (matching elana.gd's own _spawn_elec_bolt_segment()), not awaited here.
# glow_scale (Phase 3 boosts this — see the caller) only ever reaches the
# glow calls below; the sprite segments above are never touched by it, so
# "bigger bolt" in Phase 3 is communicated purely through a bigger glow, not
# a stretched/scaled pixel-art sprite.
func _flash_electric_bolt(top: Vector2, bottom: Vector2, glow_scale: float = 1.0) -> void:
	var diff = bottom - top
	var dist = diff.length()
	var angle = diff.angle()
	var dir = diff.normalized() if dist > 0.0 else Vector2.DOWN
	var full_segments = int(dist / ELECTRIC_BOLT_NATIVE_WIDTH)
	for i in full_segments:
		var pos = top + dir * (ELECTRIC_BOLT_NATIVE_WIDTH * (float(i) + 0.5))
		_spawn_electric_bolt_segment(_electric_bolt_full_frames, pos, angle)
	var leftover = dist - float(full_segments) * ELECTRIC_BOLT_NATIVE_WIDTH
	if leftover > 1.0 and _electric_bolt_leftover_frames != null:
		var pos = top + dir * (ELECTRIC_BOLT_NATIVE_WIDTH * float(full_segments) + leftover / 2.0)
		_spawn_electric_bolt_segment(_electric_bolt_leftover_frames, pos, angle)

	# Same glow technique elana.gd's own _draw_elec_bolt() uses for her elec
	# zap — a line-light along the bolt's full length plus a radial burst at
	# the impact point (here, the ground strike at "bottom", not "top" —
	# elana.gd's own "to" is likewise always the actual impact point).
	_spawn_electric_bolt_glow(top + diff * 0.5, angle, dist, glow_scale)
	_spawn_electric_impact_glow(bottom, glow_scale)

func _spawn_electric_bolt_segment(frames: SpriteFrames, pos: Vector2, angle: float) -> void:
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.global_position = pos
	sprite.rotation = angle
	sprite.modulate = ELECTRIC_BOLT_TINT
	sprite.z_index = 15
	sprite.play("spark")
	get_tree().current_scene.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, electric_storm_bolt_flash_time)
	tween.tween_callback(sprite.queue_free)

# Linear fill instead of radial — fades only across the bolt's thickness
# (top-to-bottom of the texture) and stays uniformly bright along its full
# length, so it reads as a straight bar of light instead of an ellipse.
# Two layers: a normal one that fades slowly, and a thinner/hotter one on
# top that fades out quick. Identical to elana.gd's own _spawn_elec_bolt_
# glow()/_spawn_elec_line_light() — duplicated here rather than called
# directly since those are private to elana.gd's own instance. glow_scale
# multiplies both thickness and energy, so Phase 3's bolts flash visibly
# wider and brighter without the underlying sprite ever being touched.
func _spawn_electric_bolt_glow(pos: Vector2, angle: float, length: float, glow_scale: float = 1.0) -> void:
	_spawn_electric_line_light(pos, angle, length, 4.0 * glow_scale, 6.0 * glow_scale, 0.8)
	_spawn_electric_line_light(pos, angle, length, 8.0 * glow_scale, 10.0 * glow_scale, 0.15)

func _spawn_electric_line_light(pos: Vector2, angle: float, length: float, thickness: float, energy: float, fade_duration: float) -> void:
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
	tex.height = int(round(thickness))

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

# Two radial bursts stacked at the same spot (the bolt's ground-strike
# point) — a big one that fades slowly (matching the normal line's speed),
# and a smaller, more intense one on top that fades out quick (matching the
# intense line's speed). glow_scale grows both the burst's footprint (scale)
# and its brightness (energy), same idea as _spawn_electric_bolt_glow().
func _spawn_electric_impact_glow(pos: Vector2, glow_scale: float = 1.0) -> void:
	_spawn_electric_radial_light(pos, 0.18 * glow_scale, 0.3 * glow_scale, 5.0 * glow_scale, 0.8)
	_spawn_electric_radial_light(pos, 0.4 * glow_scale, 0.65 * glow_scale, 10.0 * glow_scale, 0.15)

func _spawn_electric_radial_light(pos: Vector2, start_scale: float, end_scale: float, energy: float, fade_duration: float) -> void:
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

# Called once from _ready() — ELECTRIC_STORM_BOLT_HEIGHT is a fixed const,
# so the leftover-remainder segment's size never changes between bolts;
# building both pieces once here and reusing them avoids reconstructing the
# same SpriteFrames/AtlasTexture resources 30 times per storm.
func _build_electric_bolt_frames() -> void:
	_electric_bolt_full_frames = SpriteFrames.new()
	_electric_bolt_full_frames.add_animation("spark")
	_electric_bolt_full_frames.set_animation_loop("spark", true)
	_electric_bolt_full_frames.set_animation_speed("spark", 12.0)
	for path in ELECTRIC_BOLT_FRAMES:
		_electric_bolt_full_frames.add_frame("spark", load(path))

	var full_segments = int(ELECTRIC_STORM_BOLT_HEIGHT / ELECTRIC_BOLT_NATIVE_WIDTH)
	var leftover = ELECTRIC_STORM_BOLT_HEIGHT - float(full_segments) * ELECTRIC_BOLT_NATIVE_WIDTH
	if leftover > 1.0:
		_electric_bolt_leftover_frames = SpriteFrames.new()
		_electric_bolt_leftover_frames.add_animation("spark")
		_electric_bolt_leftover_frames.set_animation_loop("spark", true)
		_electric_bolt_leftover_frames.set_animation_speed("spark", 12.0)
		for path in ELECTRIC_BOLT_FRAMES:
			var atlas = AtlasTexture.new()
			atlas.atlas = load(path)
			atlas.region = Rect2(0, 0, leftover, ELECTRIC_BOLT_NATIVE_HEIGHT)
			_electric_bolt_leftover_frames.add_frame("spark", atlas)

# Built once here, reused every frame the beam is active — same linear-fill
# gradient technique as the electric bolt's line light, blue-toned and
# fainter (FROST_BEAM_GLOW_ENERGY), fixed at FROST_BEAM_GLOW_BASE_WIDTH and
# stretched via scale.x in _update_frost_beam_visual() to match the beam's
# actual current length each frame.
func _build_frost_beam_glow_texture() -> void:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.5, 1])
	gradient.colors = PackedColorArray([
		Color(0.3, 0.7, 1.0, 0),
		Color(1.4, 1.8, 3.0, 1),
		Color(0.3, 0.7, 1.0, 0),
	])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = int(FROST_BEAM_GLOW_BASE_WIDTH)
	tex.height = 6

	_frost_beam_glow.texture = tex
	_frost_beam_glow.color = Color.WHITE
	_frost_beam_glow.energy = FROST_BEAM_GLOW_ENERGY
	_frost_beam_glow.texture_scale = 1.0

func _update_hp_bar() -> void:
	var pct = float(hp) / float(max_hp) if max_hp > 0 else 0.0
	_hp_fill.size.x = _hp_bg.size.x * clamp(pct, 0.0, 1.0)

func _apply_damage(damage: int) -> void:
	if hp <= 0:
		return
	hp -= damage
	# Elemander doesn't route through hit_handler.gd (too different a
	# shape), so it calls the same shared GameData.spawn_crit_aware_damage_
	# number() hit_handler.gd/hollowfang.gd use, instead of hand-copying
	# the consume-and-clear logic.
	GameData.spawn_crit_aware_damage_number(damage, global_position)
	if hp <= 0:
		hp = 0
		_die()
		return
	# Checked highest phase first so one big hit that skips straight past
	# 50% down to 15% still lands in Phase 3, not stuck at Phase 2. Setting
	# the flag here is the only thing this function needs to do — Phase 2's
	# pairing already covers Phase 3 too (_start_random_attack()'s
	# "phase >= 2" check), and every individual attack's boost/window-
	# duration lookups just read `phase` reactively at their own start, so
	# nothing needs to be kicked off from this exact moment; the current
	# attack (if any) is left alone to finish naturally rather than being
	# interrupted mid-sequence.
	if phase < 3 and hp <= max_hp * PHASE_3_HP_RATIO:
		phase = 3
	elif phase < 2 and hp <= max_hp * PHASE_2_HP_RATIO:
		phase = 2

# Death sequence (motes/blessing/checkpoint, matching Hollowfang's own
# eventual reveal) is still open — same as Hollowfang's is per the bosses
# backlog. Persistence + reward wiring below is NOT part of that open item
# though — mark_removed()/gain_xp()/reset_boss_camera() were simply missing
# outright (2026-08-20 fix): killing him never paid xp_reward, never
# persisted the kill (is_removed() guard added in _ready() above), and left
# the boss camera lock stuck on permanently.
func _die() -> void:
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	GameData.gain_xp(xp_reward)
	GameData.reset_boss_camera()
	queue_free()

# Standard on_hit/on_elemental_hit interface, same shape hit_handler.gd's is
# (so the generic swing-hitbox call site elana.gd already uses works
# unmodified) — but routed through _apply_damage() directly instead, same
# choice Hollowfang made, since neither boss uses the shared HitHandler
# component.
func on_hit(_hit_direction: int, damage: int, is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	# is_magic here just means "not a physical weapon swing" for callers like
	# Bulwark's reflect that don't know a specific element — treated as
	# already-resolved damage, no defense reduction (matches hit_handler.gd's
	# own on_hit()'s is_magic branch skipping the stun/knockback path, not
	# skipping defense — Elemander's physical defense specifically only
	# applies to real weapon swings per the doc's "high baseline physical
	# defense" identity).
	var final_damage: int = damage if is_magic else GameData.calc_damage(float(damage), float(body_defense))
	_apply_damage(final_damage)

func on_elemental_hit(element: String, _hit_direction: int, damage: int, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	var mult: float = ELEMENT_MATCH_MULT if active_elements.has(element) else 1.0
	_apply_damage(max(1, int(round(float(damage) * mult))))

# Same reasoning as Hollowfang's blocks_chain_pull() — a 200x512 boss getting
# reeled in by a chain hook wouldn't make sense, and chain_projectile.gd's
# pull writes to fields (is_stunned/_pending_knockback) this script, like
# Hollowfang's, doesn't declare.
func blocks_chain_pull() -> bool:
	return true

# Same opt-in hook Hollowfang's own get_targeting_points() implements, for
# the exact same reason: elana.gd's Electric Herb bolt + chain lightning
# both use a ~125-150px range check against a single point, which a boss
# this size (512 tall) would almost never actually be within — she'd have
# to stand nearly on top of one exact spot on his origin. The 5
# ElectricBoltPoint nodes (spread across his body in the editor) give
# elana.gd's targeting several points to pick the closest of instead of
# one fixed spot, so the zap can connect near whichever part of him she's
# actually standing near.
func get_targeting_points() -> Array:
	var points: Array = [
		$ElectricBoltPoint1/CollisionShape2D.global_position,
		$ElectricBoltPoint2/CollisionShape2D.global_position,
		$ElectricBoltPoint3/CollisionShape2D.global_position,
		$ElectricBoltPoint4/CollisionShape2D.global_position,
		$ElectricBoltPoint5/CollisionShape2D.global_position,
	]
	# Fire Dash's sweeping hitbox is the only part of him actually visible
	# and near her during the dash — the real body (the 5 points above) sits
	# invisible, collision-disabled, off at back_pos for the whole sequence
	# (see _run_fire_dash()). Adding the dash collision's own live position
	# as a 6th candidate, only while it's actually active, lets the zap
	# reach the part of him she can actually see and stand near instead of
	# only ever offering 5 points that are off-screen and out of range for
	# the entire dash.
	if _dash_collision.visible:
		points.append(_dash_collision.global_position)
	return points
