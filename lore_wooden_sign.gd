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
	# Gated the same as the interact check below — without this, the hint
	# ignored GameData.in_cutscene entirely and re-showed itself every
	# frame the dialogue box was open (she's still standing right next to
	# the sign, so player_inside stays true), fighting the one-time
	# HUD.hide_prompt() call _read() makes right when she presses E.
	if player_inside and not GameData.in_cutscene:
		HUD.show_prompt("E to read", self, _prompt_id)
	else:
		HUD.hide_prompt(_prompt_id)

func _read() -> void:
	HUD.hide_prompt(_prompt_id)
	HUD.show_dialogue(DialogueData.LORE_WOODEN_SIGN, true)
