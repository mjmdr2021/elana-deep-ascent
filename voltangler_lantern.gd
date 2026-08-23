extends Node2D

# Voltangler's destructible lantern lure (2026-08-22) -- a separate hittable
# sub-part, same "child node with its own Hurtbox literally named 'Hurtbox'"
# pattern web_strand.gd already uses for Broodspawner's anchors. Necessary
# because elana.gd's swing-hit detection hardcodes `area.name == "Hurtbox"`
# (_on_hitbox_area_entered()) -- a second hittable part on the same boss
# needs its own node with its own Hurtbox child, not just another Area2D
# hanging off the main body's already-named Hurtbox.
#
# No HP pool -- ANY landed hit destroys it outright, matching the user's own
# framing ("elana can destroy it") as one decisive hit, not a DPS check.
# voltangler.gd toggles this node's own Hurtbox.monitoring on/off each
# reveal window (see _show_lantern()/_hide_lantern()); normally only an
# actual hit while it's toggled on reaches here at all.
#
# 2026-08-23, user report: "when i hit the lantern collision even latern
# visual not show. it gets destroyed... when lantern not visible, dont show
# also collision of lantern" -- rather than trust monitoring alone stayed
# perfectly in sync with the visual (Area2D signal delivery can lag a
# physics frame behind a script toggle), on_hit() now also asks boss_ref
# directly whether it's ACTUALLY in a revealed window right now and bails
# if not. Belt-and-suspenders: even if monitoring is ever left on outside a
# reveal window for any reason, a hit still can't register unless
# is_lantern_vulnerable() agrees.

var boss_ref: Node = null

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

func on_hit(_hit_direction: int, _damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if boss_ref == null or not boss_ref.has_method("is_lantern_vulnerable") or not boss_ref.is_lantern_vulnerable():
		return
	if boss_ref.has_method("on_lantern_destroyed"):
		boss_ref.on_lantern_destroyed()
	queue_free()
