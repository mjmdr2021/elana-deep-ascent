extends "res://vine_gate.gd"

# Same destructible-obstacle behavior as VineGate (HP, regen, hit-flash,
# persistent removal), except only a Warhammer melee swing can actually
# damage it — every other weapon, and any magic/elemental hit, bounces off
# harmlessly.
#
# If boss_ref is set (used for boss-arena entrance seals), the gate is fully
# invulnerable — not even a Warhammer can scratch it — for as long as that
# boss is alive. This is what stops a mid-fight cutscene retrigger: the
# player can't break back out through the entrance to re-cross the trigger
# zone until the boss is dead, at which point the gate reverts to a normal
# breakable one.
var boss_ref: Node = null

# Replaces vine_gate.gd's sword/spear/chain_claw rule entirely rather than
# stacking on top of it — warhammer isn't in that list, so inheriting it
# unchanged would reject every hit this gate is actually meant to accept.
func _is_valid_hit(is_magic: bool) -> bool:
	return not is_magic and GameData.current_weapon == "warhammer"

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	if boss_ref and is_instance_valid(boss_ref) and boss_ref.hp > 0:
		return
	super.on_hit(hit_direction, damage, is_magic, attacker)
