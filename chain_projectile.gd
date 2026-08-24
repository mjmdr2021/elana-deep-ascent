extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 500.0
var max_range: float = 220.0
var damage: int = 0
var source: Node = null
var _traveled: float = 0.0
var _hit: bool = false
var _pull_target: Node = null
var _pulling: bool = false
var _pull_timer: float = 0.0
var _retracting: bool = false
var _retract_timer: float = 0.0

const PULL_SPEED: float = 600.0
const PULL_STOP_DIST: float = 28.0
const PULL_MAX_TIME: float = 0.8
const RETRACT_TIMEOUT: float = 0.9  # covers the longest possible wall-grapple pull (max_range/speed) + margin

const CLAW_TEXTURE = preload("res://projectiles/claw_projectile.png")
const CHAIN_LINK_TEXTURE = preload("res://projectiles/claw_chain.png")
const CHAIN_LINK_SPACING: float = 24.0  # matches claw_chain.png's native width — no stretching
const PASS_THROUGH_DIST: float = 14.0
const SEGMENT_FADE_DURATION: float = 0.15

var _chain_segments: Array = []  # Sprite2D nodes, oldest (closest to source) first
var _dist_since_last_link: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = (1 << 2)  # layer 3 (hittable/hurtboxes)
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)

	var head = Sprite2D.new()
	head.name = "Head"
	head.texture = CLAW_TEXTURE
	head.rotation = direction.angle()
	add_child(head)

	var light = PointLight2D.new()
	light.texture = _make_glow_texture()
	light.color = Color(1.0, 0.6, 0.2)
	light.energy = 1.4
	light.texture_scale = 1.2
	add_child(light)

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	add_child(shape)

# Same radial white-to-transparent glow shape Glint's own light uses —
# built here since this projectile has no backing .tscn to hold the resource.
func _make_glow_texture() -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	return tex

# Lays chain-link sprites at native scale along the throw path (same
# "tile, don't stretch" approach as the elec bolt), left behind fully
# opaque instead of fading on a timer like the fire trail — they only
# fade once whoever's traveling back along the chain actually reaches them.
func _maybe_spawn_chain_segment() -> void:
	_dist_since_last_link += speed * get_process_delta_time()
	if _dist_since_last_link < CHAIN_LINK_SPACING:
		return
	_dist_since_last_link -= CHAIN_LINK_SPACING
	var link = Sprite2D.new()
	link.texture = CHAIN_LINK_TEXTURE
	link.rotation = direction.angle()
	link.z_index = -1
	# add_child() first — see the matching comment in elana.gd::_heavy_chain().
	# Setting global_position before parenting double-counts the level root's
	# offset, which is exactly what made the chain links drift from the claw.
	get_parent().add_child(link)
	link.global_position = global_position
	_chain_segments.append(link)

# Fades and drops any segment the traveler (Elana during a wall-grapple, or
# the pulled enemy during an enemy-grapple) has caught up to.
func _fade_passed_segments(traveler_pos: Vector2) -> void:
	for i in range(_chain_segments.size() - 1, -1, -1):
		var link = _chain_segments[i]
		if not is_instance_valid(link):
			_chain_segments.remove_at(i)
			continue
		if link.global_position.distance_to(traveler_pos) <= PASS_THROUGH_DIST:
			_chain_segments.remove_at(i)
			var tween = link.create_tween()
			tween.tween_property(link, "modulate:a", 0.0, SEGMENT_FADE_DURATION)
			tween.tween_callback(link.queue_free)

func _clear_remaining_segments() -> void:
	for link in _chain_segments:
		if is_instance_valid(link):
			var tween = link.create_tween()
			tween.tween_property(link, "modulate:a", 0.0, SEGMENT_FADE_DURATION)
			tween.tween_callback(link.queue_free)
	_chain_segments.clear()

func _process(delta: float) -> void:
	if _retracting:
		_retract_timer += delta
		if is_instance_valid(source):
			_fade_passed_segments(source.global_position)
		if _chain_segments.is_empty() or _retract_timer >= RETRACT_TIMEOUT or not is_instance_valid(source):
			_clear_remaining_segments()
			queue_free()
		return

	if _pulling:
		_pull_timer += delta
		if not is_instance_valid(_pull_target) or not is_instance_valid(source) or _pull_timer >= PULL_MAX_TIME:
			_end_pull()
			return
		global_position = _pull_target.global_position
		_fade_passed_segments(_pull_target.global_position)
		var to_source = source.global_position - _pull_target.global_position
		if to_source.length() <= PULL_STOP_DIST:
			_end_pull()
			return
		# is_stunned/_pending_knockback are base_enemy.gd fields — not every
		# "enemies"-group member declares them. blocks_chain_pull() (checked
		# before _pulling is ever set true, in _on_area_entered()) is meant
		# to keep anything without them from reaching this point at all, but
		# guarding here too means a future enemy that forgets to implement
		# it fails safe instead of erroring.
		if "is_stunned" in _pull_target:
			_pull_target.is_stunned = true
			_pull_target._pending_knockback = to_source.normalized() * PULL_SPEED
		return

	if _hit:
		return
	var prev_pos = global_position
	global_position += direction * speed * delta
	_traveled += speed * delta
	_maybe_spawn_chain_segment()
	if not monitoring and _traveled >= 12.0:
		monitoring = true
	if _traveled >= max_range:
		_clear_remaining_segments()
		queue_free()
		return
	if monitoring:
		var space = get_world_2d().direct_space_state
		var query = PhysicsRayQueryParameters2D.create(prev_pos, global_position, 1)
		var result = space.intersect_ray(query)
		if result:
			_hit = true
			if is_instance_valid(source):
				source._grapple_direction = direction
				source._grapple_timer = _compute_grapple_timer(result["position"])
			_retracting = true
			$Head.visible = false

# Flat timers cap total pull distance at speed*time regardless of how far
# the hook actually landed — compute duration from the real distance instead
# (plus a small buffer) so the pull always reaches (and passes through) it.
const GRAPPLE_TIME_BUFFER: float = 0.1

func _compute_grapple_timer(hook_pos: Vector2) -> float:
	var dist = source.global_position.distance_to(hook_pos)
	return dist / source.GRAPPLE_PULL_SPEED + GRAPPLE_TIME_BUFFER

func _end_pull() -> void:
	if is_instance_valid(_pull_target):
		_pull_target.velocity.x = 0.0
		if "is_stunned" in _pull_target:
			_pull_target.is_stunned = false
	_clear_remaining_segments()
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	if _hit or area.name != "Hurtbox":
		return
	_hit = true
	var target = area.get_parent()
	if is_instance_valid(target) and is_instance_valid(source):
		if target.is_in_group("enemies"):
			var pull_dir = int(sign(source.global_position.x - target.global_position.x))
			# Generic hook — lets a target (Shield-bearer) fully replace the
			# normal damage path, e.g. to make the chain a pure utility hit
			# with zero damage instead of a weapon hit.
			if target.has_method("on_chain_hit"):
				target.on_chain_hit()
			else:
				target.on_hit(pull_dir, damage, false, source)
			GameData.glint_take_hit(GameData.get_weapon_hit_cost(true))
			GameData.check_weapon_depletion()
			# Generic hook — the hit above still lands (Shield-bearer's own
			# modify_incoming_damage() already reduces it if blocked), but a
			# target can refuse to actually be grappled/pulled in. Reversed
			# instead of just cancelling (2026-08-24, user explicit: "cant
			# pull bat. elana will be pulled to it" -- confirmed as the
			# correct general behavior, not bat-specific): reuses the exact
			# same grapple-to-wall mechanic below for when the hook hits
			# terrain instead of an enemy, just anchored at the boss's own
			# Hurtbox position instead of a wall.
			if target.has_method("blocks_chain_pull") and target.blocks_chain_pull():
				source._grapple_direction = direction
				source._grapple_timer = _compute_grapple_timer(global_position)
				_retracting = true
				$Head.visible = false
				return
			_pull_target = target
			_pulling = true
			# Can't set monitoring directly here — this IS the area_entered
			# callback, and Area2D is locked against monitoring changes for
			# the duration of its own in/out signal dispatch. Deferred call
			# applies it right after, once the engine's unlocked again.
			set_deferred("monitoring", false)
		else:
			source._grapple_direction = direction
			source._grapple_timer = _compute_grapple_timer(global_position)
			_retracting = true
			$Head.visible = false
