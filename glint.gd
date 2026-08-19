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

# Independent scouting — she detaches, roams under WASD with simple wall
# collision, and beelines back through everything once recalled. Leash is
# 50px tighter than the enemy proximity-activation radius they already share.
const SCOUT_SPEED: float = 180.0
const SCOUT_RETURN_SPEED: float = 750.0
const SCOUT_LEASH_RADIUS: float = preload("res://base_enemy.gd").ACTIVATION_RADIUS - 50.0
const SCOUT_ARRIVE_DIST: float = 6.0
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
		_process_scouting(delta)
		return
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
			if from_elana.length() > SCOUT_LEASH_RADIUS:
				intended = elana.global_position + from_elana.normalized() * SCOUT_LEASH_RADIUS
			global_position = _move_with_collision(global_position, intended, elana.global_position, delta)
	_light.energy = lerp(_light.energy, 1.3, 0.12)

# Shape-based block against terrain/solid obstacles (same layer Elana
# collides with) — checks her actual BodyShape circle (see glint.tscn,
# bigger than her 12x12 sprite) against terrain, not just a single point/
# line, so her real visual extent can't overlap a wall, not only her exact
# center. Used by both scouting (above) and the normal attached-follow
# hover (see _update_position()) — she still moves/tethers toward Elana
# either way, she just can't overlap a wall to get there.
const STUCK_NUDGE_SPEED: float = 60.0  # world px/sec — slow, deliberate escape

# safe_pos is Elana's own current position — always guaranteed clear of
# solid terrain, since SHE has real physics collision and can never be
# inside a wall. Used as the recovery direction when Glint's already stuck
# (see below). First attempt jumped 90% of the way there in one frame,
# which looked sudden/clunky; then tried nudging toward whichever cardinal
# direction was clear instead, which didn't work out either — back to
# nudging toward safe_pos, but as a slow per-frame step instead of a snap.
func _move_with_collision(from: Vector2, to: Vector2, safe_pos: Vector2, delta: float) -> Vector2:
	var space = get_world_2d().direct_space_state
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = _body_shape.shape
	shape_query.collision_mask = 1
	# A shape-cast starting already overlapping terrain doesn't behave
	# usefully for "where's the wall ahead" (standard physics-engine
	# limitation — checks from inside a shape aren't a meaningful "am I
	# about to hit this" query) — so if she's already stuck in a wall (very
	# possible: her hover offset had zero wall-awareness until just now, so
	# plenty of ordinary positions near a wall already overlap one), step
	# toward the guaranteed-safe position at a fixed slow speed.
	shape_query.transform = Transform2D(0.0, from)
	if not space.intersect_shape(shape_query, 1).is_empty():
		var to_safe: Vector2 = safe_pos - from
		var step: float = STUCK_NUDGE_SPEED * delta
		if to_safe.length() <= step:
			return safe_pos
		return from + to_safe.normalized() * step
	if from == to:
		return to
	shape_query.transform = Transform2D(0.0, to)
	if space.intersect_shape(shape_query, 1).is_empty():
		return to
	# Destination overlaps — fall back to a ray to find roughly where the
	# wall starts, then back off by the shape's own radius (not a flat
	# guess) so her actual body stays clear of it, not just her center.
	var ray_query := PhysicsRayQueryParameters2D.create(from, to, 1)
	var result := space.intersect_ray(ray_query)
	if result:
		return result["position"] - (to - from).normalized() * _body_shape.shape.radius
	return from

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
	var target_energy: float
	if _swing_flash_timer > 0.0 or _kill_flash_timer > 0.0:
		target_energy = 1.8
	elif has_weapon and GameData.glint_max_hp > 0.0:
		var ratio = clamp(GameData.glint_hp / GameData.glint_max_hp, 0.0, 1.0)
		target_energy = lerp(0.7, 1.3, ratio)
	else:
		target_energy = 1.0

	# _dim_factor (default 1.0, driven down by apply_light_dim — see below)
	# multiplies both energy and scale, so a dim reads as the light genuinely
	# weakening rather than just a tint change.
	_light.energy = lerp(_light.energy, target_energy * _dim_factor, 0.12)
	# Main light stays white — it's the scene's primary illumination, so
	# tinting it to the herb color would wash the whole visible area instead
	# of just Glint. The herb tint lives on the small HerbGlow light instead.
	_light.color = _light.color.lerp(Color.WHITE, 0.15)
	# Luminosity+ (Elana tree, +25%/lvl) and Herb Integration (Glint tree,
	# flat +30% while a herb is active) add together, not multiply — maxed
	# Luminosity+ (75%) plus Herb Integration is +105% total, not +127.5%.
	var glow_bonus: float = GameData.glint_luminosity_bonus
	if has_herb and GameData.get_glint_skill_level("g_herb_integration") >= 1:
		glow_bonus += 0.3
	var target_scale: float = _base_light_scale * (1.0 + glow_bonus) * _dim_factor
	_light.texture_scale = lerp(_light.texture_scale, target_scale, 0.1)

	var herb_glow_target: float = 1.4 if has_herb else 0.0
	_herb_glow.energy = lerp(_herb_glow.energy, herb_glow_target, 0.12)
	if has_herb:
		_herb_glow.color = _herb_glow.color.lerp(GameData.active_herb.color, 0.2)
