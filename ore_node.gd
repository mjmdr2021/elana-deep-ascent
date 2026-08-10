extends StaticBody2D

# Proper-name dropdown in the Inspector instead of hand-typing "ore1".."ore4"
# — OreType maps 1:1 to GameData.ORE_REGISTRY's keys, translated in
# drop_ores() so the rest of the game (inventory, shop, GameData) is
# untouched and keeps using the existing item ID strings.
enum OreType { SWORD, CHAIN_CLAW, SPEAR, WARHAMMER }
const ORE_TYPE_IDS: Dictionary = {
	OreType.SWORD: "ore1",
	OreType.CHAIN_CLAW: "ore2",
	OreType.SPEAR: "ore3",
	OreType.WARHAMMER: "ore4",
}

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

func _ready():
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	original_color = $ColorRect.color
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
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

func on_elemental_hit(_element: String, hit_direction: int, damage: int) -> void:
	on_hit(hit_direction, damage, true)

func on_hit(hit_direction: int, damage: int, is_magic: bool = false) -> void:
	if hp <= 0:
		return
	if show_break_hint and not GameData.ore_break_hint_shown:
		GameData.ore_break_hint_shown = true
		HUD.hide_prompt("ore_break_hint")
	hp -= damage
	GameData.spawn_damage_number(damage, global_position)
	if hp <= 0:
		GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
		drop_ores()
		queue_free()
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

func drop_ores():
	var item_id: String = ORE_TYPE_IDS[ore_type]
	for i in 3:
		var piece = ORE_PIECE.instantiate()
		piece.ore_type = item_id
		piece.position = global_position + Vector2(randf_range(-10, 10), 0)
		piece.linear_velocity = Vector2(randf_range(-120, 120), randf_range(-300, -200))
		get_parent().call_deferred("add_child", piece)
