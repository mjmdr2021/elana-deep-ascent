extends Area2D

var direction: int = 1
var damage: int = 0

const TRAVEL: float = 16.0
const SPEED: float = 240.0

var _traveled: float = 0.0
var _hit: Array = []

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	input_pickable = false

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(8, 18)
	shape.shape = rect
	add_child(shape)

	var vis = ColorRect.new()
	vis.size = Vector2(8, 18)
	vis.position = Vector2(-4, -9)
	vis.color = Color(1.0, 0.85, 0.2, 0.75)
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vis)

	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	position.x += direction * SPEED * delta
	_traveled += SPEED * delta
	if _traveled >= TRAVEL:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.name != "Hurtbox":
		return
	var enemy = area.get_parent()
	if enemy in _hit:
		return
	if not enemy.is_in_group("enemies"):
		return
	_hit.append(enemy)
	enemy.velocity.x += direction * 80.0
	enemy.on_hit(direction, damage, true)
