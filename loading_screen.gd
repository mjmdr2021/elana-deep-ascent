extends Node

# Threaded scene-load screen — title_screen.gd's _on_new_game()/_on_continue()
# set GameData.pending_scene_load then switch here instead of calling
# change_scene_to_file() directly on the target scene. change_scene_to_file()
# is synchronous: it blocks the main thread for the entire load+instantiate
# of full_map.tscn (the whole open-world map — every room, enemy, tileset —
# in one shot), which is what caused the reported freeze with zero feedback.
# This screen itself is trivial (built procedurally below, no heavy content
# of its own) so switching TO it is effectively instant; it then polls a
# background ResourceLoader request so the spinner keeps animating while the
# real scene loads off the main thread.

const LOADING_SPINNER_SCRIPT = preload("res://loading_spinner.gd")
const BG_COLOR: Color = Color(0.04, 0.04, 0.06)  # matches title_screen.gd's background
const TEXT_COLOR: Color = Color(0.92, 0.87, 0.72)  # matches title_screen.gd's title text

var _target_scene: String = ""
var _label: Label = null

func _ready() -> void:
	_build_ui()
	# The gameplay HUD (health bar, hotbar, boss HP bar, etc.) is a
	# persistent autoload — title_screen.gd's _on_continue() already sets
	# its visibility for whatever's about to load (before this screen ever
	# existed), so without this it stays showing right through the loading
	# screen instead of just the spinner/text. Restored below once the real
	# scene is actually ready to switch to.
	HUD.set_hud_visible(false)

	_target_scene = GameData.pending_scene_load
	GameData.pending_scene_load = ""
	if _target_scene == "":
		# Shouldn't happen via the normal title-screen flow, but fail safe
		# instead of sitting on a loading screen forever with nothing queued.
		push_warning("loading_screen: no pending_scene_load set, returning to title")
		get_tree().change_scene_to_file("res://title_screen.tscn")
		return
	ResourceLoader.load_threaded_request(_target_scene)

func _build_ui() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 0
	add_child(layer)

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)

	var area = CenterContainer.new()
	area.anchor_right = 1.0
	area.anchor_bottom = 1.0
	bg.add_child(area)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	area.add_child(vbox)

	var spinner = Control.new()
	spinner.custom_minimum_size = Vector2(56, 56)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spinner.set_script(LOADING_SPINNER_SCRIPT)
	vbox.add_child(spinner)

	_label = Label.new()
	_label.text = "Loading... 0%"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(_label)

func _process(_delta: float) -> void:
	if _target_scene == "":
		return
	var progress: Array = []
	var status = ResourceLoader.load_threaded_get_status(_target_scene, progress)
	if not progress.is_empty():
		_label.text = "Loading... %d%%" % int(round(float(progress[0]) * 100.0))
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed: PackedScene = ResourceLoader.load_threaded_get(_target_scene)
		_target_scene = ""
		# Restored to whatever it should actually be for a fresh load (not
		# just re-shown unconditionally) — matches the same
		# received_stone_being_power check title_screen.gd's own
		# _on_continue()/_on_new_game() already use.
		HUD.set_hud_visible(GameData.received_stone_being_power)
		get_tree().change_scene_to_packed(packed)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("loading_screen: failed to load " + _target_scene)
		_target_scene = ""
		get_tree().change_scene_to_file("res://title_screen.tscn")
