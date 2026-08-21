extends Area2D

# Broodspawner's UP-phase spit — travels in a straight line until it hits
# terrain, then stops and becomes a stationary egg with a hatch timer.
# Destructible while waiting to hatch, same shape as ant_egg.gd (raw
# damage subtraction, no defense math). On hatch, spawns swarm.tscn — the
# existing spawner that clusters a handful of Swarmers around itself —
# reused as-is rather than reinventing "summon a swarm" from scratch.

const SWARM_SCENE = preload("res://swarm.tscn")
const SPEED: float = 200.0
const LIFETIME: float = 3.0  # despawns if it somehow never hits anything

@export var hp: int = 15
@export var hatch_time: float = 10.0

var direction: Vector2 = Vector2.RIGHT
var _landed: bool = false
var _hatch_timer: float = 0.0
var _lifetime_remaining: float = LIFETIME
var _done: bool = false

@onready var _color_rect: ColorRect = $ColorRect
const TRAVEL_COLOR: Color = Color(0.5, 0.8, 0.3, 1.0)
const EGG_COLOR: Color = Color(0.75, 0.9, 0.6, 1.0)

func _ready() -> void:
	add_to_group("enemy_projectiles")
	collision_layer = 0
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)
	_color_rect.color = TRAVEL_COLOR

func _physics_process(delta: float) -> void:
	if _done:
		return
	if not _landed:
		_lifetime_remaining -= delta
		if _lifetime_remaining <= 0.0:
			queue_free()
			return
		position += direction * SPEED * delta
		return
	_hatch_timer -= delta
	if _hatch_timer <= 0.0:
		_hatch()

func _on_body_entered(_body: Node) -> void:
	if _landed:
		return
	_landed = true
	_hatch_timer = hatch_time
	_color_rect.color = EGG_COLOR

func _hatch() -> void:
	if _done:
		return
	_done = true
	var swarm = SWARM_SCENE.instantiate()
	swarm.position = position
	get_parent().call_deferred("add_child", swarm)
	queue_free()

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if _done or not _landed:
		return
	hp -= damage
	if hp <= 0:
		_done = true
		queue_free()

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)
