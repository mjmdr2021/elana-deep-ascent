extends "res://player_proximity_area.gd"

# Order must not change — scenes store the enum value as an int. RANDOM
# added at the end for the same reason — inserting it earlier would shift
# every already-placed herb's stored index onto the wrong type.
enum HerbType { HERB, ELEMENTAL_FIRE, ELEMENTAL_FROST, ELEMENTAL_ELEC, AGILITY, HEAL, POWER, RANDOM }

const HERB_ID = {
	HerbType.HERB: "herb",
	HerbType.ELEMENTAL_FIRE: "herbElementalFire",
	HerbType.ELEMENTAL_FROST: "herbElementalFrost",
	HerbType.ELEMENTAL_ELEC: "herbElementalElec",
	HerbType.AGILITY: "herbAgility",
	HerbType.HEAL: "herbHeal",
	HerbType.POWER: "herbPower",
}
# HERB..POWER only — RANDOM itself isn't a real herb, just a selector
# resolved once in _ready().
const RANDOM_CHOICE_COUNT: int = 7

@export var herb_type: HerbType = HerbType.HERB
# Set true on exactly one herb (whichever Elana meets first) to show a
# one-shot "E to pickup" hint while she's standing near it. Never shows
# again once she's actually picked up any herb, anywhere.
@export var show_pickup_hint: bool = false

func _ready():
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	# Rolled once (cached in GameData, keyed by scene+node name) rather than
	# every time this node's _ready() runs — same reason ore_node.gd does
	# this — otherwise re-entering the room would silently re-roll a
	# different herb each visit instead of staying fixed until New Game.
	if herb_type == HerbType.RANDOM:
		var scene_path = get_tree().current_scene.scene_file_path
		herb_type = GameData.get_random_choice(scene_path, name, RANDOM_CHOICE_COUNT) as HerbType
	super._ready()
	$AnimatedSprite2D.play("idle")

func _process(_delta):
	_update_pickup_hint()
	if player_inside and player and Input.is_action_just_pressed("interact"):
		GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
		player.pick_up(HERB_ID[herb_type])
		if not GameData.herb_pickup_hint_shown:
			GameData.herb_pickup_hint_shown = true
			HUD.hide_prompt("herb_pickup_hint")
		queue_free()

func _update_pickup_hint() -> void:
	if not show_pickup_hint or GameData.herb_pickup_hint_shown:
		return
	if player_inside:
		HUD.show_prompt("E to pickup", self, "herb_pickup_hint", Vector2(0, -16))
	else:
		HUD.hide_prompt("herb_pickup_hint")
