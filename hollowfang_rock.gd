extends Area2D

# Cave Disruptor's falling rock hazard — spawned above the arena, falls
# straight down ignoring all terrain collision (the ceiling/floating
# platforms it's meant to pass through), damages on contact WHILE falling
# (a narrower graze radius, doesn't stop it), and explodes in a wider
# radius once it reaches target_y (the placeholder "arena floor" —
# CaveDisruptorArenaZone's bottom edge, until a real arena/floor exists).
# Unlike hollowfang_spit.gd/hollowfang_spike.gd, this isn't aimed at anyone
# and isn't destructible — it's a pure environmental hazard, not a combat
# target.

const MIDAIR_HIT_RADIUS: float = 16.0

@export var target_y: float = 0.0
@export var fall_speed: float = 500.0
@export var damage: int = 15
@export var explosion_radius: float = 40.0

var _done: bool = false
# Everyone already damaged by the mid-air graze check, so a body lingering
# in range doesn't get hit every frame — same "hits once, tracked in a
# list" shape as hollowfang.gd's _tail_hit_bodies. Doesn't stop the rock
# from continuing to fall (and potentially still catching them again in
# the explosion at the floor) once it's grazed someone.
var _midair_hit_bodies: Array = []

func _ready() -> void:
	add_to_group("hazards")  # Ant Queen's death reward halves damage from this group
	collision_layer = 0
	collision_mask = 0  # ignores all terrain/floating platforms on the way down

func _physics_process(delta: float) -> void:
	if _done:
		return
	position.y += fall_speed * delta
	_check_midair_hit()
	if global_position.y >= target_y:
		_explode()

func _check_midair_hit() -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana and elana not in _midair_hit_bodies and elana.global_position.distance_to(global_position) <= MIDAIR_HIT_RADIUS:
		_midair_hit_bodies.append(elana)
		elana.take_damage(damage, false, self)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy not in _midair_hit_bodies and enemy.has_method("on_hit") and enemy.global_position.distance_to(global_position) <= MIDAIR_HIT_RADIUS:
			_midair_hit_bodies.append(enemy)
			enemy.on_hit(0, damage, false)

func _explode() -> void:
	if _done:
		return
	_done = true
	_show_explosion_visual()
	var elana = get_tree().get_first_node_in_group("player")
	if elana and elana.global_position.distance_to(global_position) <= explosion_radius:
		elana.take_damage(damage, false, self)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("on_hit") and enemy.global_position.distance_to(global_position) <= explosion_radius:
			enemy.on_hit(0, damage, false)
	queue_free()

# Semi-opaque circle at the explosion point, fading out — same technique
# elana.gd's _show_plunge_aoe() uses (a Polygon2D circle, tween the alpha to
# 0, free on finish). A fresh node rather than drawing on the rock itself,
# since the rock queue_free()s the same frame this is spawned.
func _show_explosion_visual() -> void:
	var poly = Polygon2D.new()
	poly.color = Color(0.95, 0.45, 0.1, 0.55)
	poly.z_index = 3
	var pts := PackedVector2Array()
	for i in 24:
		var a = (float(i) / 24.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * explosion_radius)
	poly.polygon = pts
	# Local position matched to the shared future parent (get_parent(), same
	# as every other runtime-spawned node this session) — setting
	# global_position before add_child() actually runs is unreliable.
	poly.position = get_parent().to_local(global_position)
	get_parent().call_deferred("add_child", poly)
	var tween = get_tree().create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.4)
	tween.tween_callback(poly.queue_free)
