extends Area2D

const SPEED = 180.0
var aim_direction = Vector2.RIGHT
var lifetime = 4.0
var damage = 10
var slow_factor: float = 1.0
var _slow_timer: float = 0.0

func _ready():
	add_to_group("enemy_projectiles")
	body_entered.connect(_on_body_entered)
	$Sprite2D.rotation = aim_direction.angle()
	if GameData.danger_sense_active_timer > 0.0:
		apply_slow(GameData.DANGER_SENSE_SLOW_FACTOR, GameData.danger_sense_active_timer)

func _on_body_entered(_body):
	queue_free()

func apply_slow(factor: float, duration: float) -> void:
	slow_factor = min(slow_factor, factor)
	_slow_timer = max(_slow_timer, duration)

func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			slow_factor = 1.0
	position += aim_direction * SPEED * slow_factor * delta
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) < 14:
		elana.take_damage(damage, false, self)
		queue_free()
