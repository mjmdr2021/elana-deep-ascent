extends Area2D

# Graniteus's Boulder Hurl projectile -- a real ballistic arc (same
# peak-height -> launch-velocity -> flight-time math cobblecroak.gd's own
# Leap Drop uses), aimed at target_position sampled once at throw time
# (Elana's position when thrown), not homing.
#
# 2026-08-24, reworked per user: "boulder toss should just continue the
# trajectory until hits a terrain. the location target is just
# trajectory" -- target_position now ONLY feeds the initial launch-angle
# math (_solve_arc()'s dx); it's no longer a height it stops at. Lands via
# real terrain collision instead (collision_mask = terrain layer,
# body_entered), same model wyrmbat_tailspike.gd uses -- keeps arcing under
# gravity past wherever Elana originally stood until it actually hits
# ground, rather than stopping mid-air at her old position or sailing
# through terrain that happens to sit below that height.
#
# Player-hit stays a proximity check (established convention for thrown/
# arcing projectiles in this codebase, not real Area2D overlap) -- but the
# radius was too small relative to the boulder's own visual size to
# reliably land a hit (2026-08-24, user report: "elana isnt damaged when
# hit by those thrown boulder"), bumped up accordingly.
#
# 2026-08-24, user: "when boudler hits elana, add knock back when hit, and
# explodes there into ores." Unlike TailSpike (deliberately passes through
# her), the boulder now stops dead on a player hit -- lands immediately at
# that exact point (same _land()/_spill_ore() as a terrain hit) instead of
# continuing on to wherever it would've otherwise landed.
#
# Breaks and spills real ore1-4 pieces on landing (2026-08-24, user
# explicit: "Real ore items") -- reuses ore_piece.tscn exactly as
# ore_node.gd's own drop_ores() does, just with a random type per piece
# instead of one fixed type per node.
#
# 2026-08-25, cross-boss interaction #4 from the original twin-boss spec,
# user explicit: "the boulder throw when in contact with bat will flap
# wings to shoot the boulder fast downwards but location is random and
# explosion when hitting ground is bigger. knockback is greater." If this
# ever touches Wyrmbat mid-flight, she flaps her wings (flap_wings(), a
# cosmetic flash on her end) and the boulder redirects to a fast
# straight-line shot AT ELANA'S CURRENT POSITION (2026-08-25, user
# correction: "not straight downward, does a straight velocity to elanas
# position instead" -- not a blind vertical drop) from wherever Wyrmbat
# currently happens to be -- her own combat-fly position varies every
# time, which IS the "random location" from the spec, not an extra
# randomization layered on top. Lands with a real AoE explosion (the
# normal landing never had one at all) bigger and harder-hitting than the
# boulder's own regular mid-flight contact damage/knockback.
#
# 2026-08-25, reworked the contact detection itself from a per-frame
# proximity poll to real collision (user: "why not make a collision box
# below the bat, and when collided, does the flap redirect" -- same
# real-collision preference already applied to the Boulder Roll/TailSpike
# interaction earlier). This boulder now sits on its own dedicated
# collision_layer (64) purely so Wyrmbat's own BoulderRedirectZone
# (wyrmbat.tscn/.gd) can pick it up via a real area_entered signal --
# nothing else masks against that layer, so no risk of colliding with
# terrain/player/other hazards by accident. redirect_toward() is now
# public, called BY that zone instead of this script polling for her.

const HIT_RADIUS: float = 32.0
const REDIRECT_DROP_SPEED: float = 900.0
const ORE_PIECE: PackedScene = preload("res://ore_piece.tscn")
const ORE_TYPES: Array[String] = ["ore1", "ore2", "ore3", "ore4"]

@export var target_position: Vector2 = Vector2.ZERO
@export var peak_height: float = 300.0  # matches graniteus.gd's own boulder_hurl_peak_height default
@export var damage: int = 20
@export var ore_piece_count: int = 3
@export var lifetime: float = 3.0  # safety cap if it never hits terrain
@export var knockback_x: float = 350.0
@export var knockback_y: float = -200.0
@export var knockback_duration: float = 0.4
@export var redirect_explosion_radius: float = 100.0
@export var redirect_explosion_damage: int = 35
@export var redirect_knockback_x: float = 550.0
@export var redirect_knockback_y: float = -320.0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _velocity: Vector2 = Vector2.ZERO
var _hit_player: bool = false
var _landed: bool = false
var _redirected: bool = false

func _ready() -> void:
	add_to_group("enemy_projectiles")
	add_to_group("hazards")
	collision_layer = 64  # dedicated layer -- only Wyrmbat's BoulderRedirectZone masks against this
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)
	_solve_arc()

func _solve_arc() -> void:
	var dx: float = target_position.x - global_position.x
	var launch_speed_y: float = sqrt(2.0 * _gravity * peak_height)
	var flight_time: float = 2.0 * launch_speed_y / _gravity
	var launch_speed_x: float = dx / flight_time if flight_time > 0.0 else 0.0
	_velocity = Vector2(launch_speed_x, -launch_speed_y)

func _physics_process(delta: float) -> void:
	if _landed:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_land()
		return
	if not _redirected:
		_velocity.y += _gravity * delta
	global_position += _velocity * delta
	if not _redirected and not _hit_player:
		var elana = get_tree().get_first_node_in_group("player")
		if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
			_hit_player = true
			if elana.has_method("take_damage"):
				elana.take_damage(damage, false, self)
			if elana.has_method("apply_knockback"):
				var away: float = sign(elana.global_position.x - global_position.x)
				elana.apply_knockback(Vector2(away * knockback_x, knockback_y), knockback_duration)
			_land()
			return

# Called by Wyrmbat's own BoulderRedirectZone (wyrmbat.gd) on real
# area_entered contact -- fires as a straight-line shot toward wherever
# Elana currently is (sampled once here, not homing) rather than a blind
# straight-down drop (2026-08-25, user correction: "not straight downward,
# does a straight velocity to elanas position instead").
func redirect_toward(target_pos: Vector2) -> void:
	if _redirected or _landed:
		return
	_redirected = true
	var dir: Vector2 = target_pos - global_position
	# Degenerate case (target sampled exactly on top of the boulder) --
	# normalized() of a zero vector stays zero, which would leave her
	# motionless instead of redirected. Falls back to straight down.
	_velocity = dir.normalized() * REDIRECT_DROP_SPEED if dir != Vector2.ZERO else Vector2(0.0, REDIRECT_DROP_SPEED)

func _on_body_entered(_body: Node) -> void:
	_land()

func _land() -> void:
	if _landed:
		return
	_landed = true
	set_physics_process(false)
	if _redirected:
		_explode()
	_spill_ore()
	queue_free()

# Only reachable via the Wyrmbat-redirect path -- the normal landing never
# had an AoE explosion at all, matching the spec's "explosion when hitting
# ground is bigger" (bigger than nothing, in the normal case) and "knockback
# is greater" (greater than the boulder's own regular mid-flight contact
# knockback above).
func _explode() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var elana = tree.get_first_node_in_group("player")
	if elana == null:
		return
	if global_position.distance_to(elana.global_position) <= redirect_explosion_radius:
		if elana.has_method("take_damage"):
			elana.take_damage(redirect_explosion_damage, false, self)
		if elana.has_method("apply_knockback"):
			var away: float = sign(elana.global_position.x - global_position.x)
			elana.apply_knockback(Vector2(away * redirect_knockback_x, redirect_knockback_y), knockback_duration)

func _spill_ore() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in ore_piece_count:
		var piece = ORE_PIECE.instantiate()
		piece.ore_type = ORE_TYPES[randi() % ORE_TYPES.size()]
		piece.position = global_position + Vector2(randf_range(-10, 10), 0)
		piece.linear_velocity = Vector2(randf_range(-120, 120), randf_range(-300, -200))
		parent.call_deferred("add_child", piece)
