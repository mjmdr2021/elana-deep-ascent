extends "res://flying_enemy.gd"

# Never aggros or chases (AggroZone disconnected, so target can never get
# set) — just floats around on its own via flying_enemy.gd's unmodified
# patrol/hover behavior, slowed way down via `speed` on the .tscn. Telegraphed
# AOE pulse on a repeating timer — brightens (telegraph_time), then releases
# a damage pulse around itself and, in the same beat, tells every other
# Spark Jelly within chain_radius to start its own telegraph immediately (a
# chain reaction — fighting a cluster means eating several pulses close
# together instead of one at a time). elec-immune via the normal
# fire_resist/frost_resist/elec_resist system on the .tscn.
#
# Water-bound: ticks damage every out_of_water_tick_interval while not on a
# "water"-tagged tile (see water_check.gd) — same rule as Spark Eel.
@export var pulse_interval: float = 3.0
@export var telegraph_time: float = 0.6
@export var pulse_radius: float = 50.0
@export var pulse_damage: int = 10
@export var chain_radius: float = 80.0
@export var out_of_water_tick_damage: int = 3
@export var out_of_water_tick_interval: float = 1.0
@export var bob_amplitude: float = 4.0
@export var bob_speed: float = 0.6
const TELEGRAPH_TINT: Color = Color(1.6, 1.6, 0.4, 1.0)

var _pulse_timer: float = 0.0
var _telegraphing: bool = false
var _telegraph_timer: float = 0.0
var _out_of_water_timer: float = 0.0

func _ready() -> void:
	super._ready()
	_pulse_timer = pulse_interval
	# The pulse is the only intended threat — disconnect the normal melee
	# windup-attack cycle so it can't also land 0-damage "hits" that
	# GameData.calc_damage()'s floor would still round up to 1 (same bug
	# class fixed earlier for the magma terrain tiles).
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	# No aggro/chase at all — target must never get set.
	if $AggroZone.body_entered.is_connected(_on_aggro_zone_body_entered):
		$AggroZone.body_entered.disconnect(_on_aggro_zone_body_entered)
	if $AggroZone.body_exited.is_connected(_on_aggro_zone_body_exited):
		$AggroZone.body_exited.disconnect(_on_aggro_zone_body_exited)

# Target is permanently null (AggroZone disconnected), so this fully
# replaces flying_enemy.gd's patrol/hover with its own much gentler drift
# instead of calling super — the shared _move() bobs vertically at a fixed
# 25px amplitude regardless of `speed` (which only scales the horizontal
# component), which is what was still reading as "fast" after slowing
# `speed` down alone.
func _move(_delta: float) -> void:
	velocity.x = speed * direction
	velocity.y = sin(hover_time * bob_speed) * bob_amplitude
	if position.x > start_position.x + patrol_range:
		direction = -1
	elif position.x < start_position.x - patrol_range:
		direction = 1

# 2026-09-05, real sprite art added -- the generic idle/walk/attack
# auto-switching in base_enemy.gd's own _update_sprite() only ever
# triggers "attack" off attack_windup_timer/attack_anim_timer, which this
# enemy never sets (its own AttackZone windup-attack cycle is disconnected
# in _ready(), the pulse is its only real threat) -- so that generic logic
# would just force "idle" back every single frame regardless of what
# trigger_chain_pulse()/_release_pulse() below try to set, same class of
# bug found on Mantrap. Takes manual control instead, keeping only the
# facing-flip the base version also does.
func _update_sprite() -> void:
	if _sprite == null:
		return
	_sprite.flip_h = direction > 0

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	_tick_water(delta)
	if _telegraphing:
		_telegraph_timer -= delta
		if _telegraph_timer <= 0.0:
			_release_pulse()
		return
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		trigger_chain_pulse()

func _tick_water(delta: float) -> void:
	# 2026-09-06, same real bug found on Spark Eel (user: "why does eel die
	# so quick when touching a bit air") -- this copy-pasted the identical
	# defect: reset to 0.0 while in water, but 0.0 is also the "timer's up"
	# trigger the countdown checks (<= 0.0), so the very first frame back
	# out of water fired an instant damage tick instead of waiting the full
	# out_of_water_tick_interval. Re-arms to the full interval instead, same
	# as the reset-on-tick line below.
	if WaterCheck.is_water(global_position, get_tree()):
		_out_of_water_timer = out_of_water_tick_interval
		return
	_out_of_water_timer -= delta
	if _out_of_water_timer <= 0.0:
		_out_of_water_timer = out_of_water_tick_interval
		hp -= out_of_water_tick_damage
		GameData.spawn_damage_number(out_of_water_tick_damage, global_position)
		if hp <= 0 and is_instance_valid($HitHandler):
			$HitHandler._die()

# Public — called on itself (pulse_timer running out) and by a nearby
# Spark Jelly's own _release_pulse() to chain-trigger this one early.
func trigger_chain_pulse() -> void:
	if _telegraphing:
		return
	_telegraphing = true
	_telegraph_timer = telegraph_time
	modulate = TELEGRAPH_TINT
	if _sprite:
		_sprite.play("attack")

func _release_pulse() -> void:
	_telegraphing = false
	_pulse_timer = pulse_interval
	modulate = Color.WHITE
	if _sprite:
		_sprite.play("idle")
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= pulse_radius:
		elana.take_damage(pulse_damage, true, self, "elec")
		# 2026-09-06, user explicit: "spark fly applies strong shock" -- the
		# elec-hit damage above doesn't itself carry a shock (that's a
		# separate call, same pattern Elemander/Voltangler/electrified water
		# already use), so wire it in here specifically with the longer
		# Strong Shock duration rather than the regular one those use.
		if elana.has_method("apply_shock"):
			elana.apply_shock(GameData.STRONG_SHOCK_STUN_DURATION)
	_spawn_pulse_visual()
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node):
			continue
		if node.has_method("trigger_chain_pulse") and global_position.distance_to(node.global_position) <= chain_radius:
			node.trigger_chain_pulse()

# hit_handler.gd's _die() calls this, then holds the node alive for a fixed
# 0.5s (its own _flash_hit() + a hard-coded create_timer(0.5)) before
# queue_free() -- the "death" animation on spark_jelly.tscn is deliberately
# 4 frames at speed 8.0 (0.5s exactly) to fill that same window.
func on_death() -> void:
	if _sprite:
		_sprite.play("death")

func _spawn_pulse_visual() -> void:
	var poly = Polygon2D.new()
	poly.color = Color(1.0, 0.95, 0.3, 0.45)
	var pts := PackedVector2Array()
	for i in 24:
		var a = (float(i) / 24.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * pulse_radius)
	poly.polygon = pts
	poly.global_position = global_position
	poly.z_index = 3
	get_parent().add_child(poly)
	var tween = get_tree().create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.4)
	tween.tween_callback(poly.queue_free)
