extends Area2D

# Hollowfang's Eject Spikes projectile — fast, straight-line, no hatch
# behavior (unlike Spit Volley, this doesn't spawn anything on landing).
# Destructible mid-air, same "weapon/element both work" pattern every other
# destructible enemy projectile this session uses.
#
# Passes THROUGH Elana (damages her once, keeps flying — doesn't stop or
# despawn on that hit) but actually stops and lingers on terrain: sticks in
# place for TERRAIN_LINGER seconds before disappearing, rather than
# vanishing the instant it lands. On hit, also drags her further along the
# spike's own current heading and stuns her briefly — a real punish for
# standing in a spike's path instead of just chip damage. Deliberately NOT
# dragging toward the spike's original pre-fire random target (that point
# has no relation to which way the spike was actually traveling when it hit
# her — if it happened to sit behind her relative to the real flight path,
# she'd get yanked "backwards" relative to the hit; continuing the spike's
# real trajectory is always consistent with it instead).
const SPEED: float = 520.0
const HIT_RADIUS: float = 14.0
const TERRAIN_LINGER: float = 1.0
const DRAG_DURATION: float = 0.2
const DRAG_CONTINUE_DIST: float = 60.0
const STUN_DURATION: float = 1.0
@export var damage: int = 12
@export var hp: int = 4

var aim_direction: Vector2 = Vector2.RIGHT
var lifetime: float = 2.0
var _done: bool = false  # true once stuck in terrain — stops movement, not yet freed
var _hit_player: bool = false
# Spikes launch from the head while it's ducked in close to the boss's own
# (terrain-layer) body — same reason hollowfang_spit.gd excludes its own
# spawning body from terrain collision, see there for the full rationale.
var source: Node = null

func _ready() -> void:
	add_to_group("enemy_projectiles")
	add_to_group("hazards")  # Ant Queen's death reward halves damage from this group
	collision_layer = 0
	collision_mask = 1  # terrain
	body_entered.connect(_on_body_entered)
	rotation = aim_direction.angle()

func _physics_process(delta: float) -> void:
	if _done:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_land()
		return
	position += aim_direction * SPEED * delta
	if not _hit_player:
		var elana = get_tree().get_first_node_in_group("player")
		if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
			_hit_player = true
			elana.take_damage(damage, false, self)
			_drag_player_to_target(elana)
			# No _land() here — it keeps flying through her, doesn't stop.

# Stuns her and pulls her further along the spike's own current direction of
# travel — a real punish for standing in a spike's path. apply_drag_stun()
# handles wall collisions itself (pins her in place instead of dragging
# through terrain).
func _drag_player_to_target(elana: Node) -> void:
	if elana.has_method("apply_drag_stun"):
		var drag_target: Vector2 = global_position + aim_direction * DRAG_CONTINUE_DIST
		elana.apply_drag_stun(drag_target, DRAG_DURATION, STUN_DURATION)

func _on_body_entered(body: Node) -> void:
	# Not just `body == source` — Hollowfang's head has its own separate
	# solid body (HeadCollision) that spikes spawn right next to, see
	# hollowfang.gd's owns_body().
	if source != null and source.has_method("owns_body") and source.owns_body(body):
		return
	_land()

# Freezes in place (movement stops via the _done check above) rather than
# despawning immediately — lingers stuck in the terrain for a beat before
# actually disappearing.
func _land() -> void:
	if _done:
		return
	_done = true
	await get_tree().create_timer(TERRAIN_LINGER).timeout
	if is_instance_valid(self):
		queue_free()

func on_hit(_hit_direction: int, dmg: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if _done:
		return
	hp -= dmg
	if hp <= 0:
		_done = true
		queue_free()

func on_elemental_hit(_element: String, hit_direction: int, dmg: int, attacker: Node = null) -> void:
	on_hit(hit_direction, dmg, true, attacker)
