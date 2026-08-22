extends Area2D

# Invisible trigger volume for scripted dialogue/cutscene beats. cutscene_type
# picks which one this particular placed instance fires — add a new case to
# both the enum and _on_body_entered()'s match when a future marker needs
# different content.
const DialogueData = preload("res://dialogue_data.gd")

# BOSS2_HOLE_ENTRANCE appended at the end (2026-08-22, user request: "add
# cutscene type. boss2HoleEntranceCutScene"), not inserted between existing
# entries -- GDScript enums serialize as plain integers in .tscn files
# (cutscene_type = N), so reordering would silently reassign every already-
# placed marker after the insertion point to the wrong type.
enum CutsceneType { GLINT_SCOUT_TUTORIAL, CAMERA_PAN, BOSS1_DROP_ENTRANCE, AIR_DASH_TUTORIAL, BOSS2_HOLE_ENTRANCE }

@export var cutscene_type: CutsceneType = CutsceneType.GLINT_SCOUT_TUTORIAL

const CAMERA_PAN_OFFSET: Vector2 = Vector2(-400, 0)
const CAMERA_PAN_DURATION: float = 1.5
const CAMERA_PAN_HOLD: float = 2.0

# "The cave shakes" beat, fired once the pan-back finishes — throws Elana
# up and forward (in whichever direction she's currently facing) into the
# arena, with a camera shake riding along.
const SHAKE_KNOCKUP_FORWARD: float = 220.0
const SHAKE_KNOCKUP_UP: float = -320.0
const SHAKE_KNOCKUP_DURATION: float = 0.4
const SHAKE_TRAUMA: float = 0.8
const ROAR_TRAUMA: float = 0.7
# Ceiling on how long Boss1NormalEntrance() will wait for Elana to land
# after the knockup before giving up and continuing anyway.
const LANDING_WAIT_TIMEOUT: float = 3.0

# Hardcoded, not looked up per-cutscene — both Boss1NormalEntrance() and
# BossCameraLock() seal the entrance gate at this exact same world spot
# (Boss1NormalEntranceCutscene's own position, 20px left, matching the
# offset already tuned there), instead of each computing/looking it up
# slightly differently. Update this one value if the entrance ever moves.
const ENTRANCE_GATE_POS: Vector2 = Vector2(-57, -200)

# Guards against a second Boss1NormalEntrance() starting while the first is
# still mid-flight — the existing camera_pan_intro_done/boss_alive check
# only blocks replaying the intro after it's already finished, not
# re-entering the trigger zone while it's still running. The sequence's own
# knockback (_shake_elana_into_arena()) is physics-driven, not blocked by
# GameData.in_cutscene, so if it ever carried her back across this same
# zone mid-sequence, a second concurrent run would otherwise be possible.
var _normal_entrance_running: bool = false

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
			# Normally a true one-time flag — but if the boss is still alive
			# (walked out of the zone and back in mid-fight, or died and a
			# fresh one respawned into the same spot later), re-triggering
			# is allowed instead of staying silent forever. Only a boss
			# that's actually dead (or never existed) keeps the intro from
			# replaying once it's already played.
			var boss = get_tree().get_first_node_in_group("bosses")
			var boss_alive = boss != null and is_instance_valid(boss) and boss.hp > 0
			if GameData.camera_pan_intro_done and not boss_alive:
				return
			if _normal_entrance_running:
				return
			GameData.camera_pan_intro_done = true
			Boss1NormalEntrance(body)
		CutsceneType.BOSS1_DROP_ENTRANCE:
			# Always re-triggers — no one-time flag. Safe against firing
			# mid-sequence: GameData.in_cutscene freezes her for the entire
			# BossCameraLock() run (including the whole Drop Push sequence),
			# so she physically can't re-enter this trigger zone until a
			# previous run has completely finished.
			BossCameraLock(body)
		CutsceneType.AIR_DASH_TUTORIAL:
			if GameData.air_dash_tutorial_done:
				return
			GameData.air_dash_tutorial_done = true
			_start_air_dash_tutorial_cutscene(body)
		CutsceneType.BOSS2_HOLE_ENTRANCE:
			# BossCameraLock() is already boss-agnostic (reads whichever
			# boss is currently in the "bosses" group, calls duck-typed
			# methods on it) despite its Boss1-flavored name -- Elemander
			# needs no new sequence logic of his own, just his own marker
			# actually wired to a boss-entrance type instead of silently
			# defaulting to GLINT_SCOUT_TUTORIAL (see the marker fix in
			# full_map.tscn). Same re-entry safety as BOSS1_DROP_ENTRANCE
			# above -- no one-time flag needed, GameData.in_cutscene
			# blocks a concurrent re-trigger for the same reason.
			BossCameraLock(body)

func _start_scout_tutorial_cutscene(elana: Node) -> void:
	GameData.in_cutscene = true

	# Gravity still applies during the freeze — if she's airborne, just wait
	# for her to land naturally before the dialogue starts. is_instance_valid
	# guards on self throughout — this node (and get_tree() along with it)
	# can go null if a scene reload/room unload happens while this coroutine
	# is suspended on one of the long waits below (dialogue, waiting on the
	# player to actually press X), same class of bug the other cutscene
	# function here already guards against via is_instance_valid(elana).
	while is_instance_valid(self) and is_instance_valid(elana) and not elana.is_on_floor():
		await get_tree().physics_frame
	if not is_instance_valid(self):
		# This node (and get_tree() along with it) went away mid-wait —
		# still clear in_cutscene explicitly rather than just returning, or
		# whatever new context Elana ends up in inherits a stuck freeze with
		# nothing left around to ever un-set it.
		GameData.in_cutscene = false
		return

	HUD.show_dialogue(DialogueData.SCOUT_TUTORIAL, false)
	await HUD.dialogue_finished
	if not is_instance_valid(self):
		GameData.in_cutscene = false
		return

	# Instruction prompt — red border, no click-to-advance. Only closes once
	# the player actually presses X and Glint starts scouting; scout_glint's
	# input handler isn't gated by GameData.in_cutscene, so the press works
	# normally while Elana stays frozen.
	HUD.show_prompt("Press X to make Glint scout", elana, "scout_tutorial")
	while is_instance_valid(self) and not GameData.glint_scouting:
		await get_tree().process_frame
	if not is_instance_valid(self):
		GameData.in_cutscene = false
		return
	HUD.hide_prompt("scout_tutorial")

	# Hand off to the scout system's own freeze (glint_scouting) — clear
	# in_cutscene now so Elana un-freezes normally once Glint returns.
	GameData.in_cutscene = false

# Reinforces the air dash prompt at a spot that actually calls for it (e.g.
# a gap only an air dash can cross) — separate from stone_being.gd's own
# one-time power-grant flow, which shows this exact same "air_dash_tutorial"
# prompt id once when the ability first gets unlocked. Unlike the scout
# tutorial above, this does NOT stay frozen (GameData.in_cutscene) while
# waiting for her to actually perform the dash — she has to jump and press
# Shift herself, which she can't do at all while in_cutscene is blocking her
# input. So: freeze only for the dialogue beat, unfreeze, THEN show the
# prompt and let her handle the rest on her own — elana.gd's existing
# "sprint" input handler already clears this same prompt id the instant she
# lands a real air dash, so nothing here needs to wait around for it.
func _start_air_dash_tutorial_cutscene(elana: Node) -> void:
	GameData.in_cutscene = true
	while is_instance_valid(self) and is_instance_valid(elana) and not elana.is_on_floor():
		await get_tree().physics_frame
	if not is_instance_valid(self):
		GameData.in_cutscene = false
		return

	HUD.show_dialogue(DialogueData.AIR_DASH_TUTORIAL, false)
	await HUD.dialogue_finished
	if not is_instance_valid(self):
		GameData.in_cutscene = false
		return

	GameData.in_cutscene = false
	HUD.show_prompt("Press SHIFT while in air to air dash", elana, "air_dash_tutorial")

# Pans Elana's own camera left via Camera2D.offset (not her actual position),
# holds briefly, then eases back to center — once that pan-back finishes,
# the cave "shakes": she's knocked up and forward into the arena with a
# camera shake riding along, and lands. Deliberately does NOT touch zoom or
# lock the camera to arena bounds or show the boss HP bar (boss_zoom_active,
# camera_locked/camera_bounds) — no camera change of any kind until she's
# actually made her way further into the arena and BossCameraLock() below
# fires, which then jumps straight to the full locked boss-camera mode in
# one step rather than easing through an intermediate cutscene zoom first.
# The entrance DOES seal here though — right as she first crosses in, not
# only later at BossCameraLock() — drop_entrance_gate() is idempotent
# (guarded by hollowfang.gd's own live-gate check), so whichever of the two
# fires first is the one that actually seals it; the other is a no-op.
func Boss1NormalEntrance(elana: Node) -> void:
	_normal_entrance_running = true
	GameData.in_cutscene = true
	# Tells elana.gd's _update_camera_lock() to stay completely hands-off
	# while this tween owns camera_offset_base — without this, that function
	# runs every frame too and (since camera_locked isn't set until after
	# the tween finishes, below) its own "ease back to Vector2.ZERO" branch
	# was fighting the tween's leftward pan in real time, which is what
	# actually caused the reported "wonky" pan.
	GameData.camera_pan_active = true

	var boss = get_tree().get_first_node_in_group("bosses")

	# Targets elana.camera_offset_base, not Camera.offset directly — that's
	# the "base" the screen-shake system adds its own offset on top of each
	# frame, so the two never fight over the same property.
	var tween = create_tween()
	tween.tween_property(elana, "camera_offset_base", CAMERA_PAN_OFFSET, CAMERA_PAN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# "The snake roars" — fires right as the hold begins (camera's already
	# settled on whatever the pan-left revealed), a camera shake plus the
	# boss's own head-shake riding together.
	tween.tween_callback(_trigger_boss_roar.bind(elana, boss))
	tween.tween_interval(CAMERA_PAN_HOLD)
	tween.tween_property(elana, "camera_offset_base", Vector2.ZERO, CAMERA_PAN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_shake_elana_into_arena.bind(elana))
	await tween.finished

	# This whole sequence (tween + landing wait) can run up to ~8s — if this
	# marker node itself gets freed partway through (a scene reload, room
	# transition, anything that clears the level while it's still
	# suspended), get_tree() below goes null and the function would error
	# out silently without ever reaching the gate-drop call at the end.
	# Guarded here (same class of bug _start_scout_tutorial_cutscene() also
	# guards against) — the wait loop bails early if so, but the gate-drop
	# below still always runs regardless (it only needs `boss`, not this
	# node, to still be valid).
	if is_instance_valid(self):
		# A beat so physics has actually applied the knockup's upward
		# velocity before checking is_on_floor() — otherwise this could
		# false-positive exit immediately if she happened to still be
		# grounded the instant the callback fired.
		await get_tree().create_timer(0.15).timeout
		# Wall-clock timer polling (create_tree().create_timer()), NOT
		# `await get_tree().physics_frame` — that signal only fires as
		# physics actually ticks, so anything that stalls/slows physics
		# processing could stall this loop right along with it, well past
		# LANDING_WAIT_TIMEOUT's supposed cap. SceneTreeTimers run off idle
		# time instead, so this reliably exits on schedule regardless.
		var landing_wait_elapsed: float = 0.0
		while landing_wait_elapsed < LANDING_WAIT_TIMEOUT:
			if not is_instance_valid(self) or not is_instance_valid(elana) or elana.is_on_floor():
				break
			await get_tree().create_timer(0.05).timeout
			landing_wait_elapsed += 0.05

	# Sealed after she's landed (or the wait above bailed/timed out) — always
	# attempted regardless of whether this marker survived the wait, only
	# `boss` needs to still be valid.
	if boss and is_instance_valid(boss) and boss.has_method("drop_entrance_gate"):
		boss.drop_entrance_gate(ENTRANCE_GATE_POS)

	# Camera lock/zoom/HP bar reveal — this entrance never used to trigger
	# it at all (only the hole/drop entrance's BossCameraLock() did), which
	# is the bug this closes: taking the normal entrance left the HP bar
	# permanently hidden and the camera unlocked for the entire fight unless
	# she also happened to cross the separate drop-entrance trigger zone,
	# which the normal path doesn't reach. Shared with BossCameraLock() via
	# _reveal_boss_camera_lock() rather than duplicated here.
	_reveal_boss_camera_lock(boss)

	GameData.camera_pan_active = false
	GameData.in_cutscene = false
	_normal_entrance_running = false

# Boss 1 Drop Entrance — a second, later beat once Elana's actually made her
# way into the arena proper, not the instant the camera-pan reveal above
# knocks her in. No camera change happens until Drop Push has fully finished
# — the entrance gate seals first, then the Drop Push sequence (delay,
# violent shake, then the actual shove toward the arena) plays out, and only
# once she's actually landed at her final spot does the camera jump straight
# to full boss-camera-lock mode in one step (boss_zoom_active + camera_locked
# set together, not eased through an intermediate cutscene zoom, and not
# active during the push itself). Bundles what used to be split across the
# pan cutscene's tail end and a standalone CaveDisruptorArenaZone safety-net
# check in hollowfang.gd into one place. Awaits the whole Drop Push sequence
# before releasing control, so she can't act again until it's done.
func BossCameraLock(elana: Node) -> void:
	GameData.in_cutscene = true
	var boss = get_tree().get_first_node_in_group("bosses")
	if boss:
		# Invulnerable while boss is alive — see rock_gate.gd's boss_ref
		# comment. Also the actual fix for the mid-fight retrigger: the gate
		# physically blocks the player from re-crossing the trigger zone
		# until it's dead. Same hardcoded ENTRANCE_GATE_POS Boss1NormalEntrance()
		# uses — whichever of the two cutscenes fires first is the one that
		# actually seals it (drop_entrance_gate() is idempotent), so both
		# need to land at the exact same spot.
		if boss.has_method("drop_entrance_gate"):
			boss.drop_entrance_gate(ENTRANCE_GATE_POS)
		if boss.has_method("start_drop_push_sequence"):
			await boss.start_drop_push_sequence(elana)

		# Camera lock/zoom/HP bar reveal — deliberately AFTER Drop Push, not
		# before or during it.
		_reveal_boss_camera_lock(boss)

	GameData.in_cutscene = false

# Shared by BossCameraLock() (after its own Drop Push sequence) and
# Boss1NormalEntrance() (right after its own landing-wait/gate-seal) — the
# moment either entrance is considered "done," regardless of which one
# actually got her into the arena.
func _reveal_boss_camera_lock(boss: Node) -> void:
	if not boss or not is_instance_valid(boss):
		return
	GameData.boss_zoom_active = true
	GameData.camera_locked = true
	if boss.has_method("get_camera_bounds"):
		GameData.camera_bounds = boss.get_camera_bounds()

func _shake_elana_into_arena(elana: Node) -> void:
	if elana.has_method("apply_knockback"):
		elana.apply_knockback(Vector2(elana.facing * SHAKE_KNOCKUP_FORWARD, SHAKE_KNOCKUP_UP), SHAKE_KNOCKUP_DURATION)
	if elana.has_method("add_camera_trauma"):
		elana.add_camera_trauma(SHAKE_TRAUMA)

func _trigger_boss_roar(elana: Node, boss: Node) -> void:
	if elana.has_method("add_camera_trauma"):
		elana.add_camera_trauma(ROAR_TRAUMA)
	if boss and boss.has_method("play_roar_shake"):
		boss.play_roar_shake()
