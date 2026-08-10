extends Area2D

# Off on a specific instance (e.g. lava.tscn, temporarily) to make that
# hazard harmless without touching the shared script's default lethal
# behavior for the others (electrified_water.tscn, the generic death_zone.tscn).
@export var lethal: bool = true

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if lethal and body.is_in_group("player"):
		body.die()
