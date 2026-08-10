extends "res://flying_enemy.gd"

# Never attacks at all (AttackZone signals disconnected below). Healing is a
# passive aura, not a seek-and-heal behavior: every ally within heal_radius
# of wherever the wisp currently is gets healed continuously (a smooth
# per-second trickle applied every physics frame, not a chunky tick) — it
# doesn't navigate toward anyone. The only thing that overrides normal
# flying_enemy.gd patrol/hover is Elana getting close, which makes it flee.
@export var flee_range: float = 55.0
@export var flee_speed: float = 90.0
@export var heal_radius: float = 110.0
@export var heal_rate: float = 6.0
const AURA_ALPHA: float = 0.22
const AURA_TEX_SIZE: int = 64

var _aura_visual: Sprite2D

func _ready() -> void:
	super._ready()
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	# Persistent low-opacity aura sprite (built once, just toggled/scaled,
	# not spawned per-heal) — same technique elana.gd uses for its own
	# always-on buff auras like the Life Barrier ring: a soft radial-gradient
	# GradientTexture2D on a Sprite2D, sized via `scale` to match heal_radius.
	_aura_visual = Sprite2D.new()
	_aura_visual.texture = _make_aura_texture()
	_aura_visual.modulate = Color(0.3, 1.0, 0.4, AURA_ALPHA)
	_aura_visual.z_index = -1
	var aura_scale = (heal_radius * 2.0) / float(AURA_TEX_SIZE)
	_aura_visual.scale = Vector2(aura_scale, aura_scale)
	add_child(_aura_visual)

func _make_aura_texture() -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = AURA_TEX_SIZE
	tex.height = AURA_TEX_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	return tex

func _move(delta: float) -> void:
	_tick_heal_aura(delta)
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= flee_range:
		var away = (global_position - elana.global_position).normalized()
		velocity = away * flee_speed
		direction = 1 if away.x >= 0.0 else -1
		return
	velocity.x = speed * direction
	velocity.y = sin(hover_time * 2.0) * 25.0
	if position.x > start_position.x + patrol_range:
		direction = -1
	elif position.x < start_position.x - patrol_range:
		direction = 1

func _tick_heal_aura(delta: float) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		var hp = enemy.get("hp")
		var emax = enemy.get("max_hp")
		if hp == null or emax == null or hp <= 0.0 or hp >= float(emax):
			continue
		if global_position.distance_to(enemy.global_position) > heal_radius:
			continue
		enemy.hp = min(float(emax), hp + heal_rate * delta)
