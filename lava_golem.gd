extends "res://enemy.gd"

# Normal-enemy-sized fire brute — no trail (unlike Magma Slug). Melee hits
# apply burn on top of normal damage; when Elana's too far to melee, it
# lobs fire_bolt.tscn "magma balls" at her on its own cooldown instead.
#
# Armored shell that cracks under repeated hits — starts heavily defended
# (high `defense`); once `shell_hits_to_crack` hits have landed, the shell
# permanently cracks, dropping `defense` to `cracked_defense` for the rest
# of the fight. Hit-counting reuses modify_incoming_damage(), the same
# generic hit_handler.gd hook Shield-bearer uses — it fires on every hit
# regardless of source (melee/elemental), before defense/damage math runs.
const FIRE_BOLT_SCENE = preload("res://fire_bolt.tscn")
@export var ranged_range: float = 120.0
@export var ranged_cooldown_time: float = 2.0
@export var magma_ball_damage: int = 8
@export var monster_burn_damage: int = 3
@export var monster_burn_ticks: int = 3
@export var shell_hits_to_crack: int = 5
@export var cracked_defense: int = 8
const CRACKED_TINT: Color = Color(0.9, 0.5, 0.25, 1.0)

var _ranged_cooldown: float = 0.0
var _hits_taken: int = 0
var _cracked: bool = false

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	if _ranged_cooldown > 0.0:
		_ranged_cooldown -= delta

func _move(delta: float) -> void:
	super._move(delta)
	if target and _ranged_cooldown <= 0.0 and global_position.distance_to(target.global_position) > ranged_range:
		_fire_magma_ball()
		_ranged_cooldown = ranged_cooldown_time

func _fire_magma_ball() -> void:
	var bolt = FIRE_BOLT_SCENE.instantiate()
	var aim_dir = (target.global_position - global_position).normalized()
	bolt.aim_direction = aim_dir
	bolt.damage = magma_ball_damage
	bolt.position = position + aim_dir * 20.0
	get_parent().call_deferred("add_child", bolt)

# Overrides base_enemy.gd's _perform_attack() entirely (rather than calling
# super and separately checking whether it landed) so burn only applies on
# an actual connected hit, not whenever the wall raycast blocks it.
func _perform_attack() -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana:
		$WallCheck.target_position = to_local(elana.global_position)
		$WallCheck.force_raycast_update()
		if not $WallCheck.is_colliding():
			elana.take_damage(attack_damage, false, self)
			if elana.has_method("apply_player_burn"):
				elana.apply_player_burn(monster_burn_damage, monster_burn_ticks)
	attack_cooldown = attack_cooldown_time

func modify_incoming_damage(_hit_direction: int, damage: int) -> int:
	if not _cracked:
		_hits_taken += 1
		if _hits_taken >= shell_hits_to_crack:
			_crack_shell()
	return damage

func _crack_shell() -> void:
	_cracked = true
	defense = cracked_defense
	modulate = CRACKED_TINT
