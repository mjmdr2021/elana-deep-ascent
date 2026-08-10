extends Area2D

# Auto-derived from this instance's own path in the scene, so placing
# multiple copies just works — no manual per-instance ID to remember to set.
# (Used to be an @export defaulting to "rn_1" on every copy unless
# hand-edited — every placed Ritual Node was silently sharing that same ID,
# which is why touching one made all of them show as active.)
var node_id: String = ""

func _ready():
	node_id = str(get_tree().current_scene.get_path_to(self))
	body_entered.connect(_on_body_entered)
	if GameData.active_ritual_node == node_id:
		$ColorRect.color = Color.YELLOW

func _on_body_entered(body):
	if body.is_in_group("player") and GameData.active_ritual_node != node_id:
		GameData.active_ritual_node = node_id
		GameData.respawn_scene = get_tree().current_scene.scene_file_path
		GameData.respawn_position = global_position
		$ColorRect.color = Color.YELLOW
		GameData.save_game()
