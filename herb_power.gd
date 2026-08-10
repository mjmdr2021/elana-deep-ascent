extends "res://base_herb.gd"

func _init() -> void:
	herb_name = "Power Herb"
	item_id = "herbPower"
	color = Color(0.7, 0.2, 0.9)

func apply_effect() -> void:
	GameData.damage_multiplier = 1.5 + GameData.power_potency_bonus

func remove_effect() -> void:
	GameData.damage_multiplier = 1.0
