extends Area2D

# Ant Queen's egg — laid near her, stationary, does nothing on its own. If
# Elana doesn't destroy it within hatch_time, it hatches into a Swarmer at
# its own position — same "destroy it or it hatches" shape as
# hollowfang_spit.gd's landed spits, just placed directly instead of
# arriving there via flight.

@export var hp: int = 15
@export var hatch_time: float = 10.0

var skip_removed_check: bool = false
var _done: bool = false
var _hatch_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy_projectiles")
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
	var swarmer = load("res://swarmer.tscn").instantiate()
	swarmer.position = position
	swarmer.skip_removed_check = true
	get_parent().call_deferred("add_child", swarmer)
	queue_free()

func on_hit(_hit_direction: int, dmg: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if _done:
		return
	hp -= dmg
	if hp <= 0:
		_done = true
		queue_free()

func on_elemental_hit(_element: String, hit_direction: int, dmg: int, attacker: Node = null) -> void:
	on_hit(hit_direction, dmg, true, attacker)
