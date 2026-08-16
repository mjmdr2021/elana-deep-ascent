extends Area2D

# Hollowfang's Spit Volley projectile — big, hurts Elana on a direct hit,
# hatches a Swarmer where it lands if it doesn't (terrain body_entered, same
# event that ends the flight either way). Destructible mid-air via its own
# Hurtbox, same "weapon/element both work" pattern every other destructible
# enemy projectile this session uses.
const SPEED: float = 180.0
const HIT_RADIUS: float = 16.0
@export var damage: int = 10
@export var hp: int = 6

# Emitted exactly once, right before this projectile frees itself, whichever
# way it resolves (hit Elana, landed and hatched, timed out, or destroyed
# mid-air). Passes the hatched Swarmer if one was spawned, otherwise null —
# lets hollowfang.gd track the whole volley (in-flight spits + whatever they
# hatched) as one group, so it knows when it's actually safe to spit again.
signal resolved(swarmer: Node)

var aim_direction: Vector2 = Vector2.RIGHT
var lifetime: float = 5.0
var _done: bool = false
# Hollowfang's own body is on the terrain layer too (needed so Elana can't
# walk through it), and this spawns right next to the boss — a fixed grace
# window alone isn't enough, since at this speed it could easily still be
# inside the boss's own ~480px-wide footprint by the time any short window
# expired, just hitting the same bug delayed. Excluding the exact spawning
# body by reference instead — correct regardless of how long it takes to
# actually clear the boss's own collision, and never mistakes genuine
# terrain elsewhere for "still touching the caster".
var source: Node = null

func _ready() -> void:
	add_to_group("enemy_projectiles")
	collision_layer = 0
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)
	rotation = aim_direction.angle()

func _physics_process(delta: float) -> void:
	if _done:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_land(true)
		return
	position += aim_direction * SPEED * delta
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
		elana.take_damage(damage, false, self)
		_land(false)

func _on_body_entered(body: Node) -> void:
	# Not just `body == source` — Hollowfang's head has its own separate
	# solid body (HeadCollision) that spits spawn right next to, see
	# hollowfang.gd's owns_body().
	if source != null and source.has_method("owns_body") and source.owns_body(body):
		return
	_land(true)

func _land(hatch: bool) -> void:
	if _done:
		return
	_done = true
	var swarmer: Node = null
	if hatch:
		swarmer = load("res://swarmer.tscn").instantiate()
		swarmer.position = position
		swarmer.skip_removed_check = true
		get_parent().call_deferred("add_child", swarmer)
	resolved.emit(swarmer)
	queue_free()

func on_hit(_hit_direction: int, dmg: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if _done:
		return
	hp -= dmg
	if hp <= 0:
		_done = true
		resolved.emit(null)
		queue_free()

func on_elemental_hit(_element: String, hit_direction: int, dmg: int, attacker: Node = null) -> void:
	on_hit(hit_direction, dmg, true, attacker)
