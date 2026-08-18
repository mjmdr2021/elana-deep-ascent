extends Area2D

# Ant Queen's egg — laid near her, stationary, does nothing on its own. If
# Elana doesn't destroy it within hatch_time, it hatches into a Swarmer at
# its own position — same "destroy it or it hatches" shape as
# hollowfang_spit.gd's landed spits, just placed directly instead of
# arriving there via flight.

@export var hp: int = 15
@export var hatch_time: float = 10.0
# Fallback only — ant_queen.gd overwrites this with its own
# egg_hatch_vicinity_radius export on every egg it lays, same as hatch_time
# above. Matters if an egg is ever hand-placed in a scene without a queen.
@export var hatch_vicinity_radius: float = 30.0

# Set by ant_queen.gd right after spawning — the hatch timer only ticks while
# Elana is within hatch_vicinity_radius of THIS (her), not the egg itself, so
# a queen can be ignored entirely and her eggs just sit banked, unhatched,
# instead of quietly building an ambush while she's out of sight.
var queen: Node = null

var skip_removed_check: bool = false
var _done: bool = false
var _hatch_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy_projectiles")
	add_to_group("ant_eggs")
	_hatch_timer = hatch_time

func _physics_process(delta: float) -> void:
	if _done:
		return
	if not _player_in_hatch_vicinity():
		return
	_hatch_timer -= delta
	if _hatch_timer <= 0.0:
		_hatch()

# No queen reference (defensive — shouldn't happen via the normal spawn path)
# fails safe as "never hatches" rather than hatching unconditionally.
func _player_in_hatch_vicinity() -> bool:
	if not is_instance_valid(queen):
		return false
	var player = get_tree().get_first_node_in_group("player")
	return player != null and queen.global_position.distance_to(player.global_position) <= hatch_vicinity_radius

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
