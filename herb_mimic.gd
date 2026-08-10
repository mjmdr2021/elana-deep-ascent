extends "res://enemy.gd"

# Disguised as a stationary herb pickup — visible (unlike Burrower), but
# unhittable and inert until Elana gets close enough that she'd normally be
# about to interact with it. Then it lunges: a fast, locked-direction burst
# (doesn't home mid-lunge) dealing one surprise hit if it connects, then
# settles into a completely normal enemy.gd chaser — same post-reveal
# pattern Burrower uses. No herb drop on death.
enum MimicState { DISGUISED, LUNGING, ACTIVE }

@export var trigger_range: float = 20.0
@export var lunge_speed: float = 260.0
@export var lunge_duration: float = 0.25
@export var lunge_hit_range: float = 16.0
@export var lunge_damage: int = 12
const DISGUISED_COLOR: Color = Color(0.4, 0.8, 0.35, 1.0)
const REVEALED_TINT: Color = Color(1.2, 0.4, 0.5, 1.0)
const VISUAL_SIZE: float = 12.0
const NORMAL_AGGRO_SIZE: Vector2 = Vector2(100, 32)
const NORMAL_AGGRO_POS: Vector2 = Vector2(0, -8)

var _state: MimicState = MimicState.DISGUISED
var _lunge_timer: float = 0.0
var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_hit_done: bool = false

func _ready() -> void:
	# ColorRect's color must be set BEFORE super._ready() — base_enemy.gd
	# captures it as original_color for the hit-flash system at that point.
	$AnimatedSprite2D.visible = false
	$ColorRect.color = DISGUISED_COLOR
	$ColorRect.offset_left = -VISUAL_SIZE / 2.0
	$ColorRect.offset_top = -VISUAL_SIZE / 2.0
	$ColorRect.offset_right = VISUAL_SIZE / 2.0
	$ColorRect.offset_bottom = VISUAL_SIZE / 2.0
	$ColorRect.visible = true
	super._ready()
	$Hurtbox.set_deferred("monitorable", false)
	if $AggroZone.body_entered.is_connected(_on_aggro_zone_body_entered):
		$AggroZone.body_entered.disconnect(_on_aggro_zone_body_entered)
	if $AggroZone.body_exited.is_connected(_on_aggro_zone_body_exited):
		$AggroZone.body_exited.disconnect(_on_aggro_zone_body_exited)
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	# Reshape AggroZone into a small centered proximity trigger — the "close
	# enough you'd be about to press E on it" range — instead of its normal
	# side-facing aggro box.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(trigger_range * 2.0, trigger_range * 2.0)
	$AggroZone/CollisionShape2D.shape = shape
	$AggroZone/CollisionShape2D.position = Vector2.ZERO
	$AggroZone.position = Vector2.ZERO
	$AggroZone.body_entered.connect(_on_trigger_entered)

func _on_trigger_entered(body: Node) -> void:
	if _state != MimicState.DISGUISED or not body.is_in_group("player"):
		return
	_state = MimicState.LUNGING
	_lunge_timer = lunge_duration
	_lunge_hit_done = false
	_lunge_dir = (body.global_position - global_position).normalized()
	direction = 1 if _lunge_dir.x >= 0.0 else -1
	modulate = REVEALED_TINT
	if $AggroZone.body_entered.is_connected(_on_trigger_entered):
		$AggroZone.body_entered.disconnect(_on_trigger_entered)

func _move(delta: float) -> void:
	match _state:
		MimicState.DISGUISED:
			velocity = Vector2.ZERO
		MimicState.LUNGING:
			velocity = _lunge_dir * lunge_speed
			_check_lunge_hit()
			_lunge_timer -= delta
			if _lunge_timer <= 0.0:
				_finish_lunge()
		MimicState.ACTIVE:
			super._move(delta)

func _check_lunge_hit() -> void:
	if _lunge_hit_done:
		return
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= lunge_hit_range:
		_lunge_hit_done = true
		elana.take_damage(lunge_damage, false, self)
		if elana.has_method("add_camera_trauma"):
			elana.add_camera_trauma(0.3)

func _finish_lunge() -> void:
	_state = MimicState.ACTIVE
	$Hurtbox.set_deferred("monitorable", true)
	$AggroZone.body_entered.connect(_on_aggro_zone_body_entered)
	$AggroZone.body_exited.connect(_on_aggro_zone_body_exited)
	$AttackZone.body_entered.connect(_on_attack_zone_body_entered)
	$AttackZone.body_exited.connect(_on_attack_zone_body_exited)
	var aggro_shape := RectangleShape2D.new()
	aggro_shape.size = NORMAL_AGGRO_SIZE
	$AggroZone/CollisionShape2D.shape = aggro_shape
	$AggroZone/CollisionShape2D.position = NORMAL_AGGRO_POS
	$AggroZone.position = Vector2(aggro_zone_offset * direction, 0)
	var elana = get_tree().get_first_node_in_group("player")
	if elana:
		target = elana
		deaggro_timer = 0.0
