extends Node2D

const FOLLOW_SPEED: float = 10.0
const NATURAL_COLOR: Color = Color(0.6, 0.95, 1.0, 0.9)

const WEAPON_LIGHT_OFFSET: Dictionary = {
	"fist":       Vector2(16, 16),
	"sword":      Vector2(32, 8),
	"spear":      Vector2(48, 5),
	"warhammer":  Vector2(22, 20),
	"chain_claw": Vector2(14, 14),
}

const WEAPON_LUNGE: Dictionary = {
	"sword":      16.0,
	"spear":      26.0,
	"warhammer":  14.0,
	"chain_claw": 5.0,
}

var _hover_time: float = 0.0
var _flash_timer: float = 0.0
var _kill_flash_timer: float = 0.0
var _swing_flash_timer: float = 0.0
var _story_glow_active: bool = false
var _story_glow_elapsed: float = 0.0
const STORY_GLOW_PULSE_SPEED: float = 8.0
var _prev_hp: int = 0
var _prev_xp: int = 0
var _was_attacking: bool = false
var _warhammer_delay: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _light: PointLight2D = $Light
@onready var _herb_glow: PointLight2D = $HerbGlow
@onready var _scout_camera: Camera2D = $ScoutCamera
@onready var _body_shape: CollisionShape2D = $BodyShape
var _base_light_scale: float = 1.0
var _effects_material: ShaderMaterial = null
# Multiplies the main light's energy/scale in _update_light() — driven down
# by area effects like Pollen Puffer's cloud, decays back to 1.0 (full
# brightness) once nothing is actively holding it down. Same
# min-factor/max-duration merge pattern elana.gd's own apply_slow() uses,
# so repeated calls from an enemy standing in a cloud tick correctly.
var _dim_factor: float = 1.0
var _dim_timer: float = 0.0

func apply_light_dim(factor: float, duration: float) -> void:
	_dim_factor = min(_dim_factor, factor)
	_dim_timer = max(_dim_timer, duration)

# Explicit early-cancel, separate from apply_light_dim()'s own auto-expiry
# (2026-08-25, added for Wyrmbat's Blackout Canopy zone-gating -- the dim
# needs to end the instant Elana leaves the darkened floor zone, not wait
# out whatever duration was originally applied).
func cancel_light_dim() -> void:
	_dim_factor = 1.0
	_dim_timer = 0.0

# Independent scouting — she detaches, roams under WASD with simple wall
# collision, and beelines back through everything once recalled.
const SCOUT_SPEED: float = 180.0
const SCOUT_RETURN_SPEED: float = 750.0
# Shrunk from the enemy proximity-activation radius minus 50 (650) to make
# investing in the Scouting Distance skill actually matter — the per-level
# bonus grew to match, so a fully-leveled max (770) is unchanged from
# before, only the un-upgraded starting point is shorter now.
const SCOUT_LEASH_RADIUS_BASE: float = 350.0
const SCOUT_ARRIVE_DIST: float = 6.0

# Base leash + Scouting Distance skill's per-level bonus (GameData.gd,
# child of Luminosity+) — a function, not a const, since the bonus changes
# at runtime as skill points get spent.
func _scout_leash_radius() -> float:
	return SCOUT_LEASH_RADIUS_BASE + GameData.scout_leash_radius_bonus
var _was_scouting: bool = false

func _ready() -> void:
	_prev_hp = GameData.hp
	_prev_xp = GameData.xp
	z_index = 1
	_base_light_scale = _light.texture_scale
	_effects_material = ShaderMaterial.new()
	_effects_material.shader = preload("res://elana_sprite_effects.gdshader")
	_sprite.material = _effects_material

func _process(delta: float) -> void:
	if GameData.glint_scouting:
		if not _was_scouting:
			_was_scouting = true
			_sprite.visible = true
			_sprite.modulate = NATURAL_COLOR
			_scout_camera.make_current()
			# A stuck episode's cached recovery target (see
			# _move_with_collision()) is picked differently per mode
			# (nearest clear point while scouting, always Elana's position
			# while attached) — clearing this on every mode transition
			# stops a target picked under the other mode from lingering in
			# across the switch.
			_was_stuck_last_frame = false
		_process_scouting(delta)
		return
	if _was_scouting:
		_was_stuck_last_frame = false
	_was_scouting = false
	_hover_time += delta
	if _dim_timer > 0.0:
		_dim_timer -= delta
		if _dim_timer <= 0.0:
			_dim_factor = 1.0
	_flash_timer = max(0.0, _flash_timer - delta)
	_kill_flash_timer = max(0.0, _kill_flash_timer - delta)
	_swing_flash_timer = max(0.0, _swing_flash_timer - delta)
	if _story_glow_active:
		_story_glow_elapsed += delta
		var pulse = 0.5 + 0.5 * sin(_story_glow_elapsed * STORY_GLOW_PULSE_SPEED)
		_effects_material.set_shader_parameter("glow_outline_alpha", pulse)

	var elana = get_parent()
	var weapon = GameData.current_weapon
	var has_weapon = weapon != "fist"
	var has_herb = GameData.active_herb != null

	# Normally mirrors Elana's own facing (hovers beside/behind her, looking
	# the same way she does). During a frozen cutscene lock she's instead
	# posed in front of Elana's face — flip the other way so they visibly
	# face each other instead of both facing the same direction.
	if GameData.glint_position_locked and not GameData.glint_lock_follows_facing:
		_sprite.flip_h = elana.facing == 1
	else:
		_sprite.flip_h = elana.facing == -1

	if GameData.hp < _prev_hp:
		_flash_timer = 0.25
	_prev_hp = GameData.hp

	if GameData.xp > _prev_xp:
		_kill_flash_timer = 0.2
	_prev_xp = GameData.xp

	var attacking = elana.is_swinging()
	if attacking and not _was_attacking:
		_swing_flash_timer = 0.15
		# only the normal swing has a windup — the charged spin starts instantly
		if weapon == "warhammer" and not elana.is_heavy_attack:
			_warhammer_delay = 0.5
	_was_attacking = attacking
	if not attacking:
		_warhammer_delay = 0.0
	else:
		_warhammer_delay = max(0.0, _warhammer_delay - delta)

	_update_shape(weapon, has_weapon, elana.facing)
	if GameData.glint_position_locked:
		_update_locked_position(delta, elana)
	else:
		_update_position(delta, elana, weapon, has_weapon)
	_update_color(has_weapon, has_herb)
	_update_light(has_weapon, has_herb)

# Scripted cutscene positioning — dynamic mode holds her opposite Elana's
# current facing (a "stays behind you" lock); frozen mode leaves her exactly
# where she is regardless of facing changes, so a turn can reveal her.
func _update_locked_position(delta: float, elana: Node) -> void:
	if GameData.glint_lock_follows_facing:
		var target = Vector2(-elana.facing * 18.0, -20.0)
		position = position.lerp(target, FOLLOW_SPEED * delta)

func _process_scouting(delta: float) -> void:
	var elana = get_parent()
	# Tracks Elana's own camera zoom live (already smoothed on her end) so
	# scouting doesn't jump to a fixed zoom regardless of what she was at —
	# matters e.g. during a boss fight's wide GameData.boss_zoom_active view.
	_scout_camera.zoom = elana.get_node("Camera").zoom
	# Same idle bob as when attached to Elana — applied to the sprite only
	# (not global_position), so it's purely visual and never perturbs the
	# collision-relevant scout movement/raycast checks.
	_hover_time += delta
	_sprite.position.y = sin(_hover_time * 2.5) * 4.0
	if GameData.glint_scout_returning:
		# Recalled — beeline home, ignoring every obstacle in between.
		var to_elana = elana.global_position - global_position
		if to_elana.length() <= SCOUT_ARRIVE_DIST:
			global_position = elana.global_position
			GameData.glint_scouting = false
			GameData.glint_scout_returning = false
			# Reverts to fist the normal way if the 2/sec scouting drain
			# (elana.gd's _tick_scout_weapon_drain()) actually emptied her
			# weapon's HP during the trip — no-op otherwise, leaving
			# whatever weapon she had equipped intact.
			GameData.check_weapon_depletion()
			elana.get_node("Camera").make_current()
		else:
			global_position += to_elana.normalized() * SCOUT_RETURN_SPEED * delta
	else:
		var move_dir = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down"))
		if move_dir.length() > 0.0:
			move_dir = move_dir.normalized()
			var intended = global_position + move_dir * SCOUT_SPEED * delta
			var from_elana = intended - elana.global_position
			var leash_radius: float = _scout_leash_radius()
			if from_elana.length() > leash_radius:
				intended = elana.global_position + from_elana.normalized() * leash_radius
			global_position = _move_with_collision(global_position, intended, elana.global_position, delta, true)
	# Same glow logic attached mode uses (luminosity/herb-integration bonus
	# affecting both brightness and reach) instead of a separate hardcoded
	# energy target — scouting used to skip all of that entirely. Weapon is
	# always effectively "fist" while scouting (same convention elana.gd's
	# own visual_weapon uses), so has_weapon is always false here.
	_update_light(false, GameData.active_herb != null)

# Shape-based block against terrain/solid obstacles (same layer Elana
# collides with) — checks her actual BodyShape (see glint.tscn, an 8px-
# radius circle) against terrain rather than a single point/line. Kept
# smaller than her 12x12 sprite, not bigger — an earlier bigger-than-sprite
# shape (a 16px circle) made her read as "stuck" against geometry her
# sprite visually only barely grazed, since the shape itself was catching
# on corners well before anything looked wrong on screen. A smaller shape
# means her sprite can very slightly overlap a wall at the edges before
# collision kicks in, which reads as normal hover wobble rather than a bug
# — a better trade than the opposite failure. Used by both scouting (above)
# and the normal attached-follow hover (see _update_position()) — she still
# moves/tethers toward Elana either way, she just can't overlap a wall
# beyond that small margin to get there.
const STUCK_NUDGE_SPEED: float = 60.0  # world px/sec — slow, deliberate escape

# 8 compass directions, fixed order — used both to search a small nearby
# area for a clear point and as local step candidates when the direct step
# toward the current recovery target is itself blocked.
# var, not const — .normalized() is a method call, not a constant
# expression, so GDScript's const initializer rejects it at parse time
# (confirmed: "Assigned value for constant _STUCK_DIRECTIONS isn't a
# constant expression").
var _STUCK_DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT, Vector2(1, 1).normalized(), Vector2.DOWN, Vector2(-1, 1).normalized(),
	Vector2.LEFT, Vector2(-1, -1).normalized(), Vector2.UP, Vector2(1, -1).normalized(),
]
# Kept deliberately small — "stuck" almost always means barely clipping a
# corner/edge, not being deeply embedded far from any opening. A wide
# search radius is the specific thing that went wrong in an earlier attempt
# at this: it only checks whether a CANDIDATE point itself overlaps, not
# whether a path to it does, so a big radius could "find" a point that
# reads as clear but is only reachable by cutting through solid geometry to
# get there (confirmed — that's what made her visibly cut through walls).
# Capped at 3 rings of 8px (24px total) keeps any found point close enough
# that there's essentially no room for a wall to meaningfully separate her
# from it.
const _STUCK_SEARCH_RING_STEP: float = 8.0
const _STUCK_SEARCH_MAX_RINGS: int = 3

# Cached per stuck episode, not recomputed every frame — recomputing fresh
# each frame is what made an even earlier "nudge toward whichever direction
# is clear" attempt flicker/oscillate and get reverted (see git history).
# Reset on scouting/attached-follow mode transitions (_process()) so a
# stale target from one mode can't leak into the other.
var _stuck_recovery_target: Vector2 = Vector2.INF
var _was_stuck_last_frame: bool = false

func _shape_clear_at(space: PhysicsDirectSpaceState2D, pos: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _body_shape.shape
	query.collision_mask = 1
	query.transform = Transform2D(0.0, pos)
	return space.intersect_shape(query, 1).is_empty()

# Searches the small area above outward from `from` for the nearest
# position her shape doesn't overlap terrain at. Falls back to `fallback`
# (always Elana's position) if nothing turns up within that small radius.
func _find_nearest_clear_point(space: PhysicsDirectSpaceState2D, from: Vector2, fallback: Vector2) -> Vector2:
	for ring in range(1, _STUCK_SEARCH_MAX_RINGS + 1):
		var radius: float = ring * _STUCK_SEARCH_RING_STEP
		for dir in _STUCK_DIRECTIONS:
			var candidate: Vector2 = from + dir * radius
			if _shape_clear_at(space, candidate):
				return candidate
	return fallback

# safe_pos is Elana's own current position — always guaranteed clear of
# solid terrain, since SHE has real physics collision and can never be
# inside a wall. use_nearest_safe_when_stuck (scouting only — see
# _process_scouting()) retargets recovery to the nearest clear point
# instead of always Elana's own position, since a straight trip back to
# her could be a long way during a scouting excursion; attached-follow
# mode doesn't need this since Elana is always right there anyway.
#
# Every recovery step below is validated with its own shape query before
# being taken, whichever target is in play — an earlier version nudged
# straight toward the target with NO check along the way at all, which
# during scouting specifically (Elana potentially a whole leash-radius
# away, in a different room) walked her directly through whatever solid
# geometry was in between. First attempt at recovery jumped 90% of the way
# there in one frame, which looked sudden/clunky; nudging toward safe_pos
# at a slow speed fixed that, but not the through-walls bug — this fixes
# both, plus (see the search consts above) keeps the nearest-point search
# tight enough that the target itself can't end up on the wrong side of a
# wall either.
func _move_with_collision(from: Vector2, to: Vector2, safe_pos: Vector2, delta: float, use_nearest_safe_when_stuck: bool = false) -> Vector2:
	var space = get_world_2d().direct_space_state
	if not _shape_clear_at(space, from):
		if not use_nearest_safe_when_stuck:
			# Attached-follow: exact original behavior, byte-for-byte
			# unchanged from the long-confirmed-working version — nudge
			# straight toward Elana (always close by, so a straight line
			# essentially never has anything meaningful to cross) at a
			# fixed slow speed, no per-step validation. Deliberately kept
			# isolated from the scouting logic below so nothing about
			# tuning that path can ever regress this one again.
			var to_safe: Vector2 = safe_pos - from
			var step: float = STUCK_NUDGE_SPEED * delta
			if to_safe.length() <= step:
				return safe_pos
			return from + to_safe.normalized() * step
		# Scouting only, from here down: nearest-clear-point recovery
		# target (cached per stuck episode), every step validated before
		# being taken — see this function's own top comment for why.
		if not _was_stuck_last_frame:
			_stuck_recovery_target = _find_nearest_clear_point(space, from, safe_pos)
		_was_stuck_last_frame = true
		var step_len: float = STUCK_NUDGE_SPEED * delta
		var toward_target: Vector2 = _stuck_recovery_target - from
		# Try the direct step toward the (cached) target first — cheap,
		# and correct for the common case where nothing's actually between
		# her and it.
		if toward_target.length() > 0.0:
			var direct_step: Vector2 = from + toward_target.normalized() * min(step_len, toward_target.length())
			if _shape_clear_at(space, direct_step):
				return direct_step
		# Direct path blocked — fall back to whichever of the 8 candidate
		# directions is both clear AND makes the most progress toward the
		# target, so she routes around an obstacle via only ever-validated
		# steps instead of either stopping dead or cutting through it.
		var best: Vector2 = from
		var best_dist: float = from.distance_to(_stuck_recovery_target)
		for dir in _STUCK_DIRECTIONS:
			var candidate: Vector2 = from + dir * step_len
			if not _shape_clear_at(space, candidate):
				continue
			var dist: float = candidate.distance_to(_stuck_recovery_target)
			if dist < best_dist:
				best_dist = dist
				best = candidate
		return best
	_was_stuck_last_frame = false
	if from == to:
		return to
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = _body_shape.shape
	shape_query.collision_mask = 1
	shape_query.transform = Transform2D(0.0, from)
	# cast_motion() sweeps the shape from `from` along (to - from) in one
	# call and returns the safe fraction of that move before it would hit
	# anything — replaced a two-step "check the destination is clear, and
	# if not, separately ray-cast to approximate where it's blocked" pair.
	# That had a real gap (confirmed by testing): a destination overlap
	# with a clean from->to centerline ray (e.g. her shape clipping a wall
	# corner from a diagonal approach, where the ray itself passes through
	# the gap beside it) fell through both checks and returned `from`
	# unchanged — every frame recomputed the same result, freezing her in
	# place instead of continuing to track Elana. cast_motion() answers
	# "how far can this actual shape go" directly, with no ray-vs-shape
	# approximation gap to fall through.
	shape_query.motion = to - from
	var safe_fraction: float = space.cast_motion(shape_query)[0]
	return from + shape_query.motion * safe_fraction

# Public — cutscenes trigger a gold glow that persists until stop_story_glow()
# is called, without fighting _update_color's per-frame overwrite. Same
# start/stop pattern as elana.gd's trigger_story_glow/stop_story_glow.
func trigger_story_glow() -> void:
	_story_glow_active = true
	_story_glow_elapsed = 0.0

func stop_story_glow() -> void:
	_story_glow_active = false
	_effects_material.set_shader_parameter("glow_outline_alpha", 0.0)

func _update_shape(weapon: String, has_weapon: bool, facing: int) -> void:
	_sprite.visible = not has_weapon
	var size = WEAPON_LIGHT_OFFSET.get(weapon, Vector2(16, 16)) if has_weapon else Vector2(16, 16)
	_light.position = Vector2(facing * size.x / 2.0, size.y / 2.0)

func _update_position(delta: float, elana: Node, weapon: String, has_weapon: bool) -> void:
	var target: Vector2
	var speed: float = FOLLOW_SPEED
	if has_weapon:
		var attacking = elana.is_swinging()
		var lunge_ready: bool
		if weapon == "warhammer":
			lunge_ready = attacking and _warhammer_delay <= 0.0
		else:
			lunge_ready = attacking
		if lunge_ready:
			var dist = WEAPON_LUNGE.get(weapon, 18.0)
			target = Vector2(elana.facing * dist, 3.0)
			speed = 30.0
		else:
			target = Vector2(0.0, 3.0)
	else:
		var hover = Vector2(0.0, sin(_hover_time * 2.5) * 4.0)
		target = Vector2(elana.facing * 18.0, -20.0) + hover
	# Still tethered/lerping toward target exactly as before — just routed
	# through the same wall-collision check scouting already uses, so she
	# stops just short of a wall she'd otherwise hover into/through instead
	# of clipping through it, without breaking the follow behavior itself.
	var intended_local: Vector2 = position.lerp(target, speed * delta)
	var intended_global: Vector2 = elana.to_global(intended_local)
	var allowed_global: Vector2 = _move_with_collision(global_position, intended_global, elana.global_position, delta)
	position = elana.to_local(allowed_global)

func _update_color(has_weapon: bool, has_herb: bool) -> void:
	if GameData.transform_delay_timer > 0.0:
		_sprite.modulate = Color(0.5, 0.5, 0.55)
		return
	var col: Color
	if _story_glow_active:
		col = Color(1.4, 1.2, 0.5)
	elif _flash_timer > 0.0:
		col = Color(1.0, 0.2, 0.2)
	elif _kill_flash_timer > 0.0:
		col = Color(1.0, 1.0, 0.4)
	elif _swing_flash_timer > 0.0:
		col = Color(1.0, 1.0, 0.9)
	elif has_weapon:
		col = GameData.weapon_color
	else:
		col = NATURAL_COLOR

	if has_herb and _flash_timer <= 0.0 and _kill_flash_timer <= 0.0:
		col = col.lerp(GameData.active_herb.color, 0.4)

	_sprite.modulate = col

func _update_light(has_weapon: bool, has_herb: bool) -> void:
	# Luminosity+ (Elana tree, +25%/lvl) and Herb Integration (Glint tree,
	# flat +30% while a herb is active) add together, not multiply — maxed
	# Luminosity+ (75%) plus Herb Integration is +105% total, not +127.5%.
	# Computed before target_energy now (moved up) so it can boost brightness
	# too, not just reach — previously only fed into target_scale, so a
	# "brighter light" skill only ever made her glow bigger, never actually
	# brighter.
	var glow_bonus: float = GameData.glint_luminosity_bonus
	if has_herb and GameData.get_glint_skill_level("g_herb_integration") >= 1:
		glow_bonus += 0.3

	var target_energy: float
	if _swing_flash_timer > 0.0 or _kill_flash_timer > 0.0:
		target_energy = 1.8
	elif has_weapon and GameData.glint_max_hp > 0.0:
		var ratio = clamp(GameData.glint_hp / GameData.glint_max_hp, 0.0, 1.0)
		target_energy = lerp(0.7, 1.3, ratio)
	else:
		target_energy = 1.0
	target_energy *= (1.0 + glow_bonus)

	# _dim_factor (default 1.0, driven down by apply_light_dim — see below)
	# multiplies both energy and scale, so a dim reads as the light genuinely
	# weakening rather than just a tint change.
	_light.energy = lerp(_light.energy, target_energy * _dim_factor, 0.12)
	# Main light stays white — it's the scene's primary illumination, so
	# tinting it to the herb color would wash the whole visible area instead
	# of just Glint. The herb tint lives on the small HerbGlow light instead.
	_light.color = _light.color.lerp(Color.WHITE, 0.15)
	var target_scale: float = _base_light_scale * (1.0 + glow_bonus) * _dim_factor
	_light.texture_scale = lerp(_light.texture_scale, target_scale, 0.1)

	var herb_glow_target: float = 1.4 if has_herb else 0.0
	_herb_glow.energy = lerp(_herb_glow.energy, herb_glow_target, 0.12)
	if has_herb:
		_herb_glow.color = _herb_glow.color.lerp(GameData.active_herb.color, 0.2)
