extends StaticBody2D

# Broodspawner's web strand — connects a pair of WebAnchorPointNa/Nb markers
# (broodspawner.tscn) into a single thin destructible line. Destroying all 4
# strands (see boss_ref below) triggers her DOWN phase. Replaces the earlier
# "4 separate point blobs" web_anchor.gd/.tscn (2026-08-20, per the user's
# "8 points paired into 4 strands" proposition) — same destructible-HP shape
# otherwise (no weapon restriction, no regen, one-time gate, not a
# repeatable DPS check).
#
# Not physically solid to anyone (2026-08-20, user request): root
# collision_layer/mask = 0 in web_strand.tscn. Without it, the default
# StaticBody2D layer (1, the shared terrain layer) would let Elana and
# enemies bump into it like a wall. The separate Hurtbox child Area2D below
# (layer 4/mask 8, same convention every other hittable object in this
# project uses) is what actually detects weapon hits — untouched by this,
# so it's still fully hittable despite blocking nothing physically.

@export var max_hp: int = 25
@export var thickness: float = 5.0

var hp: int
# Set by broodspawner.gd right after spawning each strand — notified via
# on_anchor_destroyed() below instead of the boss having to poll/count
# get_tree().get_nodes_in_group() every frame.
var boss_ref: Node = null

@onready var _color_rect: ColorRect = $ColorRect
var _base_color: Color

func _ready() -> void:
	hp = max_hp
	_base_color = _color_rect.color

# Called by broodspawner.gd right after instantiate(), BEFORE this node is
# added to the tree — uses direct get_node() lookups rather than @onready
# vars, since those only resolve once _ready() runs (i.e. once actually in
# the tree), which hasn't happened yet at this point. position/rotation are
# set by the caller separately; this only sizes the shapes/visual to match
# however far apart the two endpoint markers currently are.
func set_length(length: float) -> void:
	var size := Vector2(length, thickness)
	var body_shape: CollisionShape2D = get_node("CollisionShape2D")
	var hurt_shape: CollisionShape2D = get_node("Hurtbox/CollisionShape2D")
	var color_rect: ColorRect = get_node("ColorRect")
	body_shape.shape.size = size
	hurt_shape.shape.size = size
	color_rect.offset_left = -length / 2.0
	color_rect.offset_right = length / 2.0
	color_rect.offset_top = -thickness / 2.0
	color_rect.offset_bottom = thickness / 2.0

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

func on_hit(_hit_direction: int, damage: int, _is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	hp -= damage
	GameData.spawn_damage_number(damage, global_position)
	if hp <= 0:
		if boss_ref != null and boss_ref.has_method("on_anchor_destroyed"):
			boss_ref.on_anchor_destroyed()
		queue_free()
		return
	_flash_hit()

func _flash_hit() -> void:
	_color_rect.color = Color.WHITE
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self):
		_color_rect.color = _base_color
