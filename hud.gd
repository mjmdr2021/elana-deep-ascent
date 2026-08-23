extends Node

signal dialogue_finished

const ItemSlot = preload("res://item_slot.gd")
const ITEM_USE_COOLDOWN = 3

var hp_fill: ColorRect
var hp_bg: ColorRect
# Persistent top-of-screen boss HP bar — separate from any floating HPBar a
# boss scene draws above itself (e.g. hollowfang.gd's own), only visible
# while a "bosses"-group member is actually in the scene and alive.
var _boss_hp_root: Control
var _boss_hp_bg: ColorRect
var _boss_hp_fill: ColorRect
var _boss_hp_name_label: Label
var _current_boss: Node = null
var inventory_overlay: ColorRect
var char_overlay: ColorRect
var skill_overlay: ColorRect
var glint_skill_overlay: ColorRect
var inventory_open = false
var char_screen_open = false
var skill_tree_open = false
var glint_tree_open = false

var _death_screen_active: bool = false
var _dialogue_layer: CanvasLayer
var _dialogue_box: Panel
var _dialogue_speaker_label: Label
var _dialogue_text_label: Label
var _dialogue_lines: Array = []
var _dialogue_index: int = 0
var _dialogue_active: bool = false
var _dialogue_was_blocking: bool = false
var _dialogue_speaker_nodes: Dictionary = {}
var _dialogue_speaker_colors: Dictionary = {}
const DIALOGUE_DEFAULT_TEXT_COLOR: Color = Color.BLACK
const DIALOGUE_DEFAULT_SPEAKER_COLOR: Color = Color(0.3, 0.25, 0.05)
# Generic skip button, reused by any multi-beat cutscene coroutine (stone
# being intro, Elana's opening cutscene, etc.) — the button itself only
# knows how to raise a flag and force-close whatever dialogue line is
# currently up; each cutscene script is responsible for checking
# skip_requested after its own await points and jumping to its own finalize
# step, since only it knows what "the end state" of its sequence looks like.
var _skip_button: Button
var skip_requested: bool = false
var _flash_overlay: ColorRect
var _prompt_box: Panel
var _prompt_label: Label
var _prompt_active: bool = false
var _prompt_target: Node = null
var _prompt_id: String = ""
var _prompt_offset: Vector2 = Vector2.ZERO
var quickslot_slot_nodes: Array = []
var inventory_slot_nodes: Array = []
var selected_slot = 0
var wall_jump_button: Button
var double_jump_button: Button
var hp_bars_button: Button
var dodge_button: Button
var air_dash_button: Button
var item_cooldown_button: Button
var elemander_pads_button: Button
var golden_cloak_button: Button
var hollowscale_button: Button
var danger_sense_button: Button
var ant_queen_buff_button: Button
var reset_cooldowns_button: Button
var fixed_zoom_button: Button
var fixed_zoom_0_1x_button: Button
var screen_shake_button: Button
var item_use_cooldown = 0.0
var _stat_labels: Dictionary = {}
var hovered_inventory_slot: int = -1
var hovered_quickslot_slot: int = -1

var _hud_visible: bool = true
var _gameplay_layers: Array = []
var _options_layer: CanvasLayer
var _options_panel: ColorRect
var _options_settings_panel: ColorRect
var _options_open: bool = false
var _skill_sp_label: Label
var _skill_node_buttons: Dictionary = {}
var _skill_line_drawer = null
var _skill_last_sp: int = -1
var _glint_sp_label: Label
var _glint_node_buttons: Dictionary = {}
var _glint_line_drawer = null
var _glint_last_sp: int = -1
var _herb_indicator: Control
var _herb_icon: ColorRect
var _herb_bar_bg: ColorRect
var _herb_bar_fill: ColorRect
var _ore_indicator: Control
var _ore_icon: ColorRect
var _ore_bar_bg: ColorRect
var _ore_bar_fill: ColorRect
var _xp_bg: ColorRect
var _xp_fill: ColorRect
var _shield_bg: ColorRect
var _shield_fill: ColorRect
var _last_stand_box: Panel = null
var _last_stand_label: Label = null
var _last_stand_style: StyleBoxFlat = null
var _hollowscale_box: Panel = null
var _hollowscale_label: Label = null
var _hollowscale_style: StyleBoxFlat = null
var _danger_sense_box: Panel = null
var _danger_sense_label: Label = null
var _danger_sense_style: StyleBoxFlat = null
var _depth_label: Label = null
var _stack_labels: Dictionary = {}
var _hp_text: Label = null
var _sp_badge: Label = null
var _level_label: Label = null
var _herb_time_label: Label = null
var _herb_name_label: Label = null
var _ore_time_label: Label = null
var _ore_name_label: Label = null
var _danger_sense_overlay: ColorRect = null
var _danger_sense_tween: Tween = null
const WEAPON_SHORT_NAMES = {
	"fist": "FIST", "sword": "SWORD", "chain_claw": "CHAIN",
	"spear": "SPEAR", "warhammer": "HAMMER",
}

const ITEM_TOOLTIP_DURATION: float = 7.0
const ITEM_TOOLTIP_TYPEWRITER_CPS: float = 30.0
# Inventory hover description (item_slot.gd's tooltip_text) — unrelated to
# the on-first-consume popup below, keep this phrasing as the reference doc.
const ITEM_DESCRIPTIONS: Dictionary = {
	"herb": "Herb — a basic plant. No special effect.",
	"herbElementalFire": "Fire Herb — Consume to gain fire damage and fire resistance.",
	"herbElementalFrost": "Frost Herb — Consume to gain frost damage and frost resistance.",
	"herbElementalElec": "Elec Herb — Consume to gain electric damage and electric resistance.",
	"herbAgility": "Agility Herb — Consume to gain increased move speed and attack speed.",
	"herbHeal": "Heal Herb — Consume to gain gradual HP regeneration.",
	"herbPower": "Power Herb — Consume to gain increased attack damage.",
	"ore1": "Sword Ore — Consume to transform Glint into a Sword.",
	"ore2": "Chain Claw Ore — Consume to transform Glint into a Chain Claw.",
	"ore3": "Spear Ore — Consume to transform Glint into a Spear.",
	"ore4": "Warhammer Ore — Consume to transform Glint into a Warhammer.",
	"note1": "These \"Ritual Nodes\" that light up— they apparently store my soul. So when I die, these things revive me, and I start all over again.",
}
# On-first-consume popup text (_show_item_tooltip) — separate, in-character
# phrasing from Elana's POV, distinct from the inventory hover description.
const CONSUME_TOOLTIP_TEXT: Dictionary = {
	"herb": "Eating this herb gives me... nothing. No special abilities.",
	"herbElementalFire": "Eating this herb gives me fire abilities.",
	"herbElementalFrost": "Eating this herb gives me frost abilities.",
	"herbElementalElec": "Eating this herb gives me electric abilities.",
	"herbAgility": "Eating this herb gives me agility abilities.",
	"herbHeal": "Eating this herb gives me healing abilities.",
	"herbPower": "Eating this herb gives me power abilities.",
	"ore1": "Feeding this ore to Glint transforms her to a Sword.",
	"ore2": "Feeding this ore to Glint transforms her to a Chain Claw.",
	"ore3": "Feeding this ore to Glint transforms her to a Spear.",
	"ore4": "Feeding this ore to Glint transforms her to a Warhammer.",
}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_toggles()
	_setup_bottom_hud()
	_setup_boss_hp_bar()
	_setup_inventory()
	_setup_character_screen()
	_setup_skill_tree()
	_setup_glint_skill_tree()
	_setup_options()
	_setup_danger_sense_overlay()
	_setup_dialogue_box()
	_setup_skip_button()
	_setup_flash_overlay()
	_setup_prompt_box()
	_setup_debug_overlay()

const DIALOGUE_MAX_WIDTH: float = 360.0
const DIALOGUE_PADDING: float = 14.0
const DIALOGUE_WORLD_OFFSET: Vector2 = Vector2(0, -25)  # above Elana's head
# Default for show_prompt() — same idea, but its targets range from
# person-sized (Elana/Glint, scout/air-dash prompts) to small world props
# (ore/herb hints), so callers can override per-call instead of sharing
# the dialogue box's offset.
const PROMPT_WORLD_OFFSET: Vector2 = Vector2(0, -25)

# Screen-space debug readout — Elana's world position + current FPS, top
# right corner. Independent CanvasLayer/high layer number so it always
# draws on top of everything else, same convention as the dialogue/flash
# layers above.
var _debug_overlay_label: Label

func _setup_debug_overlay() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	_debug_overlay_label = Label.new()
	_debug_overlay_label.anchor_left = 1.0
	_debug_overlay_label.anchor_right = 1.0
	_debug_overlay_label.offset_left = -220.0
	_debug_overlay_label.offset_right = -8.0
	_debug_overlay_label.offset_top = 8.0
	_debug_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug_overlay_label.add_theme_font_size_override("font_size", 14)
	_debug_overlay_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_debug_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_debug_overlay_label)

func _update_debug_overlay() -> void:
	var player = get_tree().get_first_node_in_group("player")
	var pos_text = "pos: (n/a)"
	if player:
		pos_text = "pos: (%.1f, %.1f)" % [player.global_position.x, player.global_position.y]
	_debug_overlay_label.text = pos_text + "\nfps: %d" % Engine.get_frames_per_second()

func _setup_dialogue_box() -> void:
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.layer = 30
	add_child(_dialogue_layer)

	_dialogue_box = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(2)
	style.border_color = Color.BLACK
	style.set_corner_radius_all(3)
	_dialogue_box.add_theme_stylebox_override("panel", style)
	_dialogue_box.visible = false
	_dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_layer.add_child(_dialogue_box)

	_dialogue_speaker_label = Label.new()
	_dialogue_speaker_label.position = Vector2(DIALOGUE_PADDING, DIALOGUE_PADDING * 0.5)
	_dialogue_speaker_label.add_theme_font_size_override("font_size", 13)
	_dialogue_speaker_label.add_theme_color_override("font_color", Color(0.3, 0.25, 0.05))
	_dialogue_box.add_child(_dialogue_speaker_label)

	_dialogue_text_label = Label.new()
	_dialogue_text_label.add_theme_font_size_override("font_size", 14)
	_dialogue_text_label.add_theme_color_override("font_color", Color.BLACK)
	_dialogue_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dialogue_box.add_child(_dialogue_text_label)

# lines: Array of {"speaker": String, "text": String}. blocking freezes Elana
# (GameData.in_cutscene) for the duration, cleared when this sequence closes.
# Pass false when an outer script (a multi-step cutscene) is already managing
# in_cutscene itself across several show_dialogue() calls — this box then
# leaves that flag alone entirely, on either end. Await dialogue_finished to
# know when the sequence closes either way.
# speaker_nodes: optional {String speaker_name: Node} map — the box floats
# above whichever node matches the current line's speaker instead of always
# tracking Elana. Any speaker not in the map (or if the map is empty) falls
# back to the "player" group node, so single-speaker calls need nothing extra.
# speaker_colors: optional {String speaker_name: Color} map — tints both the
# speaker name and their line text. Unmapped speakers keep the normal
# black-text/brown-name default.
func show_dialogue(lines: Array, blocking: bool = true, speaker_nodes: Dictionary = {}, speaker_colors: Dictionary = {}) -> void:
	if lines.is_empty():
		return
	_dialogue_lines = lines
	_dialogue_index = 0
	_dialogue_active = true
	_dialogue_was_blocking = blocking
	_dialogue_speaker_nodes = speaker_nodes
	_dialogue_speaker_colors = speaker_colors
	if blocking:
		GameData.in_cutscene = true
	_dialogue_box.visible = true
	_display_current_dialogue_line()
	_update_dialogue_position()

func _display_current_dialogue_line() -> void:
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	var speaker: String = line.get("speaker", "")
	var text: String = line.get("text", "")
	_dialogue_speaker_label.text = speaker
	_dialogue_speaker_label.visible = speaker != ""
	_dialogue_text_label.text = text
	var color = _dialogue_speaker_colors.get(speaker)
	_dialogue_speaker_label.add_theme_color_override("font_color", color if color != null else DIALOGUE_DEFAULT_SPEAKER_COLOR)
	_dialogue_text_label.add_theme_color_override("font_color", color if color != null else DIALOGUE_DEFAULT_TEXT_COLOR)
	_resize_dialogue_box(speaker, text)

# Sizes the box to fit exactly what's on screen — a short line stays small, a
# long one wraps at DIALOGUE_MAX_WIDTH and the box grows taller to match.
func _resize_dialogue_box(speaker: String, text: String) -> void:
	var font = _dialogue_text_label.get_theme_font("font")
	var font_size = _dialogue_text_label.get_theme_font_size("font_size")
	var natural = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var content_width: float
	var line_count: int
	if natural.x <= DIALOGUE_MAX_WIDTH:
		content_width = max(natural.x, 40.0)
		line_count = 1
	else:
		content_width = DIALOGUE_MAX_WIDTH
		line_count = int(ceil(natural.x / DIALOGUE_MAX_WIDTH))

	# A short line ("Girl...") shouldn't produce a box narrower than the
	# speaker name sitting above it ("Stone Being") — widen to fit whichever
	# is bigger.
	if speaker != "":
		var speaker_font = _dialogue_speaker_label.get_theme_font("font")
		var speaker_font_size = _dialogue_speaker_label.get_theme_font_size("font_size")
		var speaker_natural = speaker_font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, speaker_font_size)
		content_width = max(content_width, min(speaker_natural.x, DIALOGUE_MAX_WIDTH))

	var line_height = font.get_height(font_size)
	var speaker_height = (_dialogue_speaker_label.get_theme_font_size("font_size") + 6.0) if speaker != "" else 0.0

	_dialogue_speaker_label.size = Vector2(content_width, speaker_height)
	_dialogue_text_label.position = Vector2(DIALOGUE_PADDING, DIALOGUE_PADDING * 0.5 + speaker_height)
	_dialogue_text_label.size = Vector2(content_width, line_height * line_count + 4.0)

	_dialogue_box.size = Vector2(
		content_width + DIALOGUE_PADDING * 2.0,
		DIALOGUE_PADDING + speaker_height + line_height * line_count + DIALOGUE_PADDING * 0.5)

# Tracks the current line's speaker screen position every frame while the box
# is up, same projection technique the item tooltip uses, sitting just above
# their head. Falls back to Elana ("player" group) for any unmapped speaker.
func _update_dialogue_position() -> void:
	var speaker: String = _dialogue_lines[_dialogue_index].get("speaker", "") if _dialogue_index < _dialogue_lines.size() else ""
	var target: Node = _dialogue_speaker_nodes.get(speaker)
	if target == null:
		target = get_tree().get_first_node_in_group("player")
	if target == null:
		return
	var screen_pos = get_viewport().get_canvas_transform() * (target.global_position + DIALOGUE_WORLD_OFFSET)
	_dialogue_box.position = screen_pos - Vector2(_dialogue_box.size.x * 0.5, _dialogue_box.size.y)

# Full-screen flash for story beats (e.g. the Stone Being's power grant) —
# sits above the dialogue box on its own layer so it can fire independently
# of whether a dialogue line is currently up.
func _setup_flash_overlay() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 31
	add_child(layer)
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1, 1, 1, 0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash_overlay)

# Fades the overlay in then out over `duration` total. Await this to block
# a cutscene script until the flash has fully finished.
func flash_screen(duration: float = 0.3, color: Color = Color.WHITE) -> void:
	var tween = create_tween()
	var flash_color = Color(color.r, color.g, color.b, 0.85)
	tween.tween_property(_flash_overlay, "color", flash_color, duration * 0.35)
	tween.tween_property(_flash_overlay, "color", Color(color.r, color.g, color.b, 0.0), duration * 0.65)
	await tween.finished

# A static, red-bordered instruction box — visually distinct from the normal
# white/black dialogue box, and deliberately does NOT advance on Space/Enter/
# Click. Callers decide when it closes (e.g. only once a specific input like
# scout_glint has actually fired), via hide_prompt().
func _setup_prompt_box() -> void:
	_prompt_box = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(2)
	style.border_color = Color(0.8, 0.1, 0.1)
	style.set_corner_radius_all(3)
	_prompt_box.add_theme_stylebox_override("panel", style)
	_prompt_box.visible = false
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_layer.add_child(_prompt_box)

	_prompt_label = Label.new()
	_prompt_label.position = Vector2(DIALOGUE_PADDING, DIALOGUE_PADDING * 0.5)
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.add_theme_color_override("font_color", Color.BLACK)
	_prompt_box.add_child(_prompt_label)

# id: optional ownership tag. Two callers can both use the shared prompt box
# without one's hide_prompt() clobbering the other's prompt if a second
# show_prompt() has already taken it over in between (e.g. the scout-tutorial
# prompt and the "press X again" hint firing back-to-back off the same
# scout_glint press).
func show_prompt(text: String, target: Node = null, id: String = "", offset: Vector2 = PROMPT_WORLD_OFFSET) -> void:
	_prompt_id = id
	_prompt_target = target
	_prompt_offset = offset
	_prompt_label.text = text
	_resize_prompt_box(text)
	_prompt_active = true
	_prompt_box.visible = true
	_update_prompt_position()

# id: pass the same tag show_prompt() was called with — only closes if that
# prompt is still the one showing. Omit (default "") to force-close whatever
# is up regardless of owner, e.g. on death.
func hide_prompt(id: String = "") -> void:
	if id != "" and id != _prompt_id:
		return
	_prompt_active = false
	_prompt_box.visible = false

func _resize_prompt_box(text: String) -> void:
	var font = _prompt_label.get_theme_font("font")
	var font_size = _prompt_label.get_theme_font_size("font_size")
	var natural = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var content_width: float
	var line_count: int
	if natural.x <= DIALOGUE_MAX_WIDTH:
		content_width = max(natural.x, 40.0)
		line_count = 1
	else:
		content_width = DIALOGUE_MAX_WIDTH
		line_count = int(ceil(natural.x / DIALOGUE_MAX_WIDTH))
	var line_height = font.get_height(font_size)

	_prompt_label.size = Vector2(content_width, line_height * line_count + 4.0)
	_prompt_box.size = Vector2(
		content_width + DIALOGUE_PADDING * 2.0,
		DIALOGUE_PADDING + line_height * line_count + DIALOGUE_PADDING * 0.5)

# Tracks `target` (falls back to Elana) every frame while the prompt is up,
# same projection technique the dialogue box uses.
func _update_prompt_position() -> void:
	var target = _prompt_target
	if target == null:
		target = get_tree().get_first_node_in_group("player")
	if target == null:
		return
	var screen_pos = get_viewport().get_canvas_transform() * (target.global_position + _prompt_offset)
	_prompt_box.position = screen_pos - Vector2(_prompt_box.size.x * 0.5, _prompt_box.size.y)

func _advance_dialogue() -> void:
	_dialogue_index += 1
	if _dialogue_index >= _dialogue_lines.size():
		_close_dialogue_box()
	else:
		_display_current_dialogue_line()
		_update_dialogue_position()
		_update_dialogue_position()

# Shared end-of-sequence cleanup — same steps _advance_dialogue() ran inline
# when it reached the last line, now also reused by the skip button to force
# a currently-open box closed immediately instead of waiting for the player
# to click through every remaining line.
func _close_dialogue_box() -> void:
	_dialogue_active = false
	_dialogue_box.visible = false
	if _dialogue_was_blocking:
		GameData.in_cutscene = false
	dialogue_finished.emit()

func _setup_skip_button() -> void:
	_skip_button = Button.new()
	_skip_button.text = "Skip ▶"
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_right = 1.0
	_skip_button.offset_left = -90.0
	_skip_button.offset_right = -10.0
	_skip_button.offset_top = 10.0
	_skip_button.offset_bottom = 38.0
	_skip_button.visible = false
	_skip_button.pressed.connect(_on_skip_button_pressed)
	_dialogue_layer.add_child(_skip_button)

func _on_skip_button_pressed() -> void:
	skip_requested = true
	if _dialogue_active:
		_close_dialogue_box()
	hide_skip_button()

# Call at the start of a skippable cutscene; the calling script must check
# skip_requested after each of its own await points and jump straight to its
# own finalize step when it's true. Call hide_skip_button() again once the
# sequence actually ends (skipped or not) — this doesn't auto-hide itself
# except on the skip press.
func show_skip_button() -> void:
	skip_requested = false
	_skip_button.visible = true

func hide_skip_button() -> void:
	_skip_button.visible = false

func _setup_danger_sense_overlay() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 15
	add_child(canvas)
	_gameplay_layers.append(canvas)
	_danger_sense_overlay = ColorRect.new()
	_danger_sense_overlay.color = Color(0.95, 0.85, 0.15, 0.0)
	_danger_sense_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_sense_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_danger_sense_overlay)

# Fades a yellow full-screen tint in, holds it, then fades out over `duration`.
func flash_danger_sense_overlay(duration: float) -> void:
	if _danger_sense_overlay == null:
		return
	if _danger_sense_tween != null and _danger_sense_tween.is_valid():
		_danger_sense_tween.kill()
	_danger_sense_tween = create_tween()
	_danger_sense_tween.tween_property(_danger_sense_overlay, "color:a", 0.25, 0.15)
	_danger_sense_tween.tween_interval(max(0.0, duration - 0.55))
	_danger_sense_tween.tween_property(_danger_sense_overlay, "color:a", 0.0, 0.4)

func set_hud_visible(show: bool) -> void:
	_hud_visible = show
	for layer in _gameplay_layers:
		layer.visible = show

func _make_toggle_button(text: String, pos: Vector2, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(150, 30)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(callback)
	return btn

# Builds a small bottom-HUD ability indicator (locked/cooldown/ready-pulse box).
# offset_left positions it; each box is 48px wide, same row as the others.
func _make_cooldown_box(offset_left: float) -> Dictionary:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3)
	var box = Panel.new()
	box.add_theme_stylebox_override("panel", style)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = offset_left
	box.offset_top = 106
	box.offset_right = offset_left + 48
	box.offset_bottom = 154
	var label = Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(label)
	return {"box": box, "label": label, "style": style}

# Refreshes a cooldown box into one of 3 states: locked, counting down, or a
# pulsing "ready" glow. `ready_color` doubles as the border/font/pulse color.
func _update_cooldown_box(style: StyleBoxFlat, label: Label, prefix: String, unlocked: bool, cooldown: float, ready_color: Color, ready_bg: Color) -> void:
	if not unlocked:
		style.border_color = Color(0.2, 0.2, 0.22)
		style.bg_color = Color(0.06, 0.06, 0.08)
		label.text = prefix
		label.add_theme_color_override("font_color", Color(0.32, 0.32, 0.36))
	elif cooldown <= 0.0:
		var pulse = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 200.0)
		style.border_color = Color(ready_color.r, ready_color.g, ready_color.b, pulse)
		style.bg_color = ready_bg
		label.text = "%s\nREADY" % prefix
		label.add_theme_color_override("font_color", ready_color)
	else:
		style.border_color = Color(0.3, 0.3, 0.3)
		style.bg_color = Color(0.06, 0.06, 0.08)
		label.text = "%s\n%ds" % [prefix, int(ceil(cooldown))]
		label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))

func _setup_toggles():
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_gameplay_layers.append(canvas)

	wall_jump_button = _make_toggle_button(
		"Wall Jump: ON" if GameData.wall_jump_enabled else "Wall Jump: OFF",
		Vector2(10, 10), _on_wall_jump_toggled)
	canvas.add_child(wall_jump_button)

	double_jump_button = _make_toggle_button(
		"Double Jump: ON" if GameData.double_jump_enabled else "Double Jump: OFF",
		Vector2(10, 50), _on_double_jump_toggled)
	canvas.add_child(double_jump_button)

	hp_bars_button = _make_toggle_button(
		"HP Bars: ON" if GameData.show_hp_bars else "HP Bars: OFF",
		Vector2(10, 90), _on_hp_bars_toggled)
	canvas.add_child(hp_bars_button)

	dodge_button = _make_toggle_button(
		"Dodge Roll: ON" if GameData.dodge_enabled else "Dodge Roll: OFF",
		Vector2(10, 130), _on_dodge_toggled)
	canvas.add_child(dodge_button)

	air_dash_button = _make_toggle_button(
		"Air Dash: ON" if GameData.air_dash_enabled else "Air Dash: OFF",
		Vector2(10, 170), _on_air_dash_toggled)
	canvas.add_child(air_dash_button)

	item_cooldown_button = _make_toggle_button(
		"Item Cooldown: ON" if GameData.item_use_cooldown_enabled else "Item Cooldown: OFF",
		Vector2(10, 210), _on_item_cooldown_toggled)
	canvas.add_child(item_cooldown_button)

	canvas.add_child(_make_toggle_button("Fill Herbs (Dev)", Vector2(10, 250), _on_fill_herbs))
	canvas.add_child(_make_toggle_button("Fill Ores (Dev)", Vector2(10, 290), _on_fill_ores))
	canvas.add_child(_make_toggle_button("Give SP +10 (Dev)", Vector2(10, 330), func(): GameData.sp += 10))
	canvas.add_child(_make_toggle_button("Glint SP +10 (Dev)", Vector2(10, 370), func(): GameData.glint_sp += 10))

	elemander_pads_button = _make_toggle_button(
		"Elemander Pads: ON" if GameData.elemander_pads_unlocked else "Elemander Pads: OFF",
		Vector2(10, 410), _on_elemander_pads_toggled)
	canvas.add_child(elemander_pads_button)

	golden_cloak_button = _make_toggle_button(
		"Golden Cloak: ON" if GameData.golden_cloak_unlocked else "Golden Cloak: OFF",
		Vector2(10, 450), _on_golden_cloak_toggled)
	canvas.add_child(golden_cloak_button)

	hollowscale_button = _make_toggle_button(
		"Hollowscale: ON" if GameData.hollowscale_unlocked else "Hollowscale: OFF",
		Vector2(10, 490), _on_hollowscale_toggled)
	canvas.add_child(hollowscale_button)

	danger_sense_button = _make_toggle_button(
		"Danger Sense: ON" if GameData.danger_sense_unlocked else "Danger Sense: OFF",
		Vector2(10, 530), _on_danger_sense_toggled)
	canvas.add_child(danger_sense_button)

	reset_cooldowns_button = _make_toggle_button(
		"No Cooldowns: ON" if GameData.dev_no_cooldowns else "No Cooldowns: OFF",
		Vector2(10, 570), _on_reset_cooldowns_toggled)
	canvas.add_child(reset_cooldowns_button)

	canvas.add_child(_make_toggle_button("Give Respecs (Dev)", Vector2(10, 610), _on_give_respecs))
	canvas.add_child(_make_toggle_button("Max All Skills (Dev)", Vector2(10, 650), _on_max_all_skills))
	canvas.add_child(_make_toggle_button("Max Level 100 (Dev)", Vector2(10, 690), _on_max_level))

	fixed_zoom_button = _make_toggle_button(
		"Zoom 1x: ON" if GameData.dev_fixed_zoom_1x else "Zoom 1x: OFF",
		Vector2(10, 730), _on_fixed_zoom_toggled)
	canvas.add_child(fixed_zoom_button)

	screen_shake_button = _make_toggle_button(
		"Screen Shake: ON" if GameData.screen_shake_enabled else "Screen Shake: OFF",
		Vector2(10, 770), _on_screen_shake_toggled)
	canvas.add_child(screen_shake_button)

	canvas.add_child(_make_toggle_button("Level Up (Dev)", Vector2(10, 810), _on_level_up))

	ant_queen_buff_button = _make_toggle_button(
		"Ant Queen Buff: ON" if GameData.ant_queen_defeated else "Ant Queen Buff: OFF",
		Vector2(10, 850), _on_ant_queen_buff_toggled)
	canvas.add_child(ant_queen_buff_button)

	canvas.add_child(_make_toggle_button("Reset to Lvl 1 (Dev)", Vector2(10, 890), _on_reset_to_level_1))

	fixed_zoom_0_1x_button = _make_toggle_button(
		"Zoom 0.1x: ON" if GameData.dev_fixed_zoom_0_1x else "Zoom 0.1x: OFF",
		Vector2(10, 930), _on_fixed_zoom_0_1x_toggled)
	canvas.add_child(fixed_zoom_0_1x_button)

func _on_give_respecs():
	GameData.add_item("respecElana")
	GameData.add_item("respecGlint")
	refresh_slots()

func _on_max_all_skills():
	GameData.dev_max_all_skills()
	_refresh_skill_tree()
	_refresh_glint_skill_tree()

# Inverse of _on_max_all_skills()/_on_max_level() — back to level 1 with
# every skill point unspent. Same UI refresh calls as _on_max_all_skills()
# since the skill trees' button states need to reflect the now-zeroed levels.
func _on_reset_to_level_1():
	GameData.dev_reset_to_level_1()
	_refresh_skill_tree()
	_refresh_glint_skill_tree()

func _on_max_level():
	GameData.dev_set_max_level()

# Unlike _on_max_level()'s straight-to-100 cheat loop, this goes through
# the real gain_xp() path for exactly one level — same SP/max_hp rewards a
# real level-up grants, useful for testing that flow specifically without
# jumping the whole way to 100.
func _on_level_up():
	GameData.gain_xp(GameData.xp_to_next() - GameData.xp)

func _on_fill_herbs():
	for herb in ["herbElementalFire", "herbElementalFrost", "herbElementalElec", "herbAgility", "herbHeal", "herbPower"]:
		for i in 2:
			GameData.add_item(herb)
	refresh_slots()

func _on_fill_ores():
	for ore_id in GameData.ORE_REGISTRY.keys():
		for i in 2:
			GameData.add_item(ore_id)
	refresh_slots()

func _on_herb_icon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		GameData.cancel_herb()

func _on_ore_icon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		GameData.cancel_ore()

func _on_wall_jump_toggled():
	GameData.wall_jump_enabled = not GameData.wall_jump_enabled
	wall_jump_button.text = "Wall Jump: ON" if GameData.wall_jump_enabled else "Wall Jump: OFF"

func _on_double_jump_toggled():
	GameData.double_jump_enabled = not GameData.double_jump_enabled
	double_jump_button.text = "Double Jump: ON" if GameData.double_jump_enabled else "Double Jump: OFF"

func _on_hp_bars_toggled():
	GameData.show_hp_bars = not GameData.show_hp_bars
	hp_bars_button.text = "HP Bars: ON" if GameData.show_hp_bars else "HP Bars: OFF"

func _on_dodge_toggled():
	GameData.dodge_enabled = not GameData.dodge_enabled
	dodge_button.text = "Dodge Roll: ON" if GameData.dodge_enabled else "Dodge Roll: OFF"

func _on_item_cooldown_toggled():
	GameData.item_use_cooldown_enabled = not GameData.item_use_cooldown_enabled
	item_cooldown_button.text = "Item Cooldown: ON" if GameData.item_use_cooldown_enabled else "Item Cooldown: OFF"

func _on_air_dash_toggled():
	GameData.air_dash_enabled = not GameData.air_dash_enabled
	air_dash_button.text = "Air Dash: ON" if GameData.air_dash_enabled else "Air Dash: OFF"

func _on_elemander_pads_toggled():
	GameData.elemander_pads_unlocked = not GameData.elemander_pads_unlocked
	elemander_pads_button.text = "Elemander Pads: ON" if GameData.elemander_pads_unlocked else "Elemander Pads: OFF"

func _on_golden_cloak_toggled():
	GameData.golden_cloak_unlocked = not GameData.golden_cloak_unlocked
	golden_cloak_button.text = "Golden Cloak: ON" if GameData.golden_cloak_unlocked else "Golden Cloak: OFF"

func _on_hollowscale_toggled():
	GameData.hollowscale_unlocked = not GameData.hollowscale_unlocked
	hollowscale_button.text = "Hollowscale: ON" if GameData.hollowscale_unlocked else "Hollowscale: OFF"

func _on_danger_sense_toggled():
	GameData.danger_sense_unlocked = not GameData.danger_sense_unlocked
	danger_sense_button.text = "Danger Sense: ON" if GameData.danger_sense_unlocked else "Danger Sense: OFF"

# Ant Queen's death reward — +50% reduction to hazard damage (spikes, vine
# thorns, Hollowfang's falling rocks) — see elana.gd's take_damage() and
# GameData.HAZARD_DAMAGE_REDUCTION. Same dev-toggle pattern as the other
# boss blessings above, for testing without actually killing her first.
func _on_ant_queen_buff_toggled():
	GameData.ant_queen_defeated = not GameData.ant_queen_defeated
	ant_queen_buff_button.text = "Ant Queen Buff: ON" if GameData.ant_queen_defeated else "Ant Queen Buff: OFF"

func _on_reset_cooldowns_toggled():
	GameData.dev_no_cooldowns = not GameData.dev_no_cooldowns
	reset_cooldowns_button.text = "No Cooldowns: ON" if GameData.dev_no_cooldowns else "No Cooldowns: OFF"

func _on_fixed_zoom_toggled():
	GameData.dev_fixed_zoom_1x = not GameData.dev_fixed_zoom_1x
	fixed_zoom_button.text = "Zoom 1x: ON" if GameData.dev_fixed_zoom_1x else "Zoom 1x: OFF"
	# Mutually exclusive with the 0.1x toggle (2026-08-22) -- both flip
	# elana.gd's camera zoom into a fixed debug value, so leaving both on
	# would just mean whichever _update_camera_zoom() checks first silently
	# wins; turning the other off here keeps the button labels honest.
	if GameData.dev_fixed_zoom_1x and GameData.dev_fixed_zoom_0_1x:
		GameData.dev_fixed_zoom_0_1x = false
		fixed_zoom_0_1x_button.text = "Zoom 0.1x: OFF"

func _on_fixed_zoom_0_1x_toggled():
	GameData.dev_fixed_zoom_0_1x = not GameData.dev_fixed_zoom_0_1x
	fixed_zoom_0_1x_button.text = "Zoom 0.1x: ON" if GameData.dev_fixed_zoom_0_1x else "Zoom 0.1x: OFF"
	if GameData.dev_fixed_zoom_0_1x and GameData.dev_fixed_zoom_1x:
		GameData.dev_fixed_zoom_1x = false
		fixed_zoom_button.text = "Zoom 1x: OFF"

func _on_screen_shake_toggled():
	GameData.screen_shake_enabled = not GameData.screen_shake_enabled
	screen_shake_button.text = "Screen Shake: ON" if GameData.screen_shake_enabled else "Screen Shake: OFF"

# Screen-space tooltip (crisp text, unaffected by camera zoom) that manually
# tracks the player's projected screen position each frame so it still visually
# follows her, without living in world-space like GameData.make_stun_indicator().
func _show_item_tooltip(item_id: String) -> void:
	if not CONSUME_TOOLTIP_TEXT.has(item_id):
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var canvas = CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	var box = Panel.new()
	box.add_theme_stylebox_override("panel", _make_item_tooltip_style())
	box.size = Vector2(200, 70)
	box.clip_contents = true
	canvas.add_child(box)

	var label = Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.BLACK)
	var full_text: String = CONSUME_TOOLTIP_TEXT[item_id]
	label.text = full_text
	label.visible_characters = 0
	box.add_child(label)

	var world_offset = Vector2(12, -40)

	# Typewriter reveal — letter by letter, while still tracking her position
	var revealed: float = 0.0
	while revealed < full_text.length() and is_instance_valid(player):
		box.position = get_viewport().get_canvas_transform() * (player.global_position + world_offset)
		revealed += ITEM_TOOLTIP_TYPEWRITER_CPS * get_process_delta_time()
		label.visible_characters = int(min(revealed, full_text.length()))
		await get_tree().process_frame
	label.visible_characters = -1

	# Hold with the full line visible
	var expire_at = Time.get_ticks_msec() + int(ITEM_TOOLTIP_DURATION * 1000)
	while is_instance_valid(player) and Time.get_ticks_msec() < expire_at:
		box.position = get_viewport().get_canvas_transform() * (player.global_position + world_offset)
		await get_tree().process_frame

	canvas.queue_free()

# Same look as the dialogue/prompt system's red-bordered boxes, for a
# consistent UI language across every "system" popup.
func _make_item_tooltip_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(2)
	style.border_color = Color(0.8, 0.1, 0.1)
	style.set_corner_radius_all(3)
	return style

func _setup_bottom_hud():
	var slot_size = 56
	var slot_gap = 4
	var num_slots = 10
	var total_slots_width = num_slots * slot_size + (num_slots - 1) * slot_gap
	var panel_height = 160

	var hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	_gameplay_layers.append(hud_layer)

	var panel = ColorRect.new()
	panel.color = Color(0.1, 0.1, 0.12, 1.0)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 220
	panel.offset_right = -220
	panel.offset_top = -panel_height
	panel.offset_bottom = 0
	hud_layer.add_child(panel)

	# Minimap placeholder (bottom-left) with live depth readout
	var minimap_style = StyleBoxFlat.new()
	minimap_style.bg_color = Color(0.04, 0.04, 0.06)
	minimap_style.set_border_width_all(2)
	minimap_style.border_color = Color(0.3, 0.3, 0.38)
	var minimap = Panel.new()
	minimap.add_theme_stylebox_override("panel", minimap_style)
	minimap.offset_left = 6
	minimap.offset_top = 6
	minimap.offset_right = 116
	minimap.offset_bottom = 116
	panel.add_child(minimap)
	var minimap_label = Label.new()
	minimap_label.text = "MINIMAP"
	minimap_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	minimap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minimap_label.add_theme_font_size_override("font_size", 11)
	minimap_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4))
	minimap.add_child(minimap_label)
	_depth_label = Label.new()
	_depth_label.text = "0 m"
	_depth_label.anchor_left = 0.0
	_depth_label.anchor_right = 1.0
	_depth_label.anchor_top = 1.0
	_depth_label.anchor_bottom = 1.0
	_depth_label.offset_top = -22
	_depth_label.offset_bottom = -4
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_depth_label.add_theme_font_size_override("font_size", 12)
	_depth_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	minimap.add_child(_depth_label)
	_sp_badge = Label.new()
	_sp_badge.anchor_left = 0.0
	_sp_badge.anchor_right = 1.0
	_sp_badge.offset_top = 4
	_sp_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sp_badge.add_theme_font_size_override("font_size", 10)
	_sp_badge.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	_sp_badge.visible = false
	minimap.add_child(_sp_badge)

	# Ability indicators — Last Stand, Hollowscale, Danger Sense, in a row.
	# Locked/grey until obtained, pulses when ready, counts down on cooldown.
	var ls = _make_cooldown_box(-298)
	_last_stand_box = ls["box"]
	_last_stand_label = ls["label"]
	_last_stand_style = ls["style"]
	panel.add_child(_last_stand_box)

	var hs = _make_cooldown_box(-246)
	_hollowscale_box = hs["box"]
	_hollowscale_label = hs["label"]
	_hollowscale_style = hs["style"]
	panel.add_child(_hollowscale_box)

	var ds = _make_cooldown_box(-194)
	_danger_sense_box = ds["box"]
	_danger_sense_label = ds["label"]
	_danger_sense_style = ds["style"]
	panel.add_child(_danger_sense_box)

	# Glint stack counters (Overcharge / Combo / Executioner)
	for entry in [["oc", "Overcharge ×0", 122], ["cb", "Combo ×0", 136], ["ex", "Executioner ×0", 150]]:
		var lbl = Label.new()
		lbl.text = entry[1]
		lbl.position = Vector2(8, entry[2])
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
		panel.add_child(lbl)
		_stack_labels[entry[0]] = lbl

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", slot_gap)
	hbox.anchor_left = 0.5
	hbox.offset_left = -total_slots_width / 2.0
	hbox.offset_top = 6
	panel.add_child(hbox)

	for i in range(num_slots):
		var slot = ItemSlot.new()
		slot.slot_index = i
		slot.slot_type = ItemSlot.SlotType.QUICKSLOT
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		hbox.add_child(slot)
		quickslot_slot_nodes.append(slot)
	quickslot_slot_nodes[selected_slot].set_selected(true)

	hp_bg = ColorRect.new()
	hp_bg.color = Color(0.3, 0.08, 0.08)
	hp_bg.anchor_left = 0.5
	hp_bg.anchor_right = 0.5
	hp_bg.anchor_top = 0.0
	hp_bg.anchor_bottom = 0.0
	hp_bg.offset_left = -total_slots_width / 2.0
	hp_bg.offset_right = total_slots_width / 2.0
	hp_bg.offset_top = 70
	hp_bg.offset_bottom = 88
	panel.add_child(hp_bg)

	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.15, 0.75, 0.15)
	hp_bg.add_child(hp_fill)

	_hp_text = Label.new()
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.add_theme_font_size_override("font_size", 10)
	_hp_text.add_theme_color_override("font_color", Color.WHITE)
	hp_bg.add_child(_hp_text)

	_shield_bg = ColorRect.new()
	_shield_bg.color = Color(0.18, 0.14, 0.04)
	_shield_bg.anchor_left = 0.5
	_shield_bg.anchor_right = 0.5
	_shield_bg.anchor_top = 0.0
	_shield_bg.anchor_bottom = 0.0
	_shield_bg.offset_left = -total_slots_width / 2.0
	_shield_bg.offset_right = total_slots_width / 2.0
	_shield_bg.offset_top = 92
	_shield_bg.offset_bottom = 101
	panel.add_child(_shield_bg)

	_shield_fill = ColorRect.new()
	_shield_fill.color = Color(0.95, 0.82, 0.15)
	_shield_bg.add_child(_shield_fill)

	_xp_bg = ColorRect.new()
	_xp_bg.color = Color(0.08, 0.06, 0.12)
	_xp_bg.anchor_left = 0.0
	_xp_bg.anchor_right = 1.0
	_xp_bg.anchor_top = 1.0
	_xp_bg.anchor_bottom = 1.0
	_xp_bg.offset_top = -6
	_xp_bg.offset_bottom = 0
	hud_layer.add_child(_xp_bg)

	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(0.55, 0.25, 0.85)
	_xp_bg.add_child(_xp_fill)

	_level_label = Label.new()
	_level_label.anchor_top = 1.0
	_level_label.anchor_bottom = 1.0
	_level_label.offset_left = 6
	_level_label.offset_top = -26
	_level_label.offset_bottom = -8
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	hud_layer.add_child(_level_label)

	_herb_indicator = Control.new()
	_herb_indicator.anchor_left = 1.0
	_herb_indicator.anchor_right = 1.0
	_herb_indicator.anchor_top = 0.0
	_herb_indicator.anchor_bottom = 1.0
	_herb_indicator.offset_left = -120
	_herb_indicator.offset_right = -66
	panel.add_child(_herb_indicator)

	_herb_bar_bg = ColorRect.new()
	_herb_bar_bg.color = Color(0.12, 0.12, 0.15)
	_herb_bar_bg.anchor_left = 0.0
	_herb_bar_bg.anchor_right = 1.0
	_herb_bar_bg.offset_top = 4
	_herb_bar_bg.offset_bottom = 96
	_herb_indicator.add_child(_herb_bar_bg)

	_herb_bar_fill = ColorRect.new()
	_herb_bar_bg.add_child(_herb_bar_fill)

	_herb_icon = ColorRect.new()
	_herb_icon.anchor_left = 0.0
	_herb_icon.anchor_right = 1.0
	_herb_icon.offset_top = 100
	_herb_icon.offset_bottom = 120
	_herb_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_herb_icon.gui_input.connect(_on_herb_icon_input)
	_herb_indicator.add_child(_herb_icon)

	_herb_time_label = _make_indicator_label(_herb_indicator, 122)
	_herb_name_label = _make_indicator_label(_herb_indicator, 138)

	_ore_indicator = Control.new()
	_ore_indicator.anchor_left = 1.0
	_ore_indicator.anchor_right = 1.0
	_ore_indicator.anchor_top = 0.0
	_ore_indicator.anchor_bottom = 1.0
	_ore_indicator.offset_left = -60
	_ore_indicator.offset_right = -6
	panel.add_child(_ore_indicator)

	_ore_bar_bg = ColorRect.new()
	_ore_bar_bg.color = Color(0.12, 0.12, 0.15)
	_ore_bar_bg.anchor_left = 0.0
	_ore_bar_bg.anchor_right = 1.0
	_ore_bar_bg.offset_top = 4
	_ore_bar_bg.offset_bottom = 96
	_ore_indicator.add_child(_ore_bar_bg)

	_ore_bar_fill = ColorRect.new()
	_ore_bar_bg.add_child(_ore_bar_fill)

	_ore_icon = ColorRect.new()
	_ore_icon.anchor_left = 0.0
	_ore_icon.anchor_right = 1.0
	_ore_icon.offset_top = 100
	_ore_icon.offset_bottom = 120
	_ore_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_ore_icon.gui_input.connect(_on_ore_icon_input)
	_ore_indicator.add_child(_ore_icon)

	_ore_time_label = _make_indicator_label(_ore_indicator, 122)
	_ore_name_label = _make_indicator_label(_ore_indicator, 138)

func _setup_boss_hp_bar() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_gameplay_layers.append(layer)

	var bar_width = 480
	_boss_hp_root = Control.new()
	_boss_hp_root.anchor_left = 0.5
	_boss_hp_root.anchor_right = 0.5
	_boss_hp_root.offset_left = -bar_width / 2.0
	_boss_hp_root.offset_right = bar_width / 2.0
	_boss_hp_root.offset_top = 18
	_boss_hp_root.offset_bottom = 44
	_boss_hp_root.visible = false
	layer.add_child(_boss_hp_root)

	_boss_hp_name_label = Label.new()
	_boss_hp_name_label.anchor_left = 0.0
	_boss_hp_name_label.anchor_right = 1.0
	_boss_hp_name_label.offset_top = -20
	_boss_hp_name_label.offset_bottom = -2
	_boss_hp_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp_name_label.add_theme_font_size_override("font_size", 14)
	_boss_hp_name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_boss_hp_root.add_child(_boss_hp_name_label)

	_boss_hp_bg = ColorRect.new()
	_boss_hp_bg.color = Color(0.1, 0.08, 0.08)
	_boss_hp_bg.anchor_left = 0.0
	_boss_hp_bg.anchor_right = 1.0
	_boss_hp_bg.anchor_top = 0.0
	_boss_hp_bg.anchor_bottom = 1.0
	_boss_hp_root.add_child(_boss_hp_bg)

	_boss_hp_fill = ColorRect.new()
	_boss_hp_fill.color = Color(0.75, 0.12, 0.12)
	_boss_hp_bg.add_child(_boss_hp_fill)

# Shows/hides and fills the top-of-screen bar based on whether a
# "bosses"-group member is currently in the scene and alive — works for
# any future boss, not just Hollowfang, as long as it exposes hp/max_hp
# (every boss so far does, same convention as regular enemies). Only
# re-searches the group when the cached reference goes stale (dies/frees),
# not every single frame.
func _update_boss_hp_bar() -> void:
	# Only shows once the boss-arena reveal cutscene has actually started
	# (GameData.boss_zoom_active, set by dialog_marker.gd's CAMERA_PAN
	# cutscene) — not just whenever a "bosses"-group member happens to
	# exist in the scene, which could be well before the player's even
	# supposed to have seen it yet. boss_zoom_active only clears via
	# reset_boss_camera() (boss death or player respawn), so hiding follows
	# the same lifecycle automatically.
	if not GameData.boss_zoom_active:
		_boss_hp_root.visible = false
		return
	if _current_boss == null or not is_instance_valid(_current_boss):
		_current_boss = get_tree().get_first_node_in_group("bosses")
	if _current_boss == null or not is_instance_valid(_current_boss) or _current_boss.hp <= 0:
		_boss_hp_root.visible = false
		return
	_boss_hp_root.visible = true
	_boss_hp_name_label.text = _current_boss.name.to_upper()
	if _boss_hp_bg.size.x > 0:
		var ratio = clamp(float(_current_boss.hp) / float(_current_boss.max_hp), 0.0, 1.0)
		_boss_hp_fill.size = Vector2(_boss_hp_bg.size.x * ratio, _boss_hp_bg.size.y)

func _make_indicator_label(parent: Control, top: int) -> Label:
	var lbl = Label.new()
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.offset_top = top
	lbl.offset_bottom = top + 16
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	parent.add_child(lbl)
	return lbl

func _select_slot(idx: int):
	quickslot_slot_nodes[selected_slot].set_selected(false)
	selected_slot = idx
	quickslot_slot_nodes[selected_slot].set_selected(true)

func _setup_inventory():
	var layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_gameplay_layers.append(layer)
	inventory_overlay = ColorRect.new()
	inventory_overlay.color = Color(0.08, 0.08, 0.1, 1.0)
	inventory_overlay.anchor_left = 0.05
	inventory_overlay.anchor_right = 0.95
	inventory_overlay.anchor_top = 0.05
	inventory_overlay.anchor_bottom = 1.0
	inventory_overlay.offset_bottom = -164
	inventory_overlay.visible = false
	layer.add_child(inventory_overlay)

	var margin = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	inventory_overlay.add_child(margin)

	var hbox = HBoxContainer.new()
	margin.add_child(hbox)

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	hbox.add_child(grid)

	for i in 25:
		var slot = ItemSlot.new()
		slot.slot_index = i
		slot.slot_type = ItemSlot.SlotType.INVENTORY
		slot.custom_minimum_size = Vector2(52, 52)
		grid.add_child(slot)
		inventory_slot_nodes.append(slot)

func refresh_slots() -> void:
	for slot in inventory_slot_nodes:
		slot.refresh()
	for slot in quickslot_slot_nodes:
		slot.refresh()

func _setup_character_screen():
	var layer = CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_gameplay_layers.append(layer)
	char_overlay = ColorRect.new()
	char_overlay.color = Color(0.08, 0.08, 0.1, 1.0)
	char_overlay.anchor_left = 0.05
	char_overlay.anchor_right = 0.95
	char_overlay.anchor_top = 0.05
	char_overlay.anchor_bottom = 1.0
	char_overlay.offset_bottom = -164
	char_overlay.visible = false
	layer.add_child(char_overlay)

	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	char_overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "CHARACTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.87, 0.72))
	vbox.add_child(title)

	_char_spacer(vbox, 4)
	_stat_labels["level"] = _char_row(vbox, "Level")
	_stat_labels["xp"] = _char_row(vbox, "XP")
	_char_divider(vbox)

	var section = Label.new()
	section.text = "STATS"
	section.add_theme_font_size_override("font_size", 13)
	section.add_theme_color_override("font_color", Color(0.55, 0.55, 0.72))
	vbox.add_child(section)

	for entry: Array in [
		["Max HP", "max_hp"], ["Attack DMG", "attack"], ["Magic DMG", "magic"],
		["Speed", "speed"], ["Attack Speed", "attack_speed"], ["HP Regen", "hp_regen"],
		["Defense", "defense"], ["Dodge Chance", "dodge_chance"], ["Elemental Resist", "elem_resist_display"],
		["Hazard Resist", "hazard_resist"], ["Crit Chance", "crit_chance"], ["Crit Damage", "crit_damage"]
	]:
		_stat_labels[entry[1]] = _char_row(vbox, entry[0])

func _char_row(parent: VBoxContainer, label_text: String) -> Label:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.85))
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)
	var val = Label.new()
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(110, 0)
	val.add_theme_color_override("font_color", Color.WHITE)
	val.add_theme_font_size_override("font_size", 14)
	row.add_child(val)
	return val

func _char_spacer(parent: VBoxContainer, height: int) -> void:
	var s = Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

func _char_divider(parent: VBoxContainer) -> void:
	_char_spacer(parent, 2)
	var div = ColorRect.new()
	div.color = Color(0.3, 0.3, 0.45, 0.6)
	div.custom_minimum_size = Vector2(0, 1)
	parent.add_child(div)
	_char_spacer(parent, 2)

func _set_stat(key: String, value: String, boosted: bool = false) -> void:
	_stat_labels[key].text = value
	var color = Color(0.35, 1.0, 0.45) if boosted else Color.WHITE
	_stat_labels[key].add_theme_color_override("font_color", color)

func refresh_character_screen() -> void:
	if _stat_labels.is_empty():
		return
	_stat_labels["level"].text = str(GameData.level)
	_stat_labels["xp"].text = "%d / %d" % [GameData.xp, GameData.xp_to_next()]
	_set_stat("max_hp", str(GameData.max_hp))
	_set_stat("attack", str(int(float(GameData.get_attack_damage()) * GameData.damage_multiplier)), GameData.damage_multiplier != 1.0)
	_set_stat("magic", str(int(float(GameData.get_magic_damage()) * GameData.damage_multiplier)), GameData.damage_multiplier != 1.0)
	var boosted_speed = GameData.base_speed * (1.0 + GameData.move_speed_herb_bonus / 100.0)
	_set_stat("speed", "%.0f" % boosted_speed, GameData.move_speed_herb_bonus > 0.0)
	var spd_total = min(GameData.attack_speed_stat + GameData.weapon_attack_speed + GameData.attack_speed_herb_bonus, 100)
	_set_stat("attack_speed", "%.2fs" % max(0.05, abs(spd_total - 100.0) / 100.0), GameData.attack_speed_herb_bonus > 0)
	_set_stat("hp_regen", "%.1f / sec" % (GameData.hp_regen + GameData.hp_regen_herb_bonus), GameData.hp_regen_herb_bonus > 0)
	_set_stat("defense", str(GameData.get_defense()))
	_set_stat("dodge_chance", "%.0f%%" % (GameData.dodge_chance * 100.0))
	# Ant Queen's death reward — see elana.gd's take_damage() and
	# GameData.HAZARD_DAMAGE_REDUCTION. 0% until she's actually defeated
	# (or the dev toggle is flipped on).
	var hazard_resist_pct = GameData.HAZARD_DAMAGE_REDUCTION * 100.0 if GameData.ant_queen_defeated else 0.0
	_set_stat("hazard_resist", "%.0f%%" % hazard_resist_pct, GameData.ant_queen_defeated)
	_set_stat("crit_chance", "%.0f%%" % (GameData.glint_crit_chance * 100.0), GameData.glint_crit_chance > 0.0)
	_set_stat("crit_damage", "%.2fx" % GameData.glint_crit_dmg_mult, GameData.glint_crit_dmg_mult > 1.5)
	var resist_element := ""
	if GameData.active_herb != null:
		match GameData.active_herb.item_id:
			"herbElementalFire": resist_element = "fire"
			"herbElementalFrost": resist_element = "frost"
			"herbElementalElec": resist_element = "elec"
	var resist_val = GameData.get_elemental_resist_for(resist_element)
	_stat_labels["elem_resist_display"].text = "%.0f%%" % (resist_val * 100.0)
	var resist_color = Color.WHITE
	match resist_element:
		"fire": resist_color = Color(0.95, 0.35, 0.1)
		"frost": resist_color = Color(0.4, 0.75, 0.95)
		"elec": resist_color = Color(0.95, 0.9, 0.15)
	_stat_labels["elem_resist_display"].add_theme_color_override("font_color", resist_color)

# ── Shared skill tree UI ─────────────────────────────────────────────────────
# Both trees (Elana and Glint) are built and refreshed by the same code;
# each tree only supplies data, layout, and colors.

const SKILL_NODE_LOCKED_COLOR := Color(0.45, 0.45, 0.45)

const ELANA_TREE_PALETTE := {
	"maxed":       Color(0.6, 1.0, 0.6),
	"maxed_skill": Color(1.0, 0.85, 0.3),
	"avail":       Color(0.85, 1.0, 0.85),
	"avail_skill": Color(1.0, 0.75, 0.4),
	"invested":    Color(0.5, 0.8, 0.5),
}

const GLINT_TREE_PALETTE := {
	"maxed":       Color(0.55, 0.95, 1.0),
	"maxed_skill": Color(0.55, 0.95, 1.0),
	"avail":       Color(0.8, 0.95, 1.0),
	"avail_skill": Color(0.8, 0.95, 1.0),
	"invested":    Color(0.4, 0.7, 0.85),
}

# Builds overlay, title, SP label, hint, scrollable canvas, connection lines,
# section labels, and node buttons. Returns the pieces the caller keeps.
func _build_tree_overlay(cfg: Dictionary) -> Dictionary:
	var layer = CanvasLayer.new()
	layer.layer = cfg["layer"]
	add_child(layer)
	_gameplay_layers.append(layer)

	var overlay = ColorRect.new()
	overlay.color = cfg["bg_color"]
	overlay.anchor_left = 0.03
	overlay.anchor_right = 0.97
	overlay.anchor_top = 0.04
	overlay.anchor_bottom = 1.0
	overlay.offset_bottom = -164
	overlay.visible = false
	layer.add_child(overlay)

	var title = Label.new()
	title.text = cfg["title"]
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", cfg["accent_color"])
	overlay.add_child(title)

	var sp_label = Label.new()
	sp_label.text = "SP: 0"
	sp_label.anchor_right = 1.0
	sp_label.position = Vector2(-90, 8)
	sp_label.add_theme_font_size_override("font_size", 15)
	sp_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.3))
	overlay.add_child(sp_label)

	var hint = Label.new()
	hint.text = "Click a node to invest 1 SP  ·  Scroll to pan"
	hint.position = Vector2(16, 28)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", cfg["hint_color"])
	overlay.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay.add_child(scroll)

	var content = Control.new()
	content.custom_minimum_size = cfg["content_size"]
	scroll.add_child(content)

	var drawer = preload("res://skill_line_drawer.gd").new()
	drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drawer.node_positions = cfg["positions"]
	drawer.connections = cfg["connections"]
	content.add_child(drawer)

	for sl in cfg["section_labels"]:
		var lbl := Label.new()
		lbl.text = sl[0]
		lbl.position = Vector2(int(sl[1]), 75)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", cfg["section_label_color"])
		content.add_child(lbl)

	var buttons: Dictionary = {}
	var on_pressed: Callable = cfg["on_node_pressed"]
	for node_id in cfg["positions"].keys():
		var pos_arr: Array = cfg["positions"][node_id]
		var btn := Button.new()
		btn.position = Vector2(pos_arr[0], pos_arr[1])
		btn.size = Vector2(64, 64)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(on_pressed.bind(node_id))
		content.add_child(btn)
		buttons[node_id] = btn

	return {"overlay": overlay, "sp_label": sp_label, "buttons": buttons, "drawer": drawer}

func _refresh_tree(buttons: Dictionary, data: Dictionary, get_level: Callable, can_spend_fn: Callable, drawer, palette: Dictionary) -> void:
	for node_id in buttons.keys():
		if not data.has(node_id):
			continue
		var btn: Button = buttons[node_id]
		var node: Dictionary = data[node_id]
		var cur_lvl: int = get_level.call(node_id)
		var max_lvl: int = int(node["max_level"])
		var is_skill: bool = node["type"] == "skill"
		var can_spend: bool = can_spend_fn.call(node_id)
		var is_maxed: bool = cur_lvl >= max_lvl

		btn.text = node["name"]
		var lvl_str: String
		if is_maxed:
			lvl_str = "MAXED"
		elif is_skill:
			lvl_str = "UNLOCKED" if cur_lvl >= 1 else "LOCKED"
		else:
			lvl_str = "Lv %d / %d" % [cur_lvl, max_lvl]
		btn.tooltip_text = "%s  [%s]\n%s" % [node["name"], lvl_str, node.get("desc", "")]

		if is_maxed:
			btn.modulate = palette["maxed_skill"] if is_skill else palette["maxed"]
		elif can_spend:
			btn.modulate = palette["avail_skill"] if is_skill else palette["avail"]
		elif cur_lvl > 0:
			btn.modulate = palette["invested"]
		else:
			btn.modulate = SKILL_NODE_LOCKED_COLOR

	if drawer:
		drawer.queue_redraw()

func _setup_skill_tree():
	# Unified positions (all paths on one canvas)
	var positions: Dictionary = {
		# Shared gateway — centered at x=860
		"herb_mastery":       [860, 10],
		"quick_digestion":    [700, 10],
		# Always owned, standalone — deliberately not wired into any prereq chain
		"air_dash_node":      [1020, 10],
		# Life path — left column starting x=10
		"vitality":           [10,  100],
		"iron_body":          [155, 100],
		"herb_heal_plus":     [10,  175],
		"overheal_shield":    [155, 175],
		"last_stand":         [300, 175],
		"fortitude":          [10,  250],
		"elem_resist":        [155, 250],
		"bulwark":            [300, 250],
		"life_barrier_skill": [10,  325],
		# Agile path — starting x=420
		"agility":            [420, 100],
		"wall_jump_skill":    [565, 100],
		"agility_herb_speed":        [420, 175],
		"attack_speed_node":  [565, 175],
		"flash_stun_skill":   [710, 175],
		"luminosity_plus":    [565, 250],
		"scouting_distance":  [710, 250],
		"phantom_blur":       [420, 250],
		"double_jump_skill":  [565, 325],
		"dodge_roll_skill":   [420, 325],
		# Elemental path — elemental_potency centered over 4 sub-cols at x=780,920,1060,1200
		"elemental_potency":         [990, 100],
		"casting_speed":      [780, 175],
		"ice_potency":        [920, 175],
		"fire_potency":       [1060,175],
		"lightning_potency":  [1200,175],
		"double_cast":        [780, 250],
		"freeze":             [920, 250],
		"burn":               [1060,250],
		"chain_lightning":    [1200,250],
		"shield_wall_skill":  [920, 325],
		"fire_blast_skill":   [1060,325],
		"storm_skill":        [1200,325],
		# Power path — starting x=1390
		"power_potency":         [1390,100],
		"anger_strikes":      [1535,100],
		"shockwave":          [1680,100],
		"penetration":        [1390,175],
		"berserker":          [1535,175],
		"executioner":        [1680,175],
		"bloodlust":          [1390,250],
		"blood_fury_skill":   [1390,325],
	}

	var connections: Array = [
		# Herb Mastery → each path root
		["herb_mastery","quick_digestion"],
		["herb_mastery","vitality"],
		["herb_mastery","agility"],
		["herb_mastery","elemental_potency"],
		["herb_mastery","power_potency"],
		# Life
		["vitality","iron_body"], ["vitality","herb_heal_plus"],
		["herb_heal_plus","overheal_shield"], ["herb_heal_plus","last_stand"],
		["herb_heal_plus","fortitude"],
		["fortitude","elem_resist"], ["fortitude","bulwark"],
		["fortitude","life_barrier_skill"],
		# Agile
		["agility","wall_jump_skill"], ["agility","agility_herb_speed"],
		["agility_herb_speed","attack_speed_node"], ["attack_speed_node","flash_stun_skill"],
		["agility_herb_speed","luminosity_plus"], ["agility_herb_speed","phantom_blur"],
		["luminosity_plus","scouting_distance"],
		["phantom_blur","double_jump_skill"], ["phantom_blur","dodge_roll_skill"],
		# Elemental
		["elemental_potency","casting_speed"], ["elemental_potency","ice_potency"],
		["elemental_potency","fire_potency"], ["elemental_potency","lightning_potency"],
		["casting_speed","double_cast"],
		["ice_potency","freeze"], ["freeze","shield_wall_skill"],
		["fire_potency","burn"], ["burn","fire_blast_skill"],
		["lightning_potency","chain_lightning"], ["chain_lightning","storm_skill"],
		# Power
		["power_potency","anger_strikes"], ["power_potency","shockwave"],
		["power_potency","penetration"],
		["penetration","berserker"], ["penetration","executioner"],
		["penetration","bloodlust"], ["bloodlust","blood_fury_skill"],
	]

	var built = _build_tree_overlay({
		"layer": 22,
		"bg_color": Color(0.05, 0.08, 0.05, 1.0),
		"title": "ELANA  ·  SKILL TREE",
		"accent_color": Color(0.85, 0.85, 0.65),
		"hint_color": Color(0.55, 0.55, 0.45),
		"content_size": Vector2(1860, 420),
		"positions": positions,
		"connections": connections,
		"section_labels": [["LIFE", 10], ["AGILE", 420], ["ELEMENTAL", 780], ["POWER", 1390]],
		"section_label_color": Color(0.6, 0.7, 0.55),
		"on_node_pressed": _on_skill_node_pressed,
	})
	skill_overlay = built["overlay"]
	_skill_sp_label = built["sp_label"]
	_skill_node_buttons = built["buttons"]
	_skill_line_drawer = built["drawer"]
	_refresh_skill_tree()

func _on_skill_node_pressed(node_id: String) -> void:
	GameData.spend_skill_point(node_id)
	_refresh_skill_tree()

func _refresh_skill_tree() -> void:
	_refresh_tree(_skill_node_buttons, GameData.SKILL_TREE_DATA,
		GameData.get_skill_level, GameData.can_spend_skill_point,
		_skill_line_drawer, ELANA_TREE_PALETTE)

func _setup_glint_skill_tree():
	var positions: Dictionary = {
		# Gateway — centered between the two branches
		"g_ore_mastery":      [660, 10],
		"g_quick_feed":       [515, 10],
		# Branch 1 — Weapon Enhancement (left, spine runs left→right)
		"g_weapon_damage":    [10,   100],
		"g_crit_chance":      [155,  100],
		"g_crit_damage":      [155,  175],
		"g_weapon_mastery":   [300,  100],
		"g_combo_strike":     [230,  175],
		"g_prime_form":       [370,  175],
		"g_lethal_striker":   [445,  100],
		"g_executioner":      [445,  175],
		"g_overcharge":       [590,  100],
		# Branch 2 — Herb Integration (right)
		"g_herb_integration": [1045, 100],
		"g_herb_elemental":  [800,  175],
		"g_slow":             [655,  250],
		"g_burn":             [800,  250],
		"g_chain":            [945,  250],
		"g_toxic":      [1000, 175],
		"g_lifesteal":  [1145, 175],
		"g_phantom":    [1290, 175],
	}

	var connections: Array = [
		["g_ore_mastery","g_weapon_damage"],
		["g_ore_mastery","g_quick_feed"],
		["g_ore_mastery","g_herb_integration"],
		# Weapon Enhancement spine + dead-ends
		["g_weapon_damage","g_crit_chance"],
		["g_crit_chance","g_crit_damage"],
		["g_crit_chance","g_weapon_mastery"],
		["g_weapon_mastery","g_combo_strike"],
		["g_weapon_mastery","g_prime_form"],
		["g_weapon_mastery","g_lethal_striker"],
		["g_lethal_striker","g_executioner"],
		["g_lethal_striker","g_overcharge"],
		# Herb Integration
		["g_herb_integration","g_herb_elemental"],
		["g_herb_integration","g_toxic"],
		["g_herb_integration","g_lifesteal"],
		["g_herb_integration","g_phantom"],
		["g_herb_elemental","g_slow"],
		["g_herb_elemental","g_burn"],
		["g_herb_elemental","g_chain"],
	]

	var built = _build_tree_overlay({
		"layer": 23,
		"bg_color": Color(0.04, 0.07, 0.09, 1.0),
		"title": "GLINT  ·  SKILL TREE",
		"accent_color": Color(0.6, 0.9, 1.0),
		"hint_color": Color(0.45, 0.55, 0.6),
		"content_size": Vector2(1400, 420),
		"positions": positions,
		"connections": connections,
		"section_labels": [["WEAPON ENHANCEMENT", 10], ["HERB INTEGRATION", 800]],
		"section_label_color": Color(0.5, 0.65, 0.75),
		"on_node_pressed": _on_glint_node_pressed,
	})
	glint_skill_overlay = built["overlay"]
	_glint_sp_label = built["sp_label"]
	_glint_node_buttons = built["buttons"]
	_glint_line_drawer = built["drawer"]
	_refresh_glint_skill_tree()

func _on_glint_node_pressed(node_id: String) -> void:
	GameData.spend_glint_skill_point(node_id)
	_refresh_glint_skill_tree()

func _refresh_glint_skill_tree() -> void:
	_refresh_tree(_glint_node_buttons, GameData.GLINT_SKILL_TREE_DATA,
		GameData.get_glint_skill_level, GameData.can_spend_glint_skill_point,
		_glint_line_drawer, GLINT_TREE_PALETTE)

func _setup_options() -> void:
	_options_layer = CanvasLayer.new()
	_options_layer.layer = 30
	_options_layer.visible = false
	add_child(_options_layer)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_options_layer.add_child(dim)

	_options_panel = ColorRect.new()
	_options_panel.color = Color(0.07, 0.07, 0.1, 1.0)
	_options_panel.anchor_left = 0.30
	_options_panel.anchor_right = 0.70
	_options_panel.anchor_top = 0.33
	_options_panel.anchor_bottom = 0.67
	_options_layer.add_child(_options_panel)

	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 16
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.87, 0.72))
	_options_panel.add_child(title)

	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_top = 0.0
	center.anchor_bottom = 1.0
	center.offset_top = 48
	_options_panel.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var resume_btn = _make_option_button("Resume")
	resume_btn.pressed.connect(_toggle_options)
	vbox.add_child(resume_btn)

	var settings_btn = _make_option_button("Settings")
	settings_btn.pressed.connect(_open_options_settings)
	vbox.add_child(settings_btn)

	var title_btn = _make_option_button("Exit to Title")
	title_btn.pressed.connect(_exit_to_title)
	vbox.add_child(title_btn)

	var desktop_btn = _make_option_button("Exit to Desktop")
	desktop_btn.pressed.connect(get_tree().quit)
	vbox.add_child(desktop_btn)

	_options_settings_panel = ColorRect.new()
	_options_settings_panel.color = Color(0.06, 0.06, 0.09, 1.0)
	_options_settings_panel.anchor_left = 0.25
	_options_settings_panel.anchor_right = 0.75
	_options_settings_panel.anchor_top = 0.15
	_options_settings_panel.anchor_bottom = 0.85
	_options_settings_panel.visible = false
	_options_layer.add_child(_options_settings_panel)

	var s_title = Label.new()
	s_title.text = "SETTINGS"
	s_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_title.anchor_right = 1.0
	s_title.offset_top = 24
	s_title.add_theme_font_size_override("font_size", 22)
	s_title.add_theme_color_override("font_color", Color(0.92, 0.87, 0.72))
	_options_settings_panel.add_child(s_title)

	var s_vbox = VBoxContainer.new()
	s_vbox.add_theme_constant_override("separation", 18)
	s_vbox.anchor_left = 0.08
	s_vbox.anchor_right = 0.92
	s_vbox.offset_top = 70
	_options_settings_panel.add_child(s_vbox)

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
	s_vbox.add_child(mode_label)

	var mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	s_vbox.add_child(mode_row)

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
	s_vbox.add_child(res_label)
	s_vbox.add_child(res_opt)

	for placeholder in ["Master Volume — coming soon", "SFX Volume — coming soon", "Controls — coming soon"]:
		var lbl = Label.new()
		lbl.text = placeholder
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5))
		s_vbox.add_child(lbl)

	var back_btn = _make_option_button("Back")
	back_btn.pressed.connect(_close_options_settings)
	s_vbox.add_child(back_btn)

func _make_option_button(label: String) -> Button:
	return GameData.make_styled_button(label)

func _toggle_options() -> void:
	_options_open = not _options_open
	_options_layer.visible = _options_open
	_options_panel.visible = true
	_options_settings_panel.visible = false
	if _options_open:
		_close_all_overlays()
	get_tree().paused = _options_open

func _open_options_settings() -> void:
	_options_panel.visible = false
	_options_settings_panel.visible = true

func _close_options_settings() -> void:
	_options_settings_panel.visible = false
	_options_panel.visible = true

func _exit_to_title() -> void:
	get_tree().paused = false
	_options_open = false
	_options_layer.visible = false
	set_hud_visible(false)
	# Dialogue/prompt/flash live on HUD (an autoload), not the scene tree, so
	# change_scene_to_file() alone won't touch them — a mid-cutscene bailout
	# would otherwise leave the dialogue box floating over the title screen.
	close_all_dialogue_ui()
	GameData.in_cutscene = false
	GameData.cutscene_scripted_move = false
	GameData.glint_position_locked = false
	GameData.glint_scouting = false
	GameData.glint_scout_returning = false
	get_tree().change_scene_to_file("res://title_screen.tscn")

# Force-closes the dialogue box, the red instruction prompt, the skip
# button, and the flash overlay regardless of what state they were
# mid-sequence in. Used for hard bailouts (exit to title) where nothing else
# will clean them up — HUD is an autoload, so without this a skip button
# left visible mid-cutscene would still be sitting there after returning to
# the title screen and starting a fresh run.
func close_all_dialogue_ui() -> void:
	_dialogue_active = false
	_dialogue_box.visible = false
	_prompt_active = false
	_prompt_box.visible = false
	_flash_overlay.color.a = 0.0
	hide_skip_button()

# Full-screen "YOU DIED" overlay — dims the screen, shows the title and a
# hint below it, then waits for literally any key/mouse/joypad press before
# resolving (caught in _input(), see _death_screen_active). elana.gd's die()
# awaits this before it actually does any of the respawn logic.
func show_death_screen() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 40
	add_child(canvas)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(dim)

	var title = Label.new()
	title.text = "YOU DIED"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.75, 0.08, 0.08))
	title.position = Vector2(-250, -50)
	title.size = Vector2(500, 60)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Press any key to return to last save point"
	subtitle.set_anchors_preset(Control.PRESET_CENTER)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	subtitle.position = Vector2(-250, 25)
	subtitle.size = Vector2(500, 30)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(subtitle)

	_death_screen_active = true
	while _death_screen_active:
		await get_tree().process_frame
	canvas.queue_free()


func _close_all_overlays():
	inventory_open = false
	inventory_overlay.visible = false
	char_screen_open = false
	char_overlay.visible = false
	skill_tree_open = false
	skill_overlay.visible = false
	glint_tree_open = false
	glint_skill_overlay.visible = false

func _toggle_inventory():
	var opening = not inventory_open
	_close_all_overlays()
	if opening:
		inventory_open = true
		inventory_overlay.visible = true

func _toggle_character_screen():
	var opening = not char_screen_open
	_close_all_overlays()
	if opening:
		char_screen_open = true
		char_overlay.visible = true
		refresh_character_screen()

func _toggle_skill_tree():
	var opening = not skill_tree_open
	_close_all_overlays()
	if opening:
		skill_tree_open = true
		skill_overlay.visible = true

func _toggle_glint_skill_tree():
	var opening = not glint_tree_open
	_close_all_overlays()
	if opening:
		glint_tree_open = true
		glint_skill_overlay.visible = true

# Dialogue advance is handled in _input(), not _unhandled_input() — it needs
# to win the race against "attack" (bound to the same left-click) regardless
# of whether attack itself is gated off during dialogue, and _input() fires
# before anything else gets a look at the event. set_input_as_handled() then
# stops it from reaching attack/anything else at all this frame.
func _input(event):
	if _death_screen_active:
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventJoypadButton and event.pressed):
			_death_screen_active = false
			get_viewport().set_input_as_handled()
		return
	if not _dialogue_active:
		return
	var advance = false
	if event.is_action_pressed("ui_accept"):
		advance = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		advance = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# A click landing on the visible Skip button is its own action, not a
		# dialogue-advance — since this function wins the race against every
		# other input handler (see comment above), left uncaught it would
		# consume the click here and set_input_as_handled() below would then
		# stop it from ever reaching the button's own "pressed" signal.
		if not (_skip_button.visible and _skip_button.get_global_rect().has_point(event.position)):
			advance = true
	if advance:
		_advance_dialogue()
		get_viewport().set_input_as_handled()

func _unhandled_input(event):
	# ESC/options is never locked — pausing should always work, cutscene or
	# prologue or not. Only guarded against the title screen itself (no
	# Elana in the tree yet means there's no gameplay to pause).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().get_first_node_in_group("player") == null:
			return
		var moleman_trade = get_tree().get_first_node_in_group("moleman_trade_ui")
		if moleman_trade:
			moleman_trade.get_parent().queue_free()
		elif _options_open:
			_toggle_options()
		elif inventory_open or char_screen_open or skill_tree_open or glint_tree_open:
			_close_all_overlays()
		else:
			_toggle_options()
		return

	if _dialogue_active:
		return
	# Between dialogue lines during a cutscene (e.g. a scripted walk beat, or
	# the gap right before a flash), _dialogue_active is briefly false — keep
	# menus locked for the whole cutscene, not just while a line is up. Also
	# locked for the whole prologue (game start through the Stone Being
	# cutscene), including the free-roam walk to reach her, not just the two
	# explicit cutscenes.
	if GameData.in_cutscene or not GameData.received_stone_being_power:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if not _options_open:
			if event.keycode == KEY_TAB or event.keycode == KEY_I:
				_toggle_inventory()
			elif event.keycode == KEY_C:
				_toggle_character_screen()
			elif event.keycode == KEY_K:
				_toggle_skill_tree()
			elif event.keycode == KEY_G:
				_toggle_glint_skill_tree()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				var idx = event.keycode - KEY_1
				if hovered_quickslot_slot >= 0:
					_swap_quickslots(hovered_quickslot_slot, idx)
				elif hovered_inventory_slot >= 0:
					_assign_to_quickslot(hovered_inventory_slot, idx)
				elif not inventory_open and not char_screen_open and not skill_tree_open and not glint_tree_open:
					_select_slot(idx)
					_use_selected_item()
			elif event.keycode == KEY_0:
				if hovered_quickslot_slot >= 0:
					_swap_quickslots(hovered_quickslot_slot, 9)
				elif hovered_inventory_slot >= 0:
					_assign_to_quickslot(hovered_inventory_slot, 9)
				elif not inventory_open and not char_screen_open and not skill_tree_open and not glint_tree_open:
					_select_slot(9)
					_use_selected_item()

func use_quickslot(idx: int) -> void:
	_select_slot(idx)
	_use_selected_item()

func _use_selected_item() -> void:
	var slot = GameData.quickslot_slots[selected_slot]
	if slot["item"] == "":
		return
	var item_id = slot["item"]
	# Key items (lore notes, etc.) have no quickslot effect — do nothing
	# rather than consuming/removing one if it was ever dragged in here.
	if GameData.KEY_ITEM_REGISTRY.has(item_id):
		return
	# Quick Feed: ores bypass the shared item-use cooldown entirely
	var quick_feed = GameData.ORE_REGISTRY.has(item_id) and GameData.get_glint_skill_level("g_quick_feed") >= 1
	# Quick Digestion: herbs bypass it too, same idea as Quick Feed but for herbs
	var quick_digestion = GameData.HERB_REGISTRY.has(item_id) and GameData.is_skill_unlocked("quick_digestion")
	if item_use_cooldown > 0.0 and GameData.item_use_cooldown_enabled and not quick_feed and not quick_digestion:
		return
	slot["count"] -= 1
	print("[consume] %s | slot %d | %d remaining" % [item_id, selected_slot, slot["count"]])
	if GameData.mark_item_seen(item_id):
		_show_item_tooltip(item_id)
	if slot["count"] <= 0:
		GameData.quickslot_slots[selected_slot] = {"item": "", "count": 0}
	if not quick_feed and not quick_digestion:
		item_use_cooldown = ITEM_USE_COOLDOWN
	if GameData.HERB_REGISTRY.has(item_id):
		GameData.apply_herb(item_id)
	elif GameData.ORE_REGISTRY.has(item_id):
		GameData.apply_ore(item_id)
	elif GameData.RESPEC_REGISTRY.has(item_id):
		GameData.apply_respec(item_id)
	refresh_slots()

func _assign_to_quickslot(inv_idx: int, qs_idx: int) -> void:
	var inv_item = GameData.inventory_slots[inv_idx].duplicate()
	if inv_item["item"] == "":
		return
	var qs_item = GameData.quickslot_slots[qs_idx].duplicate()
	GameData.quickslot_slots[qs_idx] = inv_item
	GameData.inventory_slots[inv_idx] = qs_item
	refresh_slots()

# Hover a quickslot, press a number — swaps that quickslot's item into the
# pressed number's position (and whatever was there back into the hovered
# one). Same "hover + number key" shape as _assign_to_quickslot() above,
# just quickslot-to-quickslot instead of inventory-to-quickslot.
func _swap_quickslots(from_idx: int, to_idx: int) -> void:
	if from_idx == to_idx:
		return
	var tmp = GameData.quickslot_slots[to_idx].duplicate()
	GameData.quickslot_slots[to_idx] = GameData.quickslot_slots[from_idx].duplicate()
	GameData.quickslot_slots[from_idx] = tmp
	refresh_slots()

func _process(delta):
	_update_debug_overlay()
	item_use_cooldown = max(0.0, item_use_cooldown - delta)
	if GameData.dev_no_cooldowns:
		item_use_cooldown = 0.0
	if _dialogue_active:
		_update_dialogue_position()
	if _prompt_active:
		_update_prompt_position()
	if char_screen_open:
		refresh_character_screen()
	if skill_tree_open and _skill_sp_label:
		_skill_sp_label.text = "SP: %d" % GameData.sp
		if GameData.sp != _skill_last_sp:
			_skill_last_sp = GameData.sp
			_refresh_skill_tree()
	if glint_tree_open and _glint_sp_label:
		_glint_sp_label.text = "SP: %d" % GameData.glint_sp
		if GameData.glint_sp != _glint_last_sp:
			_glint_last_sp = GameData.glint_sp
			_refresh_glint_skill_tree()
	if hp_bg.size.x > 0:
		var hp_ratio = clamp(float(GameData.hp) / float(GameData.max_hp), 0.0, 1.0)
		hp_fill.size = Vector2(hp_bg.size.x * hp_ratio, hp_bg.size.y)
	_update_boss_hp_bar()
	if _shield_bg.size.x > 0:
		var shield_ratio = clamp(GameData.passive_shield_hp / float(GameData.max_hp), 0.0, 1.0)
		_shield_fill.size = Vector2(_shield_bg.size.x * shield_ratio, _shield_bg.size.y)
	if _xp_bg.size.x > 0:
		var xp_ratio = clamp(float(GameData.xp) / float(GameData.xp_to_next()), 0.0, 1.0)
		_xp_fill.size = Vector2(_xp_bg.size.x * xp_ratio, _xp_bg.size.y)
	if GameData.active_herb != null and GameData.herb_max_timer > 0.0:
		_herb_icon.color = GameData.active_herb.color
		_herb_bar_fill.color = GameData.active_herb.color
		var ratio = clamp(GameData.herb_timer / GameData.herb_max_timer, 0.0, 1.0)
		var fill_h = _herb_bar_bg.size.y * ratio
		_herb_bar_fill.size = Vector2(_herb_bar_bg.size.x, fill_h)
		_herb_bar_fill.position.y = _herb_bar_bg.size.y - fill_h
	else:
		_herb_icon.color = Color(0.14, 0.14, 0.18)
		_herb_bar_fill.size = Vector2(_herb_bar_bg.size.x, 0)
	if GameData.glint_hp > 0.0 and GameData.glint_max_hp > 0.0:
		_ore_icon.color = GameData.weapon_color
		_ore_bar_fill.color = GameData.weapon_color
		var ore_ratio = clamp(GameData.glint_hp / GameData.glint_max_hp, 0.0, 1.0)
		var ore_fill_h = _ore_bar_bg.size.y * ore_ratio
		_ore_bar_fill.size = Vector2(_ore_bar_bg.size.x, ore_fill_h)
		_ore_bar_fill.position.y = _ore_bar_bg.size.y - ore_fill_h
	else:
		_ore_icon.color = Color(0.14, 0.14, 0.18)
		_ore_bar_fill.size = Vector2(_ore_bar_bg.size.x, 0)
	# Ability indicator boxes — locked / cooldown / glowing ready
	_update_cooldown_box(_last_stand_style, _last_stand_label, "LS",
		GameData.last_stand_heal_pct > 0.0, GameData.last_stand_cd,
		Color(0.2, 1.0, 0.35), Color(0.06, 0.18, 0.09))
	_update_cooldown_box(_hollowscale_style, _hollowscale_label, "HS",
		GameData.hollowscale_unlocked, GameData.hollowscale_cooldown,
		Color(0.75, 0.55, 0.25), Color(0.16, 0.12, 0.06))
	_update_cooldown_box(_danger_sense_style, _danger_sense_label, "DS",
		GameData.danger_sense_unlocked, GameData.danger_sense_cooldown,
		Color(0.85, 0.35, 0.85), Color(0.14, 0.06, 0.14))
	# Glint stack counters
	_update_stack_label("oc", "Overcharge", GameData.glint_overcharge_stacks, GameData.weapon_color)
	_update_stack_label("cb", "Combo", GameData.glint_combo_stacks, Color.WHITE)
	_update_stack_label("ex", "Executioner", GameData.glint_exec_stacks, Color(1.0, 0.35, 0.35))
	# HP numbers, level, unspent SP badge
	_hp_text.text = "%d / %d" % [GameData.hp, GameData.max_hp]
	_level_label.text = "Lv %d" % GameData.level
	var sp_lines: Array = []
	if GameData.sp > 0:
		sp_lines.append("+%d SP (K)" % GameData.sp)
	if GameData.glint_sp > 0:
		sp_lines.append("+%d SP (G)" % GameData.glint_sp)
	_sp_badge.visible = not sp_lines.is_empty()
	_sp_badge.text = "\n".join(sp_lines)
	# Quickslot cooldown dim
	var slots_dimmed = item_use_cooldown > 0.0 and GameData.item_use_cooldown_enabled
	for slot in quickslot_slot_nodes:
		slot.modulate = Color(0.5, 0.5, 0.5) if slots_dimmed else Color.WHITE
	# Herb / ore time + name labels
	if GameData.active_herb != null:
		_herb_time_label.text = "%ds" % int(ceil(GameData.herb_timer))
		_herb_name_label.text = GameData.active_herb.herb_name.replace(" Herb", "").to_upper()
	else:
		_herb_time_label.text = ""
		_herb_name_label.text = "—"
	if GameData.glint_hp > 0.0:
		_ore_time_label.text = "%d HP" % int(ceil(GameData.glint_hp))
		_ore_name_label.text = WEAPON_SHORT_NAMES.get(GameData.current_weapon, "?")
	else:
		_ore_time_label.text = ""
		_ore_name_label.text = "—"
	# Depth readout (16 px = 1 m, surface at y 0)
	var player = get_tree().get_first_node_in_group("player")
	if _depth_label and player:
		var depth = int(max(0.0, player.global_position.y) / 16.0)
		_depth_label.text = "-%d m" % depth if depth > 0 else "0 m"

func _update_stack_label(key: String, prefix: String, stacks: int, lit_color: Color) -> void:
	var lbl: Label = _stack_labels[key]
	lbl.text = "%s ×%d" % [prefix, stacks]
	lbl.add_theme_color_override("font_color", lit_color if stacks > 0 else Color(0.35, 0.35, 0.4))
