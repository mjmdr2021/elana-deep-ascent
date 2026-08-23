extends Node2D

# Broodspawner's real, scene-authored behind-the-back weak spot (2026-08-23,
# rebuilt after the user asked "did u create a collision zone for the
# behind weakness?" -- the first pass was a script-side position check on
# her single existing Hurtbox, which doesn't satisfy
# [[feedback-collision-shapes-in-scene]]. This is the proper version: a
# real second hittable region, same "child node + its own literally-named
# 'Hurtbox' child" shape voltangler_lantern.gd already uses for the same
# reason -- elana.gd's swing-hit detection hardcodes area.name == "Hurtbox",
# so a second hittable region on the same body can't just be another Area2D
# sharing the main Hurtbox's already-claimed name.
#
# Covers the rear half of her body (broodspawner.tscn split the old single
# 360-wide Hurtbox into two 180-wide halves: the main "Hurtbox" node stays
# the front, this is the back) and is kept mirrored to her facing by
# broodspawner.gd's own _update_facing(), same as every other zone on her.
#
# Unlike the Lantern (a genuinely separate destructible part with its own
# fate), a hit here deals damage into the SAME shared hp pool as the rest
# of her body -- this only changes WHICH defense value applies for that one
# hit, routed straight through boss_ref's own apply_weakspot_damage()
# rather than tracking anything independently here.

var boss_ref: Node = null

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if boss_ref != null and boss_ref.has_method("apply_weakspot_damage"):
		boss_ref.apply_weakspot_damage(damage)
