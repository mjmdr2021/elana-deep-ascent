extends Control

# Simple procedural loading spinner — a rotating 3/4 arc, matching the "build
# small VFX/UI procedurally instead of importing texture assets" convention
# used elsewhere (GameData.make_stun_indicator(), chain_projectile.gd's
# glow texture). Used by loading_screen.gd.

const RADIUS: float = 22.0
const THICKNESS: float = 5.0
const SPIN_SPEED: float = 4.5  # radians/sec
const ARC_LENGTH: float = TAU * 0.75  # 3/4 circle — the gap is what reads as "spinning"
const SPINNER_COLOR: Color = Color(0.92, 0.87, 0.72)  # matches title_screen.gd's title text color

var _angle: float = 0.0

func _process(delta: float) -> void:
	_angle = wrapf(_angle + SPIN_SPEED * delta, 0.0, TAU)
	queue_redraw()

func _draw() -> void:
	draw_arc(size / 2.0, RADIUS, _angle, _angle + ARC_LENGTH, 32, SPINNER_COLOR, THICKNESS, true)
