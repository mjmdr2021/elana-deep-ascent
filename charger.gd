extends "res://enemy.gd"

# Telegraphed dash: pauses and flashes red, then bursts toward wherever
# Elana was standing at the moment the dash actually fires (not homing
# mid-dash) and keeps going — no time limit — until it actually hits
# something: a wall/ore node/ice wall or her (all StaticBody2D on the same
# collision layer, so is_on_wall() already covers all three uniformly, no
# special-casing needed), stunning itself for stun_duration (2s) either way.
# Not a short controlled burst; it's meant to be unstoppable until it
# connects with an obstacle, so dodging clear of its path is the real
# counterplay, not just waiting it out.
#
# While DASHING it's immune to everything except a warhammer hit: damage
# from any other weapon/element is blocked via modify_incoming_damage()
# (the generic hit_handler.gd hook), any pending knockback from a non-
# warhammer source is cleared before base_enemy.gd consumes it (see
# _physics_process() below — same technique Shield-bearer's own
# knockback-magnitude peek already uses), and Chain Claw's pull is refused
# outright via blocks_chain_pull(). Elana herself gets knocked back hard on
# a landed hit, via her new apply_knockback() (a naive velocity write would
# just get overwritten by her own movement code the same frame — same
# reason enemies need _pending_knockback instead of a direct write).
#
# The generic melee windup/AttackZone cycle is disconnected in _ready() —
# without that, getting close enough mid-dash to also trigger the generic
# AttackZone would start its own windup, and base_enemy.gd's
# _physics_process gates _move() entirely behind "not currently in that
# windup" — freezing this whole state machine while velocity.x stayed
# locked at full dash speed. The dash deals its own damage directly (a
# distance check during DASHING), since a body-to-body collision alone
# never actually hit her — Elana's collision mask excludes the enemy layer
# entirely, so this was always relying on that now-disconnected generic
# system to land anything.
enum ChargeState { IDLE, TELEGRAPH, DASHING, RECOVER }

@export var telegraph_time: float = 0.6
@export var dash_speed: float = 220.0
@export var recover_time: float = 0.6
@export var stun_duration: float = 2.0
@export var hit_check_radius: float = 16.0
@export var knockback_x: float = 320.0
@export var knockback_y: float = -100.0
const TELEGRAPH_TINT: Color = Color(1.6, 0.5, 0.5)
const IMMUNE_WEAPON: String = "warhammer"

var _charge_state: ChargeState = ChargeState.IDLE
var _charge_timer: float = 0.0
var _dash_direction: int = 1
var _hit_this_charge: bool = false
var _stun_indicator: Label = null

func _ready() -> void:
	super._ready()
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)

# Runs before base_enemy.gd's own _physics_process, which consumes
# _pending_knockback into `velocity` and resets it to zero right away —
# clearing a non-warhammer knockback here means it never lands at all.
func _physics_process(delta: float) -> void:
	if _charge_state == ChargeState.DASHING and GameData.current_weapon != IMMUNE_WEAPON:
		_pending_knockback = Vector2.ZERO
	super._physics_process(delta)

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
				_dash_direction = direction
				_hit_this_charge = false
				modulate = Color.WHITE
		ChargeState.DASHING:
			# No time limit — keeps charging until it actually hits a wall
			# or her, not until some fixed duration runs out.
			velocity.x = dash_speed * _dash_direction
			_check_dash_hit()
			if is_on_wall():
				_smash_obstacle()
				_end_charge_stunned()
		ChargeState.RECOVER:
			velocity.x = 0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_charge_state = ChargeState.IDLE

func _check_dash_hit() -> void:
	if _hit_this_charge or not target:
		return
	if global_position.distance_to(target.global_position) <= hit_check_radius:
		_hit_this_charge = true
		target.take_damage(attack_damage, false, self)
		if target.has_method("apply_knockback"):
			target.apply_knockback(Vector2(knockback_x * _dash_direction, knockback_y))
		if target.has_method("add_camera_trauma"):
			target.add_camera_trauma(0.3)
		_end_charge_stunned()

# Smashes through whatever it just rammed into — one-shots any hittable
# static obstacle in its path (ore nodes, ice walls, and generically
# anything else with on_hit(), same "generalize over special-case"
# philosophy the rest of this session's hooks use), not hardcoded to just
# those two types by name. Plain terrain has no on_hit() at all, so it's
# naturally skipped — no filtering needed. get_slide_collision() reflects
# the collision that made is_on_wall() true this frame, so this only ever
# picks up whatever it's actually touching, not other enemies (they're on
# a different collision layer Charger's own body doesn't physically
# collide with in the first place).
func _smash_obstacle() -> void:
	for i in get_slide_collision_count():
		var collider = get_slide_collision(i).get_collider()
		if collider and collider != self and collider.has_method("on_hit"):
			collider.on_hit(0, 9999, false)

func _end_charge_stunned() -> void:
	is_stunned = true
	stun_timer = max(stun_timer, stun_duration)
	velocity.x = 0
	_charge_state = ChargeState.RECOVER
	_charge_timer = recover_time
	_show_stun_indicator()

func _show_stun_indicator() -> void:
	if is_instance_valid(_stun_indicator):
		return
	_stun_indicator = GameData.make_stun_indicator()
	add_child(_stun_indicator)
	await get_tree().create_timer(stun_duration).timeout
	if is_instance_valid(_stun_indicator):
		_stun_indicator.queue_free()
		_stun_indicator = null

# Generic hit_handler.gd hook — blocks damage from anything except a
# warhammer hit while actively dashing.
func modify_incoming_damage(_hit_direction: int, damage: int) -> int:
	if _charge_state == ChargeState.DASHING and GameData.current_weapon != IMMUNE_WEAPON:
		return 0
	return damage

# Generic chain_projectile.gd hook — can't be grappled/pulled while dashing,
# regardless of weapon (this one isn't a warhammer exception).
func blocks_chain_pull() -> bool:
	return _charge_state == ChargeState.DASHING
