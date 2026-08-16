extends Area2D

# A real arced, gravity-affected shot — launch() computes the initial
# velocity needed to travel from the mortar to Elana's position over
# flight_time seconds under GRAVITY, so it visibly arcs instead of flying
# straight. Launch data is just stored on setup_launch() (safe to call
# before this is in the tree — it's plain Vector2/float data, not a
# position write); the actual global_position assignment + velocity math
# happens in _ready(), which Godot only calls once the node is properly in
# the tree with a resolved parent transform — setting global_position any
# earlier is unreliable.
#
# Lands (hatches) on actually touching terrain — checked BOTH via the
# body_entered signal AND a per-frame get_overlapping_bodies() poll, since
# a fast-falling projectile moved via raw position increments (not swept
# collision) can occasionally tunnel through a thin floor collider between
# frames without the signal firing; the poll catches it either way.
#
# Destructible mid-flight via its own Hurtbox child (any weapon/element) —
# killing it before it lands denies the hatch.
const GRAVITY: float = 600.0
const HIT_RADIUS: float = 14.0
@export var damage: int = 6
@export var hp: int = 4
const SWARMER_SCENE = preload("res://swarmer.tscn")

var velocity: Vector2 = Vector2.ZERO
var _done: bool = false
var _launch_from: Vector2 = Vector2.ZERO
var _launch_to: Vector2 = Vector2.ZERO
var _launch_flight_time: float = 0.8

func setup_launch(from: Vector2, to: Vector2, flight_time: float = 0.8) -> void:
	_launch_from = from
	_launch_to = to
	_launch_flight_time = flight_time

func _ready() -> void:
	add_to_group("enemy_projectiles")
	collision_layer = 0
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)
	global_position = _launch_from
	var dx = _launch_to.x - _launch_from.x
	var dy = _launch_to.y - _launch_from.y
	velocity = Vector2(dx / _launch_flight_time, (dy - 0.5 * GRAVITY * _launch_flight_time * _launch_flight_time) / _launch_flight_time)

func _physics_process(delta: float) -> void:
	if _done:
		return
	velocity.y += GRAVITY * delta
	position += velocity * delta
	rotation = velocity.angle()
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
		elana.take_damage(damage, false, self)
		_land(false)
		return
	if not get_overlapping_bodies().is_empty():
		_land(true)

func _on_body_entered(_body: Node) -> void:
	if not _done:
		_land(true)

func _land(hatch: bool) -> void:
	_done = true
	if hatch:
		var swarmer = SWARMER_SCENE.instantiate()
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
