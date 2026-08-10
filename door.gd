extends Area2D

@export var target_scene = ""
@export var spawn_point_id = "SpawnRight"

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	print("Door hit by: ", body.name, " | target: ", target_scene)
	if body.is_in_group("player"):
		GameData.spawn_point_id = spawn_point_id
		get_tree().change_scene_to_file.call_deferred(target_scene)
