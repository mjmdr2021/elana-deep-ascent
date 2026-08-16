extends Area2D

var damage_cooldown = 0.0
var elana_inside = false

func _ready():
	# Ant Queen's death reward halves damage from anything tagged this —
	# see elana.gd's take_damage(). Without it (and without passing self as
	# the attacker below), the reduction check there never has anything to
	# match against and silently never fires.
	add_to_group("hazards")
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
		get_tree().get_first_node_in_group("player").take_damage(2, false, self)
		damage_cooldown = 0.5
	damage_cooldown -= delta
