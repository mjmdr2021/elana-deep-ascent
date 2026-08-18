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
		GameData.save_game()
		_activate()

# A beat of weight to actually activating one — freezes her for 1s (matching
# the color tween's own duration) while the node eases from white to yellow,
# instead of the instant color-snap this used to be.
func _activate() -> void:
	GameData.in_cutscene = true
	$ColorRect.color = Color.WHITE
	var tween := create_tween()
	tween.tween_property($ColorRect, "color", Color.YELLOW, 1.0)
	await get_tree().create_timer(1.0).timeout
	# GameData is an autoload, so clearing in_cutscene here is safe even if
	# this node got freed during the wait (e.g. a scene reload from dying
	# mid-activation) — guarded anyway for consistency with dialog_marker.gd's
	# cutscenes, and so any future edit that touches `self` after this point
	# doesn't reopen that risk without a guard already in place.
	if not is_instance_valid(self):
		GameData.in_cutscene = false
		return
	GameData.in_cutscene = false
