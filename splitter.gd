extends "res://enemy.gd"

# Splits into smaller copies on death — once. Spawned children have
# is_split_child = true so they don't chain-split infinitely.
@export var is_split_child: bool = false
@export var split_count: int = 2
@export var split_hp_fraction: float = 0.5
@export var split_scale: float = 0.65

func on_death() -> void:
	if is_split_child:
		return
	var splitter_scene = load("res://splitter.tscn")
	for i in split_count:
		var child = splitter_scene.instantiate()
		child.is_split_child = true
		child.max_hp = max(1, int(max_hp * split_hp_fraction))
		child.scale = scale * split_scale
		child.position = position + Vector2(randf_range(-10, 10), -4)
		child.skip_removed_check = true
		get_parent().call_deferred("add_child", child)
