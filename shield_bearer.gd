extends "res://enemy.gd"

# Blocks 100% of damage from hits landing on its shield side (wherever it's
# currently facing — enemy.gd's chase _move() already keeps direction
# pointed at Elana while actively chasing) — a full block, not a reduction.
# A strong knockback — plunge or hammer heavy — staggers it and knocks the
# shield down for a few seconds, exposing it to full damage from any
# direction during that window.
#
# Chain Claw is a pure utility tool against it, not a damage source: hitting
# it always deals zero damage (on_chain_hit(), a generic chain_projectile.gd
# hook that bypasses the normal on_hit() damage path entirely). The FIRST
# throw while shielded only inactivates the shield — no pull. Only a SECOND
# throw, landing after the shield is already down, actually pulls it in.
@export var block_damage_mult: float = 0.0
@export var flip_knockback_threshold: float = 200.0
@export var exposed_duration: float = 3.0
const SHIELD_UP_TINT: Color = Color(2.2, 2.0, 0.3, 1.0)

var _exposed_timer: float = 0.0
var _base_modulate: Color
var _pull_allowed: bool = false

func _ready() -> void:
	super._ready()
	_base_modulate = modulate
	modulate = SHIELD_UP_TINT

# Runs before base_enemy.gd's own _physics_process, which consumes
# _pending_knockback into `velocity` and resets it to zero right away — this
# is the only point where its pre-consumption magnitude can still be read.
func _physics_process(delta: float) -> void:
	if _exposed_timer <= 0.0 and _pending_knockback.length() >= flip_knockback_threshold:
		_drop_shield()
	if _exposed_timer > 0.0:
		_exposed_timer -= delta
		if _exposed_timer <= 0.0:
			modulate = SHIELD_UP_TINT
	super._physics_process(delta)

func _drop_shield() -> void:
	_exposed_timer = exposed_duration
	modulate = _base_modulate

# Generic hit_handler.gd hook — hit_direction encodes which side the attack
# came from (see hit_handler.gd's _apply_damage comment). Frontal = shield
# facing toward the attacker; blocked to a fraction of the damage unless
# the shield is currently knocked down.
func modify_incoming_damage(hit_direction: int, damage: int) -> int:
	if _exposed_timer > 0.0:
		return damage
	var is_frontal = (hit_direction * direction) < 0
	if is_frontal:
		return int(damage * block_damage_mult)
	return damage

# Generic chain_projectile.gd hook — called instead of the normal on_hit()
# damage path. Always zero damage. Pull is only allowed if the shield was
# ALREADY down before this particular hit (checked before _drop_shield()
# overwrites the timer) — so the throw that disables the shield never also
# pulls; that takes a separate, second throw.
func on_chain_hit() -> void:
	_pull_allowed = _exposed_timer > 0.0
	_drop_shield()

# Generic chain_projectile.gd hook — checked right after on_chain_hit()
# above, using the pre-hit state it captured.
func blocks_chain_pull() -> bool:
	return not _pull_allowed
