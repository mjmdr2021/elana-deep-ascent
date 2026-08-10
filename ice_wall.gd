extends StaticBody2D

const WIDTH: float = 12.0
const HEIGHT: float = 32.0
const LIFETIME: float = 30.0
const ICE_NODE_TEXTURE = preload("res://ice-node.png")

var hp: float = 0.0
var _sprite: Sprite2D
var _lifetime_remaining: float = LIFETIME

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(WIDTH, HEIGHT)
	shape.shape = rect
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture = ICE_NODE_TEXTURE
	_sprite.z_index = 2
	add_child(_sprite)

	var hurtbox = Area2D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	var hb_shape = CollisionShape2D.new()
	var hb_rect = RectangleShape2D.new()
	hb_rect.size = Vector2(WIDTH, HEIGHT)
	hb_shape.shape = hb_rect
	hurtbox.add_child(hb_shape)
	add_child(hurtbox)

func _process(delta: float) -> void:
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		queue_free()

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false) -> void:
	hp -= damage
	if hp <= 0:
		queue_free()
		return
	_sprite.modulate = Color(2.5, 2.5, 2.5)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		_sprite.modulate = Color.WHITE

func on_elemental_hit(_element: String, hit_direction: int, damage: int) -> void:
	on_hit(hit_direction, damage, true)
