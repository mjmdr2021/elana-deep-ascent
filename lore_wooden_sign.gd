extends "res://player_proximity_area.gd"

# Readable world sign — same "system dialog" E-prompt style lore_notes.gd's
# pickup hint uses (HUD.show_prompt(), red-bordered box), except a sign is
# never consumed/removed like a note — it just re-shows its dialogue every
# time she reads it, same as talking to Moleman again.
const DialogueData = preload("res://dialogue_data.gd")

# Unique per placed instance (its own scene-tree name) so hide_prompt()
# can't cross-cancel a different sign's hint if two are ever near each other.
var _prompt_id: String = ""

func _ready() -> void:
	super._ready()
	_prompt_id = "lore_wooden_sign_" + name

func _process(_delta: float) -> void:
	_update_read_hint()
	if player_inside and player and Input.is_action_just_pressed("interact") and not GameData.in_cutscene:
		_read()

func _update_read_hint() -> void:
	if player_inside:
		HUD.show_prompt("E to read", self, _prompt_id)
	else:
		HUD.hide_prompt(_prompt_id)

func _read() -> void:
	HUD.hide_prompt(_prompt_id)
	HUD.show_dialogue(DialogueData.LORE_WOODEN_SIGN, true)
