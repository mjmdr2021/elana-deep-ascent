extends "res://vine_gate.gd"

# Simple breakable obstacle — reuses vine_gate.gd's whole HP/damage-flash/
# hazards-group/mark_removed-persistence machinery as-is, just with a
# looser hit rule: unlike vine_gate.gd's sword/spear/chain_claw-only gate,
# any weapon (including fist, hammer, and elemental hits) breaks wood
# debris — it's just clutter blocking a path, not a magic/plant barrier.
# Also doesn't regenerate (regen_rate defaults to 0 in the .tscn) — wood
# doesn't grow back like a living vine gate does.

func _is_valid_hit(_is_magic: bool) -> bool:
	return true
