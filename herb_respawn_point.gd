extends "res://player_proximity_area.gd"

const READY_TEXTURE = preload("res://herb-respawn.png")
const COOLDOWN_TEXTURE = preload("res://herb-respawn-cd.png")

# Proper-name dropdown in the Inspector instead of hand-typing the item ID —
# same pattern as ore_node.gd's OreType. Maps 1:1 to GameData.HERB_REGISTRY's
# keys, translated in _process() so the rest of the game (inventory, HUD
# tooltips, GameData) is untouched and keeps using the existing item ID strings.
enum HerbType { FIRE, FROST, ELEC, AGILITY, HEAL, POWER }
const HERB_TYPE_IDS: Dictionary = {
	HerbType.FIRE: "herbElementalFire",
	HerbType.FROST: "herbElementalFrost",
	HerbType.ELEC: "herbElementalElec",
	HerbType.AGILITY: "herbAgility",
	HerbType.HEAL: "herbHeal",
	HerbType.POWER: "herbPower",
}

@export var herb_type: HerbType = HerbType.AGILITY
@export var short_cooldown: float = 15.0
@export var long_cooldown: float = 300.0
@export var batch_size: int = 10
# Set true on exactly one herb node (whichever Elana meets first) to show a
# one-shot "E to pickup" hint while she's standing near it. Never shows again
# once she's actually picked up any herb, anywhere.
@export var show_pickup_hint: bool = false

var _available: bool = true
var _cooldown_timer: float = 0.0
var _picks_this_batch: int = 0

func _ready():
	super._ready()
	$Sprite2D.texture = READY_TEXTURE

func _process(delta):
	_update_pickup_hint()
	if not _available:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_available = true
			$Sprite2D.texture = READY_TEXTURE
		return

	if player_inside and player and Input.is_action_just_pressed("interact"):
		player.pick_up(HERB_TYPE_IDS[herb_type])
		if not GameData.herb_pickup_hint_shown:
			GameData.herb_pickup_hint_shown = true
			HUD.hide_prompt("herb_pickup_hint")
		_picks_this_batch += 1
		_available = false
		$Sprite2D.texture = COOLDOWN_TEXTURE
		if _picks_this_batch >= batch_size:
			_picks_this_batch = 0
			_cooldown_timer = long_cooldown
		else:
			_cooldown_timer = short_cooldown

func _update_pickup_hint() -> void:
	if not show_pickup_hint or GameData.herb_pickup_hint_shown:
		return
	if player_inside:
		HUD.show_prompt("E to pickup", self, "herb_pickup_hint", Vector2(0, -16))
	else:
		HUD.hide_prompt("herb_pickup_hint")
