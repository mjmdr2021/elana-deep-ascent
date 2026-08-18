extends "res://player_proximity_area.gd"

# Readable world notes — pick up (E) to read, same "system dialog" prompt
# style herb.gd's own pickup hint uses (HUD.show_prompt(), red-bordered box),
# except this always shows while she's in range rather than herb's one-shot-
# per-playthrough hint — every note is its own individual pickup. note_type
# picks which dialogue this particular placed instance shows on pickup — add
# a new case to both the enum and _pick_up()'s match when a future note
# needs different content, same convention dialog_marker.gd's cutscene_type
# uses.
const DialogueData = preload("res://dialogue_data.gd")

enum NoteType { RITUAL_NODE_EXPLANATION }

@export var note_type: NoteType = NoteType.RITUAL_NODE_EXPLANATION

# Unique per placed instance (its own scene-tree name) so hide_prompt()
# can't cross-cancel a different note's hint if two are ever near each other.
var _prompt_id: String = ""

func _ready() -> void:
	super._ready()
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	_prompt_id = "lore_note_" + name

func _process(_delta: float) -> void:
	_update_pickup_hint()
	if player_inside and player and Input.is_action_just_pressed("interact") and not GameData.in_cutscene:
		_pick_up()

func _update_pickup_hint() -> void:
	if player_inside:
		HUD.show_prompt("E to pickup", self, _prompt_id)
	else:
		HUD.hide_prompt(_prompt_id)

func _pick_up() -> void:
	HUD.hide_prompt(_prompt_id)
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	# Goes straight into the main inventory, never a quickslot — it's a
	# collectible to read, not a consumable to use (see GameData.KEY_ITEM_
	# REGISTRY). item_id/display name/icon color registered in item_slot.gd's
	# ITEM_NAMES/ITEM_COLORS and hud.gd's ITEM_DESCRIPTIONS ("note1" →
	# "Note #1"). Add a new item_id there (and a new match arm below) when
	# a future NoteType needs its own inventory entry.
	match note_type:
		NoteType.RITUAL_NODE_EXPLANATION:
			GameData.add_item_to_inventory("note1")
			HUD.refresh_slots()
			HUD.show_dialogue(DialogueData.LORE_RITUAL_NODE_EXPLANATION, true)
	# Freed immediately — the dialogue box is its own independent screen-
	# space UI (HUD), not dependent on this node still existing to keep
	# playing out.
	queue_free()
