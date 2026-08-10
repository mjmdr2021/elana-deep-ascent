extends "res://flying_enemy.gd"

# A single stagnant fly, not a swarm — doesn't aggro, doesn't roam, just
# hovers in place with a gentle vertical bob (no horizontal drift at all).
# Emits its own ambient glow (a PointLight2D, same radial-gradient-texture
# technique enemy eye-glows already use) and zaps Elana on direct contact —
# AttackZone is repurposed as a small touch trigger instead of the normal
# windup-attack cycle, matching the "no aggro, pure contact hazard" feel.
@export var hover_amplitude: float = 3.0
@export var hover_speed: float = 3.0
const GLOW_COLOR: Color = Color(1.0, 0.95, 0.3, 1.0)
const TOUCH_SIZE: float = 14.0

func _ready() -> void:
	super._ready()
	if $AggroZone.body_entered.is_connected(_on_aggro_zone_body_entered):
		$AggroZone.body_entered.disconnect(_on_aggro_zone_body_entered)
	if $AggroZone.body_exited.is_connected(_on_aggro_zone_body_exited):
		$AggroZone.body_exited.disconnect(_on_aggro_zone_body_exited)
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TOUCH_SIZE, TOUCH_SIZE)
	$AttackZone/CollisionShape2D.shape = shape
	$AttackZone.position = Vector2.ZERO
	$AttackZone.body_entered.connect(_on_zap_touch)
	_add_glow()

func _add_glow() -> void:
	var light := PointLight2D.new()
	light.texture = _make_glow_texture()
	light.color = GLOW_COLOR
	light.energy = 0.8
	light.texture_scale = 0.3
	add_child(light)

func _make_glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([Color(3, 3, 3, 1), Color(1, 1, 0.6, 0.4), Color(1, 1, 0.6, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 96
	tex.height = 96
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	return tex

func _move(_delta: float) -> void:
	velocity = Vector2(0, sin(hover_time * hover_speed) * hover_amplitude)

func _on_zap_touch(body: Node) -> void:
	if body.is_in_group("player"):
		body.take_damage(attack_damage, false, self)
