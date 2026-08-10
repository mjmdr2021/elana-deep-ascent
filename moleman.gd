extends "res://player_proximity_area.gd"

const TRADE_UI_SCENE = preload("res://moleman_trade_ui.tscn")
const DialogueData = preload("res://dialogue_data.gd")

const ELANA_DIALOGUE_COLOR: Color = Color(0.15, 0.35, 0.85)
const MOLEMAN_DIALOGUE_COLOR: Color = Color(0.15, 0.55, 0.2)

# Per-instance — set this in the Inspector for other Molemen to give each one
# their own conversation. This first one's default lines live in dialogue_data.gd.
@export var talk_lines: Array = DialogueData.MOLEMAN_FIRST_TALK

var _choice_canvas: CanvasLayer = null
var _trade_ui: Control = null

func _ready():
	super._ready()
	$AnimatedSprite2D.play("idle")

func _process(_delta):
	if player_inside and player and Input.is_action_just_pressed("interact") \
			and _choice_canvas == null and _trade_ui == null and not GameData.in_cutscene:
		_show_choice()

func _show_choice() -> void:
	_choice_canvas = CanvasLayer.new()
	_choice_canvas.layer = 20
	get_tree().current_scene.add_child(_choice_canvas)

	# Same look as the dialogue/prompt/consume-tooltip boxes — white bg, red
	# border, black text — for one consistent "system UI" language.
	var style = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(2)
	style.border_color = Color(0.8, 0.1, 0.1)
	style.set_corner_radius_all(3)

	var box = Panel.new()
	box.add_theme_stylebox_override("panel", style)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -80
	box.offset_top = -50
	box.offset_right = 80
	box.offset_bottom = 50
	_choice_canvas.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	box.add_child(vbox)

	vbox.add_child(_make_menu_button("Talk", _on_talk_pressed))
	vbox.add_child(_make_menu_button("Trade", _on_trade_pressed))
	vbox.add_child(_make_menu_button("Cancel", _close_choice))

# White background (matching the panel, instead of Godot's default grey
# button theme), black text, a faint red tint on hover/press for feedback.
func _make_menu_button(text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", Color.BLACK)

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color.WHITE
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.85, 0.85)
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.7, 0.7)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal)

	btn.pressed.connect(callback)
	return btn

func _close_choice() -> void:
	if _choice_canvas:
		_choice_canvas.queue_free()
		_choice_canvas = null

func _on_talk_pressed() -> void:
	_close_choice()
	# Reuses the same room_state dict mark_removed/is_removed already persist
	# through save/load — "_talked" suffix keeps this key distinct from an
	# actual removal flag for a node of the same name.
	var scene_path = get_tree().current_scene.scene_file_path
	var talked_key = name + "_talked"
	if GameData.is_removed(scene_path, talked_key):
		HUD.show_dialogue(DialogueData.MOLEMAN_REPEAT_TALK, true, {"Moleman": self}, {"Moleman": MOLEMAN_DIALOGUE_COLOR})
		return
	GameData.mark_removed(scene_path, talked_key)
	if talk_lines.is_empty():
		GameData.spawn_float_text("...", global_position, Color(0.85, 0.75, 0.6))
		return
	HUD.show_dialogue(talk_lines, true, {"Moleman": self}, {
		"Elana": ELANA_DIALOGUE_COLOR,
		"Moleman": MOLEMAN_DIALOGUE_COLOR,
	})

func _on_trade_pressed() -> void:
	_close_choice()
	var canvas = CanvasLayer.new()
	canvas.layer = 20
	get_tree().current_scene.add_child(canvas)
	_trade_ui = TRADE_UI_SCENE.instantiate()
	canvas.add_child(_trade_ui)
	canvas.tree_exited.connect(func(): _trade_ui = null)
	_trade_ui.open(self)
