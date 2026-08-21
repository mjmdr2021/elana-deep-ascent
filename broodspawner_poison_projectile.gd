extends Area2D

# Broodspawner's Poison Spit projectile — same straight-line movement/
# terrain-despawn/distance-based-hit shape fire_bolt.gd uses. Hitting
# Elana directly poisons her on the spot; hitting terrain instead spawns a
# lingering poison puddle there (broodspawner_poison_puddle.tscn) — either
# way, something poisonous is left behind.

const PUDDLE_SCENE = preload("res://broodspawner_poison_puddle.tscn")
const SPEED: float = 180.0
const HIT_RADIUS: float = 14.0

@export var damage: int = 6
@export var poison_damage: int = 3
@export var poison_ticks: int = 4

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
		if elana.has_method("apply_player_poison"):
			elana.apply_player_poison(poison_damage, poison_ticks)
		queue_free()

func _on_body_entered(_body: Node) -> void:
	var puddle = PUDDLE_SCENE.instantiate()
	puddle.global_position = global_position
	puddle.poison_damage = poison_damage
	get_parent().call_deferred("add_child", puddle)
	queue_free()
