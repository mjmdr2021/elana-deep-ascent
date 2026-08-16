extends StaticBody2D

# A level-placed hazard prop, same StaticBody2D + Hurtbox structure as
# ore_node.gd/ice_wall.gd — but unlike either of those, this is a hazard:
# touching it burns Elana. Frost hits deal double damage (cooling molten
# rock cracks it faster), reusing the same on_elemental_hit(element, ...)
# entry point every other hittable object already implements.
@export var hp: float = 40.0
@export var burn_damage_per_tick: int = 3
@export var burn_ticks: int = 3

var original_color: Color

func _ready() -> void:
	original_color = $ColorRect.color
	$ContactZone.body_entered.connect(_on_contact_entered)

func _on_contact_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("apply_player_burn"):
		body.apply_player_burn(burn_damage_per_tick, burn_ticks)

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	var mult = 2.0 if element == "frost" else 1.0
	on_hit(hit_direction, int(damage * mult), true, attacker)

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	hp -= damage
	GameData.spawn_damage_number(damage, global_position)
	if hp <= 0:
		queue_free()
		return
	$ColorRect.color = Color.RED
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self):
		$ColorRect.color = original_color
