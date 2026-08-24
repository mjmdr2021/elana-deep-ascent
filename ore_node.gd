extends StaticBody2D

# Proper-name dropdown in the Inspector instead of hand-typing "ore1".."ore4"
# — OreType maps 1:1 to GameData.ORE_REGISTRY's keys, translated in
# drop_ores() so the rest of the game (inventory, shop, GameData) is
# untouched and keeps using the existing item ID strings.
enum OreType { SWORD, CHAIN_CLAW, SPEAR, WARHAMMER, RANDOM }
const ORE_TYPE_IDS: Dictionary = {
	OreType.SWORD: "ore1",
	OreType.CHAIN_CLAW: "ore2",
	OreType.SPEAR: "ore3",
	OreType.WARHAMMER: "ore4",
}
# SWORD..WARHAMMER only — RANDOM itself isn't a real drop type, just a
# selector resolved once in _ready().
const RANDOM_CHOICE_COUNT: int = 4

@export var ore_type: OreType = OreType.SWORD
# Set true on exactly one ore node (whichever Elana meets first) to show a
# one-shot "Hit to Destroy" hint while she's standing near it. Never shows
# again once she's landed a hit on any ore node, anywhere.
@export var show_break_hint: bool = false
const HINT_RADIUS: float = 80.0

var hp = 30
var original_color: Color
var _flash_material: ShaderMaterial = null
const ORE_PIECE = preload("res://ore_piece.tscn")
# Cosmetic hop, triggered externally (2026-08-24, user: "make ores also
# jump on the wave from judgement") -- Graniteus's Mountain Judgement calls
# bounce() on any nearby ore node as its earth-mound wave passes through.
const BOUNCE_HEIGHT: float = 10.0
const BOUNCE_TIME: float = 0.15
var _sprite_rest_y: float = 0.0
var _bounce_tween: Tween = null

func _ready():
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	add_to_group("ore_nodes")
	# Rolled once (cached in GameData, keyed by scene+node name) rather than
	# every time this node's _ready() runs — otherwise re-entering the room
	# would silently re-roll a different ore type each visit within the same
	# playthrough instead of staying fixed until the next New Game.
	if ore_type == OreType.RANDOM:
		var scene_path = get_tree().current_scene.scene_file_path
		ore_type = GameData.get_random_choice(scene_path, name, RANDOM_CHOICE_COUNT) as OreType
	original_color = $ColorRect.color
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		_sprite_rest_y = sprite.position.y
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = preload("res://hit_flash.gdshader")
		sprite.material = _flash_material

func _process(_delta: float) -> void:
	if not show_break_hint or GameData.ore_break_hint_shown:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player != null and global_position.distance_to(player.global_position) <= HINT_RADIUS:
		HUD.show_prompt("Hit to Destroy", self, "ore_break_hint", Vector2(0, -16))
	else:
		HUD.hide_prompt("ore_break_hint")

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	if show_break_hint and not GameData.ore_break_hint_shown:
		GameData.ore_break_hint_shown = true
		HUD.hide_prompt("ore_break_hint")
	hp -= damage
	GameData.spawn_damage_number(damage, global_position)
	if hp <= 0:
		_on_threshold_reached()
		return
	if _flash_material != null:
		_flash_material.set_shader_parameter("flash_amount", 1.0)
	else:
		$ColorRect.color = Color.RED
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		if _flash_material != null:
			_flash_material.set_shader_parameter("flash_amount", 0.0)
		else:
			$ColorRect.color = original_color

# Override point for subclasses (e.g. ore_mine.gd) — same "extends + override
# one seam" pattern wood_debris.gd uses on vine_gate.gd's _is_valid_hit().
# Default behavior is the original ore node: break permanently.
func _on_threshold_reached() -> void:
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	drop_ores()
	queue_free()

# Purely cosmetic -- bounces the sprite up and back down, no gameplay
# effect. Animated via position, never scale, same "never scale sprites"
# rule the earth mound's own rise/recede already follows. Kills any
# in-flight bounce first and always tweens relative to the cached
# _sprite_rest_y (not the sprite's current position) -- several nearby
# earth mounds can each call this in quick succession as Mountain
# Judgement's wave passes through, and reading position.y fresh mid-bounce
# would let it drift further from rest with each overlapping call.
func bounce() -> void:
	var sprite = get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	sprite.position.y = _sprite_rest_y
	_bounce_tween = create_tween()
	_bounce_tween.tween_property(sprite, "position:y", _sprite_rest_y - BOUNCE_HEIGHT, BOUNCE_TIME * 0.5)
	_bounce_tween.tween_property(sprite, "position:y", _sprite_rest_y, BOUNCE_TIME * 0.5)

func drop_ores():
	var item_id: String = ORE_TYPE_IDS[ore_type]
	for i in 3:
		var piece = ORE_PIECE.instantiate()
		piece.ore_type = item_id
		piece.position = global_position + Vector2(randf_range(-10, 10), 0)
		piece.linear_velocity = Vector2(randf_range(-120, 120), randf_range(-300, -200))
		get_parent().call_deferred("add_child", piece)
