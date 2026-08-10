extends "res://enemy.gd"

# Hangs dormant on the ceiling (no gravity, no movement, no aggro-flip) until
# Elana walks into a tall, narrow detection strip hanging below it — reshaped
# from the normal AggroZone in _ready() instead of a side-facing box. Once
# triggered it drops straight down and becomes a normal chasing melee enemy
# after landing (one-time ambush, AggroZone restored to its default shape).
enum DropState { DORMANT, DROPPING, ACTIVE }

@export var detect_width: float = 20.0
@export var detect_height: float = 200.0
@export var detect_offset_y: float = 100.0
const NORMAL_AGGRO_SIZE := Vector2(100, 32)
const LANDING_TRAUMA := 0.3

var _state: DropState = DropState.DORMANT

func _ready() -> void:
	super._ready()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(detect_width, detect_height)
	$AggroZone/CollisionShape2D.shape = shape
	$AggroZone/CollisionShape2D.position = Vector2.ZERO
	$AggroZone.position = Vector2(0, detect_offset_y)
	# Stays visible while dormant on purpose — it's meant to be spottable if
	# you look up, not a blind ambush. Only its own CollisionShape2D is
	# disabled (see _start_drop()), so it can sit embedded in ceiling art
	# without move_and_slide() depenetrating it back out (that push was the
	# earlier "drifts down a bit" bug).
	$CollisionShape2D.disabled = true

# Dormant normally just hangs in place (velocity frozen, no gravity). But a
# knockback (Chain Claw pull, etc.) sets velocity directly one frame before
# this runs — base_enemy.gd's _physics_process consumes _pending_knockback
# into `velocity` before calling _apply_gravity(). Detecting that here and
# treating it as an early drop trigger (enabling collision, same as walking
# underneath would) lets it actually get pulled/fall like a normal enemy
# instead of freezing mid-air with nothing to stop it.
func _apply_gravity(delta: float) -> void:
	if _state == DropState.DORMANT:
		if velocity != Vector2.ZERO:
			_start_drop()
		else:
			return
	super._apply_gravity(delta)

# Skip the base class's per-frame AggroZone/eye-glow repositioning while
# dormant — it would otherwise fight the custom hang-below shape set above.
func _update_zones() -> void:
	if _state == DropState.DORMANT:
		return
	super._update_zones()

func _move(delta: float) -> void:
	match _state:
		DropState.DORMANT:
			velocity.x = 0
			if target:
				_start_drop()
		DropState.DROPPING:
			if is_on_floor():
				_state = DropState.ACTIVE
				_restore_normal_aggro_zone()
				if target and target.has_method("add_camera_trauma"):
					target.add_camera_trauma(LANDING_TRAUMA)
		DropState.ACTIVE:
			super._move(delta)

func _start_drop() -> void:
	_state = DropState.DROPPING
	$CollisionShape2D.disabled = false

func _restore_normal_aggro_zone() -> void:
	var shape := RectangleShape2D.new()
	shape.size = NORMAL_AGGRO_SIZE
	$AggroZone/CollisionShape2D.shape = shape
	$AggroZone/CollisionShape2D.position = Vector2(0, -8)
