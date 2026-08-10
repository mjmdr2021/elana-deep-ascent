extends "res://vine_gate.gd"

# Same destructible-obstacle behavior as VineGate (HP, regen, hit-flash,
# persistent removal), except only a Warhammer melee swing can actually
# damage it — every other weapon, and any magic/elemental hit, bounces off
# harmlessly.
func on_hit(hit_direction: int, damage: int, is_magic: bool = false) -> void:
	if is_magic or GameData.current_weapon != "warhammer":
		return
	super.on_hit(hit_direction, damage, is_magic)
