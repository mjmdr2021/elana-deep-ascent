extends Area2D

# Ground Slam's individual earth mound — reuses ore_node.tscn's own sprite
# (ore-node.png already reads as a small earth/rock mound). Rises from a
# sunken resting position up to full height, holds briefly, then recedes
# back down and frees itself. Animated via position, never scale — the
# texture stays at native pixel size throughout, per the project's "never
# scale sprites" rule; the "rising" motion comes from moving it, not
# stretching it.
#
# Hit detection is a real scene-authored CollisionShape2D (see this file's
# .tscn) checked via get_overlapping_bodies(), not a manual distance check —
# an earlier version used collision_layer/mask = 0 with pure script-side
# distance math instead, which is exactly the "never build collision purely
# in script" rule this project otherwise follows everywhere else.
#
# elemental_golem.gd spawns 5 of these in an overlapping-ripple sequence
# (each one starts a beat after the previous, not after it finishes)
# stepping outward from the golem in whichever direction she's facing, for
# Ground Slam's wave effect.

const RISE_TIME: float = 0.15
const HOLD_TIME: float = 0.2
const RECEDE_TIME: float = 0.15
const SUNKEN_OFFSET: float = 20.0  # world px below resting height it starts/ends at

@export var damage: int = 15
@export var knockup: float = -220.0
@export var knockback_x: float = 80.0
@export var away_direction: int = 1  # which way to push Elana horizontally on hit
# Per-instance hitbox override -- defaults match the scene's own baked-in
# CircleShape2D exactly, so elemental_golem.gd's Ground Slam (which never
# sets these) is completely unaffected. Graniteus's Mountain Judgement sets
# both bigger/lower on the mounds it spawns (2026-08-24, user: "make
# collision of wave a bit lower and bigger").
@export var hit_radius: float = 18.0
@export var hit_vertical_offset: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
var _rest_y: float
var _hit_player: bool = false

func _ready() -> void:
	_rest_y = _sprite.position.y
	_sprite.position.y = _rest_y + SUNKEN_OFFSET
	# Duplicated, not mutated in place -- the CircleShape2D sub-resource is
	# shared across every instance of this packed scene by default, so
	# resizing it directly would silently resize every other currently-alive
	# mound too (including Ground Slam's, spawned from the same scene).
	var shape: CircleShape2D = _collision_shape.shape.duplicate()
	shape.radius = hit_radius
	_collision_shape.shape = shape
	_collision_shape.position.y = hit_vertical_offset
	_animate()

func _animate() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "position:y", _rest_y, RISE_TIME)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(_sprite, "position:y", _rest_y + SUNKEN_OFFSET, RECEDE_TIME)
	tween.tween_callback(queue_free)

# Only actually dangerous once mostly risen (roughly matches the visual) —
# checked every frame rather than only once, since the tween above is what
# drives whether it's "up" at any given moment.
func _physics_process(_delta: float) -> void:
	if _hit_player:
		return
	if _sprite.position.y > _rest_y + 4.0:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_hit_player = true
			body.take_damage(damage, false, self)
			body.apply_stun(0.5)
			body.apply_knockback(Vector2(away_direction * knockback_x, knockup), 0.4)
			return
