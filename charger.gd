extends "res://enemy.gd"

# Telegraphed dash: pauses and flashes red, then bursts toward wherever
# Elana was standing at the moment the dash actually fires (not homing
# mid-dash), and self-stuns if she dodges and it slams into a wall instead.
enum ChargeState { IDLE, TELEGRAPH, DASHING, RECOVER }

@export var telegraph_time: float = 0.6
@export var dash_speed: float = 220.0
@export var dash_duration: float = 0.5
@export var recover_time: float = 0.6
@export var self_stun_duration: float = 1.5
const TELEGRAPH_TINT: Color = Color(1.6, 0.5, 0.5)

var _charge_state: ChargeState = ChargeState.IDLE
var _charge_timer: float = 0.0
var _dash_direction: int = 1

func _move(delta: float) -> void:
	if not target:
		_charge_state = ChargeState.IDLE
		modulate = Color.WHITE
		super._move(delta)
		return
	match _charge_state:
		ChargeState.IDLE:
			_charge_state = ChargeState.TELEGRAPH
			_charge_timer = telegraph_time
			direction = sign(target.global_position.x - global_position.x)
			velocity.x = 0
			modulate = TELEGRAPH_TINT
		ChargeState.TELEGRAPH:
			velocity.x = 0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_charge_state = ChargeState.DASHING
				_charge_timer = dash_duration
				_dash_direction = direction
				modulate = Color.WHITE
		ChargeState.DASHING:
			velocity.x = dash_speed * _dash_direction
			_charge_timer -= delta
			if is_on_wall():
				_self_stun()
			elif _charge_timer <= 0.0:
				_charge_state = ChargeState.RECOVER
				_charge_timer = recover_time
				velocity.x = 0
		ChargeState.RECOVER:
			velocity.x = 0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_charge_state = ChargeState.IDLE

func _self_stun() -> void:
	is_stunned = true
	stun_timer = max(stun_timer, self_stun_duration)
	velocity.x = 0
	_charge_state = ChargeState.RECOVER
	_charge_timer = recover_time
