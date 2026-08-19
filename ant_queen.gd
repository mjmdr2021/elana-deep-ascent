extends "res://enemy.gd"

# Mini-boss — Ant Queen. 128x128, stationary — never chases or attacks
# directly, all her threat comes from what she summons. AggroZone's own
# handler is overridden below to a full no-op so `target` never gets set —
# enemy.gd's _move() only falls through to its STATIONARY branch when
# target is null (the chase branch takes priority over enemy_type whenever
# target IS set), so setting enemy_type alone wouldn't actually be enough
# to guarantee she never moves.
#
# - Eggs: lays one ant_egg.tscn near herself every egg_lay_interval seconds,
#   only while Elana's within egg_vicinity_radius and fewer than max_eggs are
#   already out there. Each egg has its own small hp pool and hatches into a
#   Swarmer if not destroyed — its hatch timer only counts down while Elana's
#   within egg_hatch_vicinity_radius of the QUEEN (not the egg), so eggs from
#   an ignored queen just sit banked instead of hatching offscreen. See
#   ant_egg.gd, same "destroy it or it hatches" shape as hollowfang_spit.gd's
#   landed spits, plus the vicinity gate.
# - Harden: every harden_cooldown seconds, unconditionally grants herself
#   armor_max_hp of "armor". While armor_hp > 0, modify_incoming_damage()
#   (the same generic hit_handler.gd hook shield_bearer.gd uses for its
#   shield) fully absorbs every hit into the armor pool instead of her real
#   hp, returning 0 — no partial spillover onto real hp the same hit armor
#   breaks on, the NEXT hit is what starts touching real hp again.
# - At <=50% and <=25% hp (once each, permanently), spawns an extra
#   shellback.tscn near herself as reinforcement — independent of Harden
#   and eggs, both can be active at once.

@export var egg_lay_interval: float = 3.0
# Eggs only actually lay while Elana's within this range — the timer still
# ticks/resets on schedule regardless, it just skips laying if she's out of
# range when it fires (checked again next interval, no catch-up/backlog).
@export var egg_vicinity_radius: float = 250.0
@export var egg_hatch_time: float = 10.0
# Hatch timer only ticks while Elana is this close to the QUEEN (not the
# egg) — copied onto every egg she lays, same as egg_hatch_time.
@export var egg_hatch_vicinity_radius: float = 30.0
@export var max_eggs: int = 10
# Random X range (either side of her) eggs can land within along the ground
# — a fresh roll each time, not a fixed spot every egg.
@export var egg_lay_spread: float = 80.0
@export var harden_cooldown: float = 12.0
@export var armor_max_hp: float = 150.0
@export var reinforcement_spawn_radius: float = 60.0

const EGG_SCENE = preload("res://ant_egg.tscn")
const SHELLBACK_SCENE = preload("res://shellback.tscn")
const HARDEN_TINT: Color = Color(1.6, 1.6, 0.6, 1.0)

var armor_hp: float = 0.0
var _egg_timer: float = 0.0
var _harden_timer: float = 0.0
var _base_modulate: Color
var _spawned_half_hp_reinforcement: bool = false
var _spawned_quarter_hp_reinforcement: bool = false

func _ready() -> void:
	enemy_type = GameData.EnemyType.STATIONARY
	super._ready()
	_base_modulate = modulate
	_egg_timer = egg_lay_interval
	_harden_timer = harden_cooldown

# base_enemy.gd's shared hp_regen is gated by regen_delay_timer, which any
# hit (hit_handler.gd) or burn/poison tick resets to 3s, pausing regen
# until it expires. Zeroing that delay out every frame before the base
# logic runs means it can never actually gate her regen, regardless of
# what set it — reuses the existing hp_regen application math (see
# ant_queen.tscn's hp_regen = 5) rather than duplicating it here.
func _tick_timers(delta: float) -> void:
	regen_delay_timer = 0.0
	super._tick_timers(delta)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_eggs(delta)
	_tick_harden(delta)
	_check_reinforcement_thresholds()

func _tick_eggs(delta: float) -> void:
	_egg_timer -= delta
	if _egg_timer <= 0.0:
		_egg_timer = egg_lay_interval
		if not _player_in_egg_vicinity():
			print("[ant_queen] egg timer fired but player out of vicinity range (", egg_vicinity_radius, ")")
		elif _own_eggs().size() >= max_eggs:
			print("[ant_queen] egg timer fired but egg cap (", max_eggs, ") already reached")
		else:
			_lay_egg()

func _player_in_egg_vicinity() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	return player != null and global_position.distance_to(player.global_position) <= egg_vicinity_radius

# Scoped to eggs THIS queen laid (egg.queen == self), not every egg in the
# scene — the global "ant_eggs" group check used to count every queen's
# eggs against every queen's own max_eggs cap, so a second Ant Queen placed
# in the same scene would have had her laying silently throttled by the
# first queen's eggs. Only one queen exists in full_map.tscn today, so this
# was latent, but @export var max_eggs living on each queen instance already
# implied a per-queen cap. Also reused by on_death() below to clean up
# exactly this queen's own leftover eggs, not a future queen's.
func _own_eggs() -> Array:
	return get_tree().get_nodes_in_group("ant_eggs").filter(func(egg): return egg.queen == self)

const EGG_SPAWN_ATTEMPTS: int = 6
# The terrain-clearance check below is offset this far ABOVE the candidate's
# actual Y (her own bottom edge / ground level) rather than checking exactly
# on it — a point query sitting precisely on the boundary where her own
# collision meets the floor she's standing on can register as "inside" the
# terrain shape (inclusive edge behavior), which would silently fail every
# single attempt, every time, and eggs would just never lay at all.
const EGG_GROUND_CHECK_MARGIN: float = 4.0

# Capped at max_eggs concurrent (checked by the caller before this ever
# runs) — lays on schedule otherwise. Y is her bottom edge (derived from the
# actual collision shape's height, not a hardcoded offset) — ground level,
# not dead-center. X is randomized within egg_lay_spread each time, not a
# fixed spot every egg — terrain-checked so that randomization can't drop
# one inside a wall.
func _lay_egg() -> void:
	var half_height: float = ($CollisionShape2D.shape as RectangleShape2D).size.y / 2.0
	var spawn_global: Vector2 = _find_clear_egg_spot(half_height)
	if spawn_global == Vector2.INF:
		return  # every attempt landed in terrain this cycle — try again next interval
	var egg = EGG_SCENE.instantiate()
	egg.hatch_time = egg_hatch_time
	egg.hatch_vicinity_radius = egg_hatch_vicinity_radius
	egg.queen = self
	# get_parent().to_local(...) — NOT self.to_local(...). The egg becomes a
	# child of get_parent() (a sibling of the Queen), not a child of the
	# Queen itself, so its local space needs to be relative to that same
	# shared parent — same pattern hollowfang.gd's rocks/spits/spikes use.
	egg.position = get_parent().to_local(spawn_global)
	egg.skip_removed_check = true
	get_parent().call_deferred("add_child", egg)

# Same terrain-layer convention used elsewhere (e.g. hollowfang_spike.gd's
# collision_mask = 1) — rerolls the random X a few times rather than ever
# committing to a spot that's inside solid geometry.
func _find_clear_egg_spot(half_height: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	for i in EGG_SPAWN_ATTEMPTS:
		var offset_x: float = randf_range(-egg_lay_spread, egg_lay_spread)
		var candidate: Vector2 = global_position + Vector2(offset_x, half_height)
		var query := PhysicsPointQueryParameters2D.new()
		# Checked EGG_GROUND_CHECK_MARGIN px above candidate itself — see the
		# constant's comment above. candidate (the actual returned/spawned
		# position) stays exactly at true ground level either way.
		query.position = candidate - Vector2(0, EGG_GROUND_CHECK_MARGIN)
		query.collision_mask = 1  # terrain
		if space.intersect_point(query, 1).is_empty():
			return candidate
	print("[ant_queen] _find_clear_egg_spot: all ", EGG_SPAWN_ATTEMPTS, " attempts hit terrain")
	return Vector2.INF

# Generic hit_handler.gd hook (any enemy can implement this to react to its
# own death) — permanent reward, not tied to the mandatory-boss Blessing
# track: halves incoming damage from anything tagged "hazards" from here on
# (see GameData.ant_queen_defeated / elana.gd's take_damage()).
func on_death() -> void:
	GameData.ant_queen_defeated = true
	GameData.spawn_float_text("Hazard Resist +50%!", global_position, Color(0.9, 0.8, 0.3))
	# Any of her own eggs still around get freed with her — an egg's hatch
	# timer only progresses while its queen reference is valid (see
	# ant_egg.gd's _player_in_hatch_vicinity()), so leaving them here would
	# strand them permanently un-hatchable instead of resolving the
	# "destroy it or it hatches" tension her death already settled.
	for egg in _own_eggs():
		egg.queue_free()

func _tick_harden(delta: float) -> void:
	_harden_timer -= delta
	if _harden_timer <= 0.0:
		_harden_timer = harden_cooldown
		_trigger_harden()

func _trigger_harden() -> void:
	armor_hp = armor_max_hp
	modulate = HARDEN_TINT

func _break_harden() -> void:
	armor_hp = 0.0
	modulate = _base_modulate

# Generic hit_handler.gd hook, same one shield_bearer.gd uses for its
# shield — fully absorbs into armor_hp instead of a partial reduction.
func modify_incoming_damage(_hit_direction: int, damage: int) -> int:
	if armor_hp > 0.0:
		armor_hp -= damage
		if armor_hp <= 0.0:
			_break_harden()
		return 0
	return damage

func _check_reinforcement_thresholds() -> void:
	if not _spawned_half_hp_reinforcement and hp <= max_hp * 0.5:
		_spawned_half_hp_reinforcement = true
		_spawn_shellback()
	if not _spawned_quarter_hp_reinforcement and hp <= max_hp * 0.25:
		_spawned_quarter_hp_reinforcement = true
		_spawn_shellback()

func _spawn_shellback() -> void:
	var shellback = SHELLBACK_SCENE.instantiate()
	var angle = randf() * TAU
	var dist = randf() * reinforcement_spawn_radius
	shellback.position = position + Vector2(cos(angle), sin(angle)) * dist
	shellback.skip_removed_check = true
	get_parent().call_deferred("add_child", shellback)

# Never chases — see the file-level comment for why enemy_type alone isn't
# enough on its own to guarantee this.
func _on_aggro_zone_body_entered(_body: Node) -> void:
	pass
