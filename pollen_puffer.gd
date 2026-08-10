extends "res://enemy.gd"

# Rooted (like Snap Vine/Spitting Bloom — no chase, no melee attack) with a
# constantly-present 96px cloud around it, not a periodic puff. Standing in
# the cloud ramps up slow, jump weight (lower jumps — apply_jump_weight()
# multiplies into every jump velocity alongside GameData.jump_mult), and
# Glint's light-dim, all the longer Elana stays — reapplied every physics
# frame with a short duration, so they decay out naturally within ~0.3s of
# leaving instead of needing explicit removal code (same trick apply_slow
# already used elsewhere). Poison stays flat and negligible on purpose —
# the escalating slow/weight is what makes lingering actually costly
# (harder to leave = more ticks eaten), not the poison's own tick value.
# Killing it frees the cloud's Area2D/visual immediately (they're children
# of this node), which also lets any already-applied effects decay out on
# their own short timers.
@export var cloud_radius: float = 96.0
@export var slow_min_factor: float = 0.85
@export var slow_max_factor: float = 0.35
@export var slow_ramp_time: float = 3.0
@export var dim_min_factor: float = 1.0
@export var dim_max_factor: float = 0.35
@export var poison_tick_damage: int = 1
const VISUAL_SIZE: float = 18.0
const VISUAL_COLOR: Color = Color(0.55, 0.3, 0.7, 1.0)
const CLOUD_COLOR: Color = Color(0.55, 0.3, 0.7, 0.22)

var _time_in_cloud: float = 0.0
var _elana_inside: bool = false

func _ready() -> void:
	# ColorRect's color must be set BEFORE super._ready() — base_enemy.gd
	# captures it as original_color for the hit-flash system at that point.
	$AnimatedSprite2D.visible = false
	$ColorRect.color = VISUAL_COLOR
	$ColorRect.offset_left = -VISUAL_SIZE / 2.0
	$ColorRect.offset_top = -VISUAL_SIZE / 2.0
	$ColorRect.offset_right = VISUAL_SIZE / 2.0
	$ColorRect.offset_bottom = VISUAL_SIZE / 2.0
	$ColorRect.visible = true
	super._ready()
	if $AggroZone.body_entered.is_connected(_on_aggro_zone_body_entered):
		$AggroZone.body_entered.disconnect(_on_aggro_zone_body_entered)
	if $AggroZone.body_exited.is_connected(_on_aggro_zone_body_exited):
		$AggroZone.body_exited.disconnect(_on_aggro_zone_body_exited)
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	_build_cloud()

func _build_cloud() -> void:
	var visual := Polygon2D.new()
	visual.color = CLOUD_COLOR
	var pts := PackedVector2Array()
	for i in 24:
		var a = (float(i) / 24.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * cloud_radius)
	visual.polygon = pts
	visual.z_index = -1
	add_child(visual)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2  # player layer, same as AggroZone/AttackZone
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = cloud_radius
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(_on_cloud_entered)
	area.body_exited.connect(_on_cloud_exited)
	add_child(area)

func _on_cloud_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_inside = true
		_time_in_cloud = 0.0

func _on_cloud_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_inside = false

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	if not _elana_inside:
		return
	_time_in_cloud += delta
	var t = clamp(_time_in_cloud / slow_ramp_time, 0.0, 1.0)
	var elana = get_tree().get_first_node_in_group("player")
	if not elana:
		return
	elana.apply_slow(lerp(slow_min_factor, slow_max_factor, t), 0.3)
	elana.apply_jump_weight(lerp(slow_min_factor, slow_max_factor, t), 0.3)
	elana.apply_player_poison(poison_tick_damage, 2)
	var glint = elana.get_node_or_null("Glint")
	if glint and glint.has_method("apply_light_dim"):
		glint.apply_light_dim(lerp(dim_min_factor, dim_max_factor, t), 0.3)
