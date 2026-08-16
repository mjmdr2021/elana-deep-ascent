extends "res://flying_enemy.gd"

# Smaller, faster flying_enemy.gd variant (scale set on the .tscn) with a
# custom dive attack replacing the generic windup/AttackZone cycle entirely
# (disconnected in _ready(), same trick other custom-attack enemies this
# session use): once in range, it backs AWAY from the target for
# windup_time (telegraph — a bat pulling back before diving), then darts
# forward through where the target was at the moment the dash committed
# (locked direction, doesn't home mid-dash, same "commit" flavor as
# Charger's dash), dealing light damage on a landed hit, then recovers.
#
# When idle (no target), alternates between normal flying_enemy.gd
# patrol/hover and clinging motionless to the nearest ceiling above it
# (found via a short upward raycast) — picked randomly every few seconds.
enum AttackState { NONE, WINDUP, DASHING, RECOVER }
enum IdleMode { PATROL, CEILING }

@export var attack_range: float = 55.0
@export var windup_time: float = 0.4
@export var reverse_speed: float = 50.0
@export var dash_speed: float = 220.0
@export var dash_duration: float = 0.3
@export var recover_time: float = 0.5
@export var attack_cooldown_bat: float = 1.2
@export var hit_check_radius: float = 16.0
const WINDUP_TINT: Color = Color(1.5, 0.6, 1.5, 1.0)
const CEILING_PROBE_RANGE: float = 200.0
const CEILING_REST_OFFSET: float = 8.0
const CEILING_MOVE_SPEED: float = 30.0

var _attack_state: AttackState = AttackState.NONE
var _state_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _bat_cooldown: float = 0.0
var _hit_this_attack: bool = false
var _idle_mode: IdleMode = IdleMode.PATROL
var _idle_switch_timer: float = 0.0
var _ceiling_y: float = 0.0

func _ready() -> void:
	super._ready()
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	_pick_idle_mode()

func _move(delta: float) -> void:
	if _bat_cooldown > 0.0:
		_bat_cooldown -= delta
	match _attack_state:
		AttackState.WINDUP:
			velocity = -_dash_dir * reverse_speed
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_dash()
			return
		AttackState.DASHING:
			velocity = _dash_dir * dash_speed
			_check_attack_hit()
			_state_timer -= delta
			if _state_timer <= 0.0:
				_attack_state = AttackState.RECOVER
				_state_timer = recover_time
			return
		AttackState.RECOVER:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				_attack_state = AttackState.NONE
				# Cooldown applies here regardless of hit/miss — setting it
				# only inside _check_attack_hit() would let a missed dash
				# re-attack immediately with no cooldown at all.
				_bat_cooldown = attack_cooldown_bat
			return

	if target:
		if _bat_cooldown <= 0.0 and global_position.distance_to(target.global_position) <= attack_range:
			_start_windup()
			return
		super._move(delta)
		return

	_idle_switch_timer -= delta
	if _idle_switch_timer <= 0.0:
		_pick_idle_mode()
	if _idle_mode == IdleMode.CEILING:
		var to_ceiling = _ceiling_y - global_position.y
		if abs(to_ceiling) > 2.0:
			velocity = Vector2(0, sign(to_ceiling) * CEILING_MOVE_SPEED)
			_set_clinging(false)
		else:
			velocity = Vector2.ZERO
			_set_clinging(true)
	else:
		_set_clinging(false)
		super._move(delta)

# Freezes the flap animation on whatever frame it's on while actually
# settled at the ceiling (not just en route there) — same _sprite.pause()
# base_enemy.gd's own stun-freeze uses, called every frame while clinging
# rather than once, so it stays frozen regardless of what order this runs
# in relative to _update_sprite() each frame. Only un-pauses explicitly when
# leaving the clung state (base_enemy.gd's own _update_sprite() has no idea
# this happened, since it only auto-resumes after a STUN specifically).
var _clinging: bool = false

func _set_clinging(clinging: bool) -> void:
	if clinging:
		if _sprite:
			_sprite.pause()
		_clinging = true
	elif _clinging:
		_clinging = false
		if _sprite:
			_sprite.play()

func _pick_idle_mode() -> void:
	_idle_switch_timer = randf_range(3.0, 6.0)
	if randf() < 0.5:
		_idle_mode = IdleMode.PATROL
	else:
		_idle_mode = IdleMode.CEILING
		_find_ceiling()

func _find_ceiling() -> void:
	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(
		global_position, global_position + Vector2(0, -CEILING_PROBE_RANGE), 1)
	query.exclude = [self.get_rid()]
	var result = space.intersect_ray(query)
	_ceiling_y = result.position.y + CEILING_REST_OFFSET if result else global_position.y

func _start_windup() -> void:
	_attack_state = AttackState.WINDUP
	_state_timer = windup_time
	_dash_dir = (target.global_position - global_position).normalized()
	direction = 1 if _dash_dir.x >= 0.0 else -1
	modulate = WINDUP_TINT

func _start_dash() -> void:
	_attack_state = AttackState.DASHING
	_state_timer = dash_duration
	_hit_this_attack = false
	# Re-aim at where the target actually is now that windup's over, but the
	# dash itself is still a locked burst — doesn't home mid-flight.
	if target:
		_dash_dir = (target.global_position - global_position).normalized()
	modulate = Color.WHITE

func _check_attack_hit() -> void:
	if _hit_this_attack or not target:
		return
	if global_position.distance_to(target.global_position) <= hit_check_radius:
		_hit_this_attack = true
		target.take_damage(attack_damage, false, self)
		if target.has_method("add_camera_trauma"):
			target.add_camera_trauma(0.2)
