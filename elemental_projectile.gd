extends Area2D

const ELEMENT_COLORS = {
	"fire": Color(1.0, 0.4, 0.1),
	"frost": Color(0.3, 0.7, 1.0),
	"elec": Color(1.0, 0.95, 0.2),
}
const FROST_MAX_DISTANCE = 100.0
const FROST_TICK_INTERVAL = 0.2

var aim_direction: Vector2 = Vector2.RIGHT
var speed: float = 350.0
var lifetime: float = 3.0
var damage: int = 10
var element: String = "fire"
var _distance_traveled: float = 0.0
var _frost_targets: Dictionary = {}  # enemy -> time since last hit
var _frost_sprite: AnimatedSprite2D = null
const FROST_SPIN_SPEED: float = 1.2  # radians/sec, clockwise
var _frost_light: PointLight2D = null
var _frost_pulse_time: float = 0.0
const FROST_GLOW_MIN: float = 0.4
const FROST_GLOW_MAX: float = 1.2
const FROST_PULSE_SPEED: float = 4.0

const FIRE_BALL_FRAMES = [
	"res://projectiles/fire_ball.png",
	"res://projectiles/fire_ball2.png",
	"res://projectiles/fire_ball3.png",
]
const FIRE_TRAIL_TEXTURE = preload("res://projectiles/fire_ball_trail.png")
const TRAIL_SPAWN_INTERVAL: float = 0.05
const TRAIL_FADE_DURATION: float = 0.35
var _trail_spawn_timer: float = 0.0

const ELECTRIC_BOLT_FRAMES = [
	"res://projectiles/electric_bolt1.png",
	"res://projectiles/electric_bolt2.png",
	"res://projectiles/electric_bolt3.png",
]

const FROST_FRAMES = [
	"res://projectiles/frost_0000_Group-1-copy.png",
	"res://projectiles/frost_0001_Group-1.png",
	"res://projectiles/frost_0002_Group-2.png",
]

func _ready() -> void:
	collision_layer = 0
	collision_mask = 5  # 1 = terrain, 4 = enemy Hurtbox layer

	var circle = CircleShape2D.new()
	var shape = CollisionShape2D.new()

	if element == "frost":
		speed = 90.0
		circle.radius = 9.0
		_add_frost_sprite()
	elif element == "fire":
		circle.radius = 6.0
		_add_fire_sprite()
	elif element == "elec":
		circle.radius = 6.0
		_add_elec_sprite()
	else:
		circle.radius = 6.0
		_add_colorrect_visual(Vector2(10, 10), Vector2(-5, -5))

	shape.shape = circle
	add_child(shape)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _add_colorrect_visual(size: Vector2, pos: Vector2) -> void:
	var visual = ColorRect.new()
	visual.size = size
	visual.position = pos
	visual.color = ELEMENT_COLORS.get(element, Color.WHITE)
	add_child(visual)

# Red hot core fading out to bright yellow at the edge — shared by the main
# fireball glow and each trail afterimage's own fading glow.
const FIRE_GLOW_INNER: Color = Color(1.0, 0.15, 0.05)
const FIRE_GLOW_OUTER: Color = Color(1.0, 0.9, 0.2)

# Bright-core/fading-edge gradient texture, same idea as the enemy eye
# glows, but the actual hue is baked into the gradient itself (inner_color
# at the hot core, outer_color as it fades out) instead of a single flat
# tint, so a glow can shift color from center to edge. width/height control
# how wide vs. how narrow/elongated it reads.
func _build_glow_texture(inner_color: Color, outer_color: Color, tex_width: int, tex_height: int) -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.35, 1])
	gradient.colors = PackedColorArray([
		Color(inner_color.r * 3, inner_color.g * 3, inner_color.b * 3, 1),
		Color(outer_color.r, outer_color.g, outer_color.b, 0.6),
		Color(outer_color.r, outer_color.g, outer_color.b, 0),
	])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	tex.width = tex_width
	tex.height = tex_height
	return tex

# elongated stretches/narrows the texture into a tight line instead of a
# circle (rotated with the caller) — used for the electric bolt.
func _add_glow(inner_color: Color, outer_color: Color, energy: float, glow_scale: float,
		elongated: bool = false, angle: float = 0.0, tex_width: int = 256, tex_height: int = 48) -> PointLight2D:
	var tex = _build_glow_texture(inner_color, outer_color,
		tex_width if elongated else 128, tex_height if elongated else 128)
	var light = PointLight2D.new()
	light.texture = tex
	light.color = Color.WHITE
	light.energy = energy
	light.texture_scale = glow_scale
	light.rotation = angle
	add_child(light)
	return light

func _add_fire_sprite() -> void:
	var trail = Sprite2D.new()
	trail.texture = FIRE_TRAIL_TEXTURE
	trail.rotation = aim_direction.angle()
	trail.position = -aim_direction * 12.0
	trail.z_index = -1
	add_child(trail)

	var frames = SpriteFrames.new()
	frames.add_animation("spin")
	frames.set_animation_loop("spin", true)
	frames.set_animation_speed("spin", 8.0)
	for path in FIRE_BALL_FRAMES:
		frames.add_frame("spin", load(path))
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.rotation = aim_direction.angle()
	sprite.play("spin")
	add_child(sprite)

	_add_glow(FIRE_GLOW_INNER, FIRE_GLOW_OUTER, 1.3, 0.5)

func _add_elec_sprite() -> void:
	var frames = SpriteFrames.new()
	frames.add_animation("spark")
	frames.set_animation_loop("spark", true)
	frames.set_animation_speed("spark", 12.0)
	for path in ELECTRIC_BOLT_FRAMES:
		frames.add_frame("spark", load(path))
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.rotation = aim_direction.angle()
	sprite.play("spark")
	add_child(sprite)

	# Linear, not radial — stretched to follow the bolt's own direction
	# instead of glowing as a circular blob around it. Much higher energy,
	# and a shorter texture height keeps it a tight line instead of spreading
	# into a wide oval.
	_add_glow(Color(1.0, 1.0, 0.6), Color(1.0, 0.9, 0.2), 4.5, 0.9, true, aim_direction.angle(), 220, 40)

func _add_frost_sprite() -> void:
	var frames = SpriteFrames.new()
	frames.add_animation("shimmer")
	frames.set_animation_loop("shimmer", true)
	frames.set_animation_speed("shimmer", 6.0)
	for path in FROST_FRAMES:
		frames.add_frame("shimmer", load(path))
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.play("shimmer")
	add_child(sprite)
	_frost_sprite = sprite

	# Bigger than fire's — wider texture_scale. Pulses between min/max energy
	# in _physics_process() instead of sitting at one flat brightness.
	_frost_light = _add_glow(Color(0.5, 0.85, 1.0), Color(0.5, 0.85, 1.0), FROST_GLOW_MIN, 0.6)

func _on_body_entered(_body) -> void:
	_spawn_impact_glow()
	queue_free()

func _on_area_entered(area) -> void:
	if area.name != "Hurtbox":
		return
	var enemy = area.get_parent()
	var hit_dir: int = 1 if aim_direction.x >= 0.0 else -1
	if element == "frost":
		if not _frost_targets.has(enemy):
			_frost_targets[enemy] = 0.0
			enemy.on_elemental_hit(element, hit_dir, damage)
	else:
		enemy.on_elemental_hit(element, hit_dir, damage)
		_spawn_impact_glow()
		queue_free()

const IMPACT_GLOW_DURATION: float = 0.25

# A quick radial burst of light at the impact point — expands slightly while
# fading out, then frees itself. Fire only for now (frost hits repeatedly
# via its own DoT ticks, which would make a burst-per-tick spammy/wrong).
func _spawn_impact_glow() -> void:
	if element != "fire":
		return
	var light = PointLight2D.new()
	light.texture = _build_glow_texture(FIRE_GLOW_INNER, FIRE_GLOW_OUTER, 128, 128)
	light.color = Color.WHITE
	light.energy = 2.0
	light.texture_scale = 0.6
	light.global_position = global_position
	get_parent().add_child(light)
	var tween = light.create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "energy", 0.0, IMPACT_GLOW_DURATION)
	tween.tween_property(light, "texture_scale", 1.1, IMPACT_GLOW_DURATION)
	tween.set_parallel(false)
	tween.tween_callback(light.queue_free)

func _spawn_trail_afterimage() -> void:
	var ghost = Sprite2D.new()
	ghost.texture = FIRE_TRAIL_TEXTURE
	ghost.rotation = aim_direction.angle()
	ghost.global_position = global_position
	ghost.z_index = -1
	get_parent().add_child(ghost)

	# A small glow riding along with each afterimage, fading out in step with
	# the sprite itself — the trail as a whole reads as a fading line of glow
	# instead of just the fireball's own light leaving nothing behind it.
	var light = PointLight2D.new()
	light.texture = _build_glow_texture(FIRE_GLOW_INNER, FIRE_GLOW_OUTER, 128, 128)
	light.color = Color.WHITE
	light.energy = 0.6
	light.texture_scale = 0.3
	ghost.add_child(light)

	var tween = ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, TRAIL_FADE_DURATION)
	tween.tween_property(light, "energy", 0.0, TRAIL_FADE_DURATION)
	tween.set_parallel(false)
	tween.tween_callback(ghost.queue_free)

func _physics_process(delta) -> void:
	var move = aim_direction * speed * delta
	position += move

	if element == "fire":
		_trail_spawn_timer -= delta
		if _trail_spawn_timer <= 0.0:
			_trail_spawn_timer = TRAIL_SPAWN_INTERVAL
			_spawn_trail_afterimage()

	if element == "frost":
		if _frost_sprite:
			_frost_sprite.rotation += FROST_SPIN_SPEED * delta
		if _frost_light:
			_frost_pulse_time += delta
			var t = 0.5 + 0.5 * sin(_frost_pulse_time * FROST_PULSE_SPEED)
			_frost_light.energy = lerp(FROST_GLOW_MIN, FROST_GLOW_MAX, t)
		_distance_traveled += speed * delta
		if _distance_traveled >= FROST_MAX_DISTANCE:
			queue_free()
			return
		var hit_dir: int = 1 if aim_direction.x >= 0.0 else -1
		for enemy in _frost_targets.keys():
			if not is_instance_valid(enemy):
				_frost_targets.erase(enemy)
				continue
			_frost_targets[enemy] += delta
			if _frost_targets[enemy] >= FROST_TICK_INTERVAL:
				_frost_targets[enemy] -= FROST_TICK_INTERVAL
				enemy.on_elemental_hit(element, hit_dir, damage)
	else:
		lifetime -= delta
		if lifetime <= 0:
			queue_free()
