extends Node

# Attach as a child of any world object (gates, ore/herb nodes, Moleman,
# geysers, hazard nodes, etc.) to hide it while Elana is far away and show it
# again once she's back in range. Same idea as base_enemy.gd's
# VISIBILITY_RADIUS band, but standalone — for stationary props/NPCs that
# don't need an "active/frozen" physics state, just visibility, and whose
# base class/existing _process() logic varies too much to share code by
# inheritance. Zero changes needed to the object's own script.
const VISIBILITY_RADIUS: float = 900.0
const CHECK_INTERVAL: float = 0.3

var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var target: Node2D = get_parent()
	target.visible = target.global_position.distance_to(player.global_position) <= VISIBILITY_RADIUS
