extends Area2D

# Broodspawner's periodic floor-egg summon — 8 spawn every 20s while she's
# UP (4 per side, symmetric charger/shielder/warrior/normalEnemy outward-
# to-inward — see broodspawner.gd's own spawn call for the exact
# positions/types). Any weapon except fist destroys it in one hit
# regardless of actual damage dealt; fist doesn't register a hit at all —
# matching the exact "destroyed in one hit by any weapon except fist"
# spec, fist is excluded entirely, not just weaker.

@export var hatch_time: float = 7.0
@export var enemy_scene: PackedScene

var _hatch_timer: float = 0.0
var _done: bool = false

func _ready() -> void:
	_hatch_timer = hatch_time

func _physics_process(delta: float) -> void:
	if _done:
		return
	_hatch_timer -= delta
	if _hatch_timer <= 0.0:
		_hatch()

func _hatch() -> void:
	if _done:
		return
	_done = true
	if enemy_scene != null:
		var enemy = enemy_scene.instantiate()
		enemy.position = position
		get_parent().call_deferred("add_child", enemy)
	queue_free()

func on_hit(_hit_direction: int, _damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if _done:
		return
	if GameData.current_weapon == "fist":
		return
	_done = true
	queue_free()

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)
