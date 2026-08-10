extends "res://base_herb.gd"

var element: String = ""

func apply_effect() -> void:
	GameData.elemental_active = true
	GameData.elemental_element = element

func remove_effect() -> void:
	GameData.elemental_active = false
	GameData.elemental_element = ""
