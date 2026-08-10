extends Area2D

# Straight-line enemy projectile — mirrors fire_bolt.gd, but applies slow
# (and a chance to fully freeze) instead of burn on a landed hit. Used by
# Ice Plant Spitter.
const SPEED: float = 160.0
const HIT_RADIUS: float = 14.0
@export var damage: int = 5
@export var slow_factor: float = 0.5
@export var slow_duration: float = 2.0
@export var freeze_chance: float = 0.15
@export var freeze_duration: float = 1.0

var aim_direction: Vector2 = Vector2.RIGHT
var lifetime: float = 4.0

func _ready() -> void:
	add_to_group("enemy_projectiles")
	collision_layer = 0
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)
	rotation = aim_direction.angle()

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	position += aim_direction * SPEED * delta
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
		elana.take_damage(damage, false, self)
		if elana.has_method("apply_slow"):
			elana.apply_slow(slow_factor, slow_duration)
		if elana.has_method("apply_freeze") and randf() < freeze_chance:
			elana.apply_freeze(freeze_duration)
		queue_free()

func _on_body_entered(_body: Node) -> void:
	queue_free()
