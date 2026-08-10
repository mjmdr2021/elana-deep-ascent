extends Area2D

var player_inside: bool = false
var player: Node = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player = body
		player_inside = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player = null
		player_inside = false
