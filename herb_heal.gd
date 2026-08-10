extends "res://base_herb.gd"

func _init() -> void:
	herb_name = "Heal Herb"
	item_id = "herbHeal"
	color = Color(0.15, 0.9, 0.4)

func apply_effect() -> void:
	GameData.hp_regen_herb_bonus = 5.0

func remove_effect() -> void:
	GameData.hp_regen_herb_bonus = 0.0
