extends "res://ore_node.gd"

# Never destroyed — bursts out ore whenever the current threshold is hit,
# then the NEXT threshold grows by THRESHOLD_GROWTH (60 -> 80 -> 100 -> ...)
# instead of resetting to the same amount every cycle. Reuses ore_node.gd's
# OreType dropdown/ORE_TYPE_IDS/drop_ores()/show_break_hint entirely as-is,
# overriding only the one seam ore_node.gd exposes for what happens when hp
# reaches 0 (_on_threshold_reached()) — same "extends + override one hook"
# pattern wood_debris.gd uses on vine_gate.gd.
const THRESHOLD_GROWTH: int = 20
const BASE_THRESHOLD: int = 60  # 2x ore_node.gd's own base of 30

# Tracked separately from hp — hp gets consumed down to <=0 each cycle, this
# is the "full" value it gets reset to, which itself grows every burst.
var _threshold: int = BASE_THRESHOLD

func _ready() -> void:
	super._ready()
	hp = _threshold

func _on_threshold_reached() -> void:
	drop_ores()
	_threshold += THRESHOLD_GROWTH
	hp = _threshold
