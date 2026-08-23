extends Area2D

# Cobblecroak's Rain of Rocks -- a single falling rock, spawned by
# cobblecroak.gd's _spawn_rock() well above the target area and left to fall
# straight down at a fixed speed. Modeled on hollowfang_spike.gd's
# proximity-hit pattern (distance check against Elana each frame, rather
# than relying on Area2D signal delivery, which can lag a physics frame).
# Real falling projectiles per the user's own explicit choice over a
# simpler tick-damage zone -- more true to "rain," at the cost of this extra
# file.
#
# Despawns instantly on hitting Elana -- no lingering, this is meant to be a
# repeatable spammy hazard, not a single lasting obstacle. Hitting terrain
# plays a brief break animation first (2026-08-23, user explicit: "when
# hitting terrain it breaks") instead of vanishing outright -- see _break().
# Visual is spike.png (2026-08-23, user explicit: "use spike sprite"),
# same texture/Sprite2D-at-native-size convention spike.tscn already uses.

const FALL_SPEED: float = 500.0
const HIT_RADIUS: float = 16.0
# How long the terrain-hit break animation plays before the rock actually
# despawns (2026-08-23, user explicit: "when hitting terrain it breaks") --
# a quick scale-up + fade, distinct from hitting Elana (still an instant
# despawn -- no visual justification for a shatter delay there, it should
# just land the hit and disappear).
const BREAK_DURATION: float = 0.15
@export var damage: int = 10

var _done: bool = false

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("enemy_projectiles")
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if _done:
		return
	position.y += FALL_SPEED * delta
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
		if elana.has_method("take_damage"):
			elana.take_damage(damage, false, self)
		_done = true
		queue_free()

func _on_body_entered(_body: Node) -> void:
	_break()

# Terrain hit specifically -- a quick shatter cue (scale up + fade out) so
# it reads as breaking against the ground instead of just vanishing.
func _break() -> void:
	if _done:
		return
	_done = true
	set_physics_process(false)
	if not is_instance_valid(_sprite):
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(1.6, 1.6), BREAK_DURATION)
	tween.parallel().tween_property(_sprite, "modulate:a", 0.0, BREAK_DURATION)
	await tween.finished
	if is_instance_valid(self):
		queue_free()
