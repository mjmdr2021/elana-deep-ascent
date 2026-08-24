extends Node2D

# Purely cosmetic "echo" ring for Shriek Wave (2026-08-24, user: "do a
# visual. like a circle going out like an echo.") -- a real Node2D using
# _draw() to render an expanding, fading ring outline. No texture/sprite
# involved, so the "never scale sprites" rule doesn't apply -- radius is a
# genuine vector-draw parameter, not a scaled texture.

@export var max_radius: float = 250.0
@export var duration: float = 1.0
@export var ring_color: Color = Color(0.8, 0.3, 0.9, 0.8)
@export var ring_width: float = 3.0

var _radius: float = 0.0
var _alpha: float = 1.0

func _ready() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "_radius", max_radius, duration)
	tween.tween_property(self, "_alpha", 0.0, duration)
	tween.chain().tween_callback(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var c: Color = ring_color
	c.a = ring_color.a * _alpha
	draw_arc(Vector2.ZERO, _radius, 0, TAU, 48, c, ring_width)
