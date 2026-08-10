extends "res://base_herb.gd"

func _init() -> void:
	herb_name = "Agility Herb"
	item_id = "herbAgility"
	color = Color(0.2, 0.85, 0.85)

func apply_effect() -> void:
	GameData.attack_speed_herb_bonus = 20 + GameData.attack_speed_node_bonus
	GameData.move_speed_herb_bonus = 10.0

func remove_effect() -> void:
	GameData.attack_speed_herb_bonus = 0
	GameData.move_speed_herb_bonus = 0.0
