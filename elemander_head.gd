extends Node2D

# Elemander's head pivot -- a real Node2D (matching broodspawner_weakspot.gd's
# own base class exactly, not Area2D -- this node itself has no physics
# role, only its child "Hurtbox" does), separate from Head itself (2026-08-30,
# user explicit: "make a new one. i dont want them to be the same shit" --
# Head stays the fixed Frost Beam origin/aim anchor, this is the genuinely
# decoupled node that owns the visual/collision/hurtbox and will be what
# eventually rotates for the head-tilt feature, still on hold).
#
# A plain child Area2D named "Hurtbox" here would call .on_hit() on THIS
# node (its direct parent, per elana.gd's _on_hitbox_area_entered() ->
# area.get_parent() convention) -- same "wrapper node + child literally
# named Hurtbox" pattern broodspawner_weakspot.gd and voltangler_lantern.gd
# already use for their own second hittable regions. Forwards straight to
# Elemander's own on_hit()/on_elemental_hit() -- same damage/defense as the
# body, not a separate weak-spot value (no damage differential was asked
# for, just extended hit coverage).

var boss_ref: Node = null

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	if boss_ref != null and boss_ref.has_method("on_hit"):
		boss_ref.on_hit(hit_direction, damage, is_magic, attacker)

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	if boss_ref != null and boss_ref.has_method("on_elemental_hit"):
		boss_ref.on_elemental_hit(element, hit_direction, damage, attacker)
