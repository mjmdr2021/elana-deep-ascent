extends Area2D

# Petrified Stone Being — grants Elana the Corruption Core quest and the air
# dash ability the first time she gets close. One-shot, tracked by
# GameData.stone_being_met so it never retriggers on later visits.
const DialogueData = preload("res://dialogue_data.gd")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if GameData.stone_being_met:
		return
	if not body.is_in_group("player"):
		return
	GameData.stone_being_met = true
	_start_cutscene(body)

func _start_cutscene(elana: Node) -> void:
	GameData.in_cutscene = true
	HUD.set_hud_visible(false)
	var glint = elana.get_node("Glint")

	HUD.show_dialogue(DialogueData.STONE_BEING_INTRO_A, false, {"Stone Being": self})
	await HUD.dialogue_finished

	# Staging — Elana glances left then right. Glint gets locked in place on
	# Elana's right for this beat so the glance doesn't drag her along with
	# the facing changes the way her normal dynamic follow would.
	GameData.glint_position_locked = true
	GameData.glint_lock_follows_facing = false
	glint.position = Vector2(18, -20)
	var original_facing = elana.facing
	elana.facing = -1
	await get_tree().create_timer(0.25).timeout
	elana.facing = 1
	await get_tree().create_timer(0.25).timeout
	elana.facing = original_facing
	GameData.glint_position_locked = false

	HUD.show_dialogue(DialogueData.STONE_BEING_INTRO_B, false, {"Stone Being": self})
	await HUD.dialogue_finished

	# Staging — Elana and Glint glow as the Stone Being's power settles in.
	# Persists through the whole reaction line, however long it takes the
	# player to advance it, and only cuts off right as the flash fires.
	elana.trigger_story_glow()
	glint.trigger_story_glow()

	HUD.show_dialogue(DialogueData.STONE_BEING_REACTION, false)
	await HUD.dialogue_finished

	elana.stop_story_glow()
	glint.stop_story_glow()
	await HUD.flash_screen(0.3)

	HUD.show_dialogue(DialogueData.STONE_BEING_POWER_GRANTED, false, {"Stone Being": self})
	await HUD.dialogue_finished

	GameData.air_dash_enabled = true

	HUD.show_dialogue(DialogueData.STONE_BEING_AIR_DASH_GRANT, false, {"Stone Being": self})
	await HUD.dialogue_finished

	GameData.in_cutscene = false
	GameData.received_stone_being_power = true
	HUD.set_hud_visible(true)

	# Acts as an implicit first checkpoint — reuses the exact same respawn
	# fields Ritual Nodes write to, so die()'s existing logic just naturally
	# respawns here until a real Ritual Node overwrites it. Only set if no
	# Ritual Node has been touched yet, so this never clobbers a real one.
	if GameData.respawn_scene == "":
		GameData.respawn_scene = get_tree().current_scene.scene_file_path
		GameData.respawn_position = global_position

	# Stays up until she actually lands a successful air dash — elana.gd
	# clears it ("air_dash_tutorial" id) the moment that happens.
	HUD.show_prompt("Press SHIFT while in air to air dash", elana, "air_dash_tutorial")
