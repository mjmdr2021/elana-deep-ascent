extends Area2D

# Invisible trigger volume for scripted dialogue/cutscene beats. cutscene_type
# picks which one this particular placed instance fires — add a new case to
# both the enum and _on_body_entered()'s match when a future marker needs
# different content.
const DialogueData = preload("res://dialogue_data.gd")

enum CutsceneType { GLINT_SCOUT_TUTORIAL, CAMERA_PAN }

@export var cutscene_type: CutsceneType = CutsceneType.GLINT_SCOUT_TUTORIAL

const CAMERA_PAN_OFFSET: Vector2 = Vector2(-400, 0)
const CAMERA_PAN_DURATION: float = 1.5
const CAMERA_PAN_HOLD: float = 0.4

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	match cutscene_type:
		CutsceneType.GLINT_SCOUT_TUTORIAL:
			if GameData.glint_scout_tutorial_done:
				return
			GameData.glint_scout_tutorial_done = true
			_start_scout_tutorial_cutscene(body)
		CutsceneType.CAMERA_PAN:
			if GameData.camera_pan_intro_done:
				return
			GameData.camera_pan_intro_done = true
			_start_camera_pan_cutscene(body)

func _start_scout_tutorial_cutscene(elana: Node) -> void:
	GameData.in_cutscene = true

	# Gravity still applies during the freeze — if she's airborne, just wait
	# for her to land naturally before the dialogue starts.
	while not elana.is_on_floor():
		await get_tree().physics_frame

	HUD.show_dialogue(DialogueData.SCOUT_TUTORIAL, false)
	await HUD.dialogue_finished

	# Instruction prompt — red border, no click-to-advance. Only closes once
	# the player actually presses X and Glint starts scouting; scout_glint's
	# input handler isn't gated by GameData.in_cutscene, so the press works
	# normally while Elana stays frozen.
	HUD.show_prompt("Press X to make Glint scout", elana, "scout_tutorial")
	while not GameData.glint_scouting:
		await get_tree().process_frame
	HUD.hide_prompt("scout_tutorial")

	# Hand off to the scout system's own freeze (glint_scouting) — clear
	# in_cutscene now so Elana un-freezes normally once Glint returns.
	GameData.in_cutscene = false

# Pans Elana's own camera left via Camera2D.offset (not her actual position),
# holds briefly, then eases back to center — a simple "look over there" beat
# with no dialogue. Also widens the zoom for the boss arena reveal — that part
# is driven by elana.gd's own camera-zoom system (GameData.boss_zoom_active),
# not a tween here, and deliberately never turned back off by this cutscene.
func _start_camera_pan_cutscene(elana: Node) -> void:
	GameData.in_cutscene = true
	GameData.boss_zoom_active = true

	# Targets elana.camera_offset_base, not Camera.offset directly — that's
	# the "base" the screen-shake system adds its own offset on top of each
	# frame, so the two never fight over the same property.
	var tween = create_tween()
	tween.tween_property(elana, "camera_offset_base", CAMERA_PAN_OFFSET, CAMERA_PAN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(CAMERA_PAN_HOLD)
	tween.tween_property(elana, "camera_offset_base", Vector2.ZERO, CAMERA_PAN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	GameData.in_cutscene = false
