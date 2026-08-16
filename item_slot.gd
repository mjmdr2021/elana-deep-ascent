extends Panel

enum SlotType { INVENTORY, QUICKSLOT }

const ITEM_NAMES = {
	"herbElementalFire":  "Fire Herb",
	"herbElementalFrost": "Frost Herb",
	"herbElementalElec":  "Elec Herb",
	"herbAgility":        "Agility Herb",
	"herbHeal":           "Heal Herb",
	"herbPower":          "Power Herb",
	"ore":        "Ore",
	"ore1":       "Sword Ore",
	"ore2":       "Chain Ore",
	"ore3":       "Spear Ore",
	"ore4":       "Hammer Ore",
	"respecElana": "Elana's Respec Potion",
	"respecGlint": "Glint's Respec Potion",
	"note1": "Note #1",
}

const ITEM_COLORS = {
	"herb": Color(0.2, 0.7, 0.2),
	"herbElementalFire": Color(0.95, 0.35, 0.1),
	"herbElementalFrost": Color(0.4, 0.75, 0.95),
	"herbElementalElec": Color(0.95, 0.9, 0.15),
	"herbAgility": Color(0.2, 0.85, 0.85),
	"herbHeal": Color(0.15, 0.9, 0.4),
	"herbPower": Color(0.7, 0.2, 0.9),
	"ore": Color(0.55, 0.45, 0.25),
	"ore1": Color(0.85, 0.75, 0.3),
	"ore2": Color(0.8, 0.45, 0.15),
	"ore3": Color(0.35, 0.65, 0.9),
	"ore4": Color(0.7, 0.2, 0.2),
	"respecElana": Color(0.75, 0.3, 0.75),
	"respecGlint": Color(0.3, 0.75, 0.75),
	"note1": Color(0.85, 0.8, 0.65),
}

var slot_index: int = 0
var slot_type: SlotType = SlotType.INVENTORY

var _style: StyleBoxFlat
var _icon: ColorRect
var _count_label: Label

func _ready():
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.08, 0.08, 0.08)
	_style.set_border_width_all(2)
	_style.border_color = Color(0.45, 0.45, 0.45)
	add_theme_stylebox_override("panel", _style)

	_icon = ColorRect.new()
	_icon.anchor_left = 0.15
	_icon.anchor_right = 0.85
	_icon.anchor_top = 0.15
	_icon.anchor_bottom = 0.85
	_icon.color = Color.TRANSPARENT
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count_label = Label.new()
	_count_label.anchor_left = 0.0
	_count_label.anchor_right = 0.95
	_count_label.anchor_top = 0.55
	_count_label.anchor_bottom = 1.0
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 9)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_count_label)

	if slot_type == SlotType.INVENTORY:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
	else:
		gui_input.connect(_on_quickslot_gui_input)
		mouse_entered.connect(_on_quickslot_mouse_entered)
		mouse_exited.connect(_on_quickslot_mouse_exited)
		var key_hint = Label.new()
		key_hint.text = str((slot_index + 1) % 10)
		key_hint.position = Vector2(3, 1)
		key_hint.add_theme_font_size_override("font_size", 8)
		key_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(key_hint)

	refresh()

# Click = use. Fires on release, so drag-to-rearrange (press + move,
# release swallowed by the drag system) never consumes the item.
func _on_quickslot_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		HUD.use_quickslot(slot_index)

func _on_mouse_entered() -> void:
	HUD.hovered_inventory_slot = slot_index

func _on_mouse_exited() -> void:
	if HUD.hovered_inventory_slot == slot_index:
		HUD.hovered_inventory_slot = -1

# Same shape as the inventory hover pair above, but for quickslots — lets
# HUD's number-key handler swap the hovered quickslot into whichever number
# gets pressed, instead of only supporting inventory-to-quickslot assignment.
func _on_quickslot_mouse_entered() -> void:
	HUD.hovered_quickslot_slot = slot_index

func _on_quickslot_mouse_exited() -> void:
	if HUD.hovered_quickslot_slot == slot_index:
		HUD.hovered_quickslot_slot = -1

func set_selected(selected: bool) -> void:
	_style.border_color = Color(1, 1, 0) if selected else Color(0.45, 0.45, 0.45)

func refresh() -> void:
	var data = _get_slot_data()
	if data["item"] == "":
		_icon.color = Color.TRANSPARENT
		_count_label.text = ""
		tooltip_text = ""
	else:
		_icon.color = ITEM_COLORS.get(data["item"], Color(0.5, 0.5, 0.5))
		_count_label.text = str(data["count"])
		# Full description on hover — falls back to the short name (then the
		# raw item id) for anything not in HUD's ITEM_DESCRIPTIONS yet.
		tooltip_text = HUD.ITEM_DESCRIPTIONS.get(data["item"], ITEM_NAMES.get(data["item"], data["item"]))

func _get_slot_data() -> Dictionary:
	if slot_type == SlotType.INVENTORY:
		return GameData.inventory_slots[slot_index]
	return GameData.quickslot_slots[slot_index]

func _set_slot_data(data: Dictionary) -> void:
	if slot_type == SlotType.INVENTORY:
		GameData.inventory_slots[slot_index] = data
	else:
		GameData.quickslot_slots[slot_index] = data

func _get_drag_data(_at_position) -> Variant:
	var data = _get_slot_data()
	if data["item"] == "":
		return null
	var preview = ColorRect.new()
	preview.size = Vector2(36, 36)
	preview.color = ITEM_COLORS.get(data["item"], Color(0.5, 0.5, 0.5))
	set_drag_preview(preview)
	return {"item": data["item"], "count": data["count"], "from_slot": slot_index, "from_type": slot_type}

func _can_drop_data(_at_position, data) -> bool:
	return data is Dictionary and data.has("item")

func _drop_data(_at_position, data) -> void:
	if data["from_type"] == slot_type and data["from_slot"] == slot_index:
		return

	var target = _get_slot_data().duplicate()
	var source_slots = GameData.inventory_slots if data["from_type"] == SlotType.INVENTORY else GameData.quickslot_slots
	var source = source_slots[data["from_slot"]].duplicate()

	if target["item"] == "":
		_set_slot_data(source)
		source_slots[data["from_slot"]] = {"item": "", "count": 0}
	elif target["item"] == source["item"] and target["count"] < GameData.MAX_STACK:
		var space = GameData.MAX_STACK - target["count"]
		var to_move = min(source["count"], space)
		target["count"] += to_move
		_set_slot_data(target)
		var remaining = source["count"] - to_move
		if remaining == 0:
			source_slots[data["from_slot"]] = {"item": "", "count": 0}
		else:
			source_slots[data["from_slot"]]["count"] = remaining
	else:
		_set_slot_data(source)
		source_slots[data["from_slot"]] = target

	HUD.refresh_slots()
