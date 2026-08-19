extends Node

var _settings_overlay: ColorRect

func _ready():
	HUD.set_hud_visible(false)
	var layer = CanvasLayer.new()
	layer.layer = 0
	add_child(layer)

	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)

	_build_title(bg)
	_build_buttons(bg)
	_build_settings(layer)

func _build_title(parent: Control) -> void:
	var area = CenterContainer.new()
	area.anchor_right = 1.0
	area.anchor_top = 0.18
	area.anchor_bottom = 0.42
	parent.add_child(area)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	area.add_child(vbox)

	var title = Label.new()
	title.text = "ELANA: DEEP ASCENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.92, 0.87, 0.72))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "a story of descent"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.42, 0.42, 0.55))
	vbox.add_child(sub)

func _build_buttons(parent: Control) -> void:
	var area = CenterContainer.new()
	area.anchor_right = 1.0
	area.anchor_top = 0.45
	area.anchor_bottom = 0.85
	parent.add_child(area)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	area.add_child(vbox)

	if GameData.has_save_file():
		var continue_btn = _make_button("Continue")
		continue_btn.pressed.connect(_on_continue)
		vbox.add_child(continue_btn)

	var new_game = _make_button("New Game")
	new_game.pressed.connect(_on_new_game)
	vbox.add_child(new_game)

	var settings = _make_button("Settings")
	settings.pressed.connect(_on_settings)
	vbox.add_child(settings)

	var exit = _make_button("Exit")
	exit.pressed.connect(_on_exit)
	vbox.add_child(exit)

func _build_settings(layer: CanvasLayer) -> void:
	_settings_overlay = ColorRect.new()
	_settings_overlay.color = Color(0.06, 0.06, 0.09, 0.97)
	_settings_overlay.anchor_left = 0.25
	_settings_overlay.anchor_right = 0.75
	_settings_overlay.anchor_top = 0.15
	_settings_overlay.anchor_bottom = 0.85
	_settings_overlay.visible = false
	layer.add_child(_settings_overlay)

	var title = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 24
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.87, 0.72))
	_settings_overlay.add_child(title)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.anchor_left = 0.08
	vbox.anchor_right = 0.92
	vbox.offset_top = 70
	_settings_overlay.add_child(vbox)

	var res_opt = OptionButton.new()
	for i in GameData.RESOLUTIONS.size():
		res_opt.add_item(GameData.RESOLUTION_LABELS[i])
		if GameData.RESOLUTIONS[i] == GameData.window_resolution:
			res_opt.selected = i
	res_opt.disabled = GameData.window_mode != 0
	res_opt.focus_mode = Control.FOCUS_NONE
	res_opt.item_selected.connect(func(idx): GameData.set_window_resolution(GameData.RESOLUTIONS[idx]))

	var mode_label = Label.new()
	mode_label.text = "Window Mode"
	mode_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(mode_label)

	var mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	vbox.add_child(mode_row)

	var btn_group = ButtonGroup.new()
	for entry in [["Windowed", 0], ["Fullscreen", 1]]:
		var btn = Button.new()
		btn.text = entry[0]
		btn.toggle_mode = true
		btn.button_group = btn_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.button_pressed = GameData.window_mode == entry[1]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mode = entry[1]
		btn.toggled.connect(func(on):
			if on:
				GameData.set_window_mode(mode)
				res_opt.disabled = mode != 0
		)
		mode_row.add_child(btn)

	var res_label = Label.new()
	res_label.text = "Resolution"
	res_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(res_label)
	vbox.add_child(res_opt)

	for placeholder in ["Master Volume — coming soon", "SFX Volume — coming soon", "Controls — coming soon"]:
		var lbl = Label.new()
		lbl.text = placeholder
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5))
		vbox.add_child(lbl)

	var back = _make_button("Back")
	back.pressed.connect(_on_settings_back)
	vbox.add_child(back)

func _make_button(label: String) -> Button:
	return GameData.make_styled_button(label, Vector2(220, 46), 16)

func _on_new_game() -> void:
	GameData.reset()
	# Same reason Continue needs this — reset() clears the data, but the
	# slot icons only repaint when something explicitly calls this; without
	# it, a New Game right after a previous session still shows that old
	# inventory until an unrelated action happens to trigger a refresh.
	HUD.refresh_slots()
	GameData.pending_intro = true
	# Stays hidden through the intro cutscene and the walk to the Stone
	# Being — HUD.set_hud_visible(true) only fires once she's actually
	# granted the power (see stone_being.gd), not at New Game.
	HUD.set_hud_visible(false)
	# Routed through loading_screen.tscn instead of a direct
	# change_scene_to_file() — that call is synchronous and blocks the main
	# thread for the whole load+instantiate of full_map.tscn (a noticeable
	# freeze with zero feedback); the loading screen threads it instead.
	GameData.pending_scene_load = "res://full_map.tscn"
	get_tree().change_scene_to_file("res://loading_screen.tscn")

func _on_continue() -> void:
	# Loads the save and prepares target_scene/use_default_spawn/just_died —
	# see GameData.load_and_prepare_respawn()'s own comment; elana.gd's
	# die() shares this same helper now instead of a hand-copy of it.
	if not GameData.load_and_prepare_respawn():
		return
	# load_game() sets GameData's inventory/quickslot data directly — the
	# HUD's slot icons don't repaint themselves from that alone (they only
	# update when something explicitly calls refresh_slots(), e.g. picking
	# up an item), so without this they'd stay stuck showing empty/stale
	# slots until any unrelated inventory action happened to trigger one.
	HUD.refresh_slots()
	# Matches whatever state was actually saved — the HUD stays hidden if the
	# save predates the Stone Being (shouldn't normally happen since saves
	# only happen at Ritual Nodes, but keeps this correct either way).
	HUD.set_hud_visible(GameData.received_stone_being_power)
	# Same threaded hand-off as _on_new_game() — see its comment above.
	get_tree().change_scene_to_file("res://loading_screen.tscn")

func _on_settings() -> void:
	_settings_overlay.visible = true

func _on_settings_back() -> void:
	_settings_overlay.visible = false

func _on_exit() -> void:
	get_tree().quit()
