extends Area2D

var damage_cooldown = 0.0
var elana_inside = false

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("player"):
		elana_inside = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		elana_inside = false

func _process(delta):
	if elana_inside and damage_cooldown <= 0:
		get_tree().get_first_node_in_group("player").take_damage(2)
		damage_cooldown = 0.5
	damage_cooldown -= delta
