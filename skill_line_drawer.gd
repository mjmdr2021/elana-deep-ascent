extends Control

var connections: Array = []
var node_positions: Dictionary = {}

const NODE_W: float = 64.0
const NODE_H: float = 64.0

func _draw() -> void:
	for conn in connections:
		var a_id: String = conn[0]
		var b_id: String = conn[1]
		if not (node_positions.has(a_id) and node_positions.has(b_id)):
			continue
		var a_pos: Array = node_positions[a_id]
		var b_pos: Array = node_positions[b_id]
		var a_center := Vector2(a_pos[0] + NODE_W * 0.5, a_pos[1] + NODE_H * 0.5)
		var b_center := Vector2(b_pos[0] + NODE_W * 0.5, b_pos[1] + NODE_H * 0.5)
		draw_line(a_center, b_center, Color(0.4, 0.55, 0.4, 0.65), 2.0)
