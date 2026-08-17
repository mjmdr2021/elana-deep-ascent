extends Area2D

# A lingering ground hazard Ice Slug drops behind itself as it moves — a
# slick/icy patch that slows Elana on contact instead of burning her,
# otherwise identical shape to fire_trail_patch.gd.
@export var lifetime: float = 4.0
@export var slow_factor: float = 0.55
@export var slow_duration: float = 1.5
const RADIUS: float = 10.0
const COLOR: Color = Color(0.4, 0.75, 1.0, 0.45)

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player layer
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	var visual := Polygon2D.new()
	visual.color = COLOR
	var pts := PackedVector2Array()
	for i in 12:
		var a = (float(i) / 12.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * RADIUS)
	visual.polygon = pts
	visual.z_index = -1
	add_child(visual)
	body_entered.connect(_on_entered)
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_callback(queue_free)

func _on_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("apply_slow"):
		body.apply_slow(slow_factor, slow_duration, "frost")
