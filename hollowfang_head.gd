extends Node2D

# The weak-point hitbox — a separate child node with its own Hurtbox, so it
# can use a much lower defense than the armored body while still feeding
# the same shared HP pool (via the parent's apply_boss_damage()) rather
# than tracking its own separate hp.

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	var boss = get_parent()
	if boss == null or boss.hp <= 0:
		return
	var final_damage = GameData.calc_damage(float(damage), float(boss.head_defense))
	boss.apply_boss_damage(final_damage)

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)
