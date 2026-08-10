extends Area2D

# Straight-line enemy projectile — same movement/lifetime/terrain-despawn
# shape as projectile.gd, but also applies player-burn (apply_player_burn)
# on a landed hit. Used by Fire Plant Spitter and Magma Monster's ranged
# lob.
const SPEED: float = 160.0
const HIT_RADIUS: float = 14.0
@export var damage: int = 6
@export var burn_damage: int = 2
@export var burn_ticks: int = 3

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
		if elana.has_method("apply_player_burn"):
			elana.apply_player_burn(burn_damage, burn_ticks)
		queue_free()

func _on_body_entered(_body: Node) -> void:
	queue_free()
