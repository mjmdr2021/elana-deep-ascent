extends "res://enemy.gd"

# Swells and explodes — either by closing to contact range on its own
# (self-detonate) or immediately when killed by a hit (via the generic
# on_death() hook hit_handler.gd calls, same mechanism Splitter uses).
# The AOE damage check bypasses AttackZone/HitHandler entirely and instead
# reuses the same "distance from a point" pattern elana.gd's plunge attack
# uses, since this is a burst around a point, not a directional hitbox.
@export var detonate_range: float = 10.0
@export var swell_time: float = 0.5
@export var explosion_radius: float = 50.0
@export var explosion_damage_mult: float = 2.0
const SWELL_TINT: Color = Color(1.8, 0.5, 0.5)
const SWELL_FLASH_TINT: Color = Color(3.0, 3.0, 3.0)
const BLINK_INTERVAL: float = 0.08

enum ExplodeState { NORMAL, SWELLING }
var _explode_state: ExplodeState = ExplodeState.NORMAL
var _swell_timer: float = 0.0
var _has_exploded: bool = false
var _swell_tween: Tween = null

func _ready() -> void:
	super._ready()
	# No normal melee attack at all — explosion (proximity or on-death) is
	# its only way to hurt Elana, so the generic windup/_perform_attack()
	# cycle is disconnected the same way Burrower disconnects it.
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)

func _move(delta: float) -> void:
	if _has_exploded:
		return
	if _explode_state == ExplodeState.SWELLING:
		velocity.x = 0
		_swell_timer -= delta
		if _swell_timer <= 0.0:
			_explode()
		return
	super._move(delta)
	if target and global_position.distance_to(target.global_position) <= detonate_range:
		_explode_state = ExplodeState.SWELLING
		_swell_timer = swell_time
		_start_swell_blink()

func _start_swell_blink() -> void:
	_swell_tween = create_tween()
	_swell_tween.set_loops()
	_swell_tween.tween_property(self, "modulate", SWELL_FLASH_TINT, BLINK_INTERVAL / 2.0)
	_swell_tween.tween_property(self, "modulate", SWELL_TINT, BLINK_INTERVAL / 2.0)

# Proximity self-detonate — not yet dead, so this needs to actually kill
# itself via HitHandler (grants XP, marks removed, queue_frees) after the
# blast lands. on_death() below no-ops once _has_exploded is set, so this
# doesn't loop back into a second explosion.
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true
	if _swell_tween:
		_swell_tween.kill()
	_deal_explosion_damage()
	hp = 0
	if is_instance_valid($HitHandler):
		$HitHandler._die()

# Death hook — called by hit_handler.gd's _die() when a weapon/spell kill
# happens before proximity ever triggered the swell.
func on_death() -> void:
	if _has_exploded:
		return
	_has_exploded = true
	if _swell_tween:
		_swell_tween.kill()
	_deal_explosion_damage()

func _deal_explosion_damage() -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana and elana.global_position.distance_to(global_position) <= explosion_radius:
		elana.take_damage(int(attack_damage * explosion_damage_mult), false, self)
		if elana.has_method("add_camera_trauma"):
			elana.add_camera_trauma(0.5)
	_spawn_explosion_visual()

func _spawn_explosion_visual() -> void:
	var poly = Polygon2D.new()
	poly.color = Color(1.0, 0.35, 0.1, 0.5)
	var pts := PackedVector2Array()
	for i in 24:
		var a = (float(i) / 24.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * explosion_radius)
	poly.polygon = pts
	poly.global_position = global_position
	poly.z_index = 3
	get_parent().add_child(poly)
	var tween = get_tree().create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.4)
	tween.tween_callback(poly.queue_free)
