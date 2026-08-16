extends Control

const ItemSlotScript = preload("res://item_slot.gd")

const STOCK_ITEMS = [
	"herbElementalFire", "herbElementalFrost", "herbElementalElec",
	"herbAgility", "herbHeal", "herbPower",
	"ore1", "ore2", "ore3", "ore4",
	"respecElana", "respecGlint",
]

const TRADE_RATE: int = 3
const RESPEC_ORE_COST: int = 5
const RESPEC_HERB_COST: int = 5
const STOCK_LIMIT: int = 10

@onready var _player_grid: GridContainer = $PlayerGridBg/PlayerGrid
@onready var _stock_grid: GridContainer = $StockGridBg/StockGrid
@onready var _wanted_grid: GridContainer = $WantedBg/WantedSlot
@onready var _offer_grid: GridContainer = $OfferBg/OfferSlot
@onready var _cost_label: Label = $CostLabel
@onready var _trade_button: Button = $TradeButton
@onready var _close_button: Button = $CloseButton

var _moleman: Node = null
var _wanted_items: Dictionary = {}   # item_id -> count
var _offered_items: Dictionary = {}  # item_id -> count, reserved from player inventory

func _ready() -> void:
	_trade_button.pressed.connect(_on_trade_pressed)
	_close_button.pressed.connect(func(): get_parent().queue_free())
	add_to_group("moleman_trade_ui")

func open(moleman: Node) -> void:
	_moleman = moleman
	_wanted_items.clear()
	_offered_items.clear()
	_refresh_all()

# Square inventory-style slot — dark panel, bordered, icon, count — matching
# item_slot.gd's look, since this needs to work for both real inventory data
# and Moleman's abstract catalog / the staging boxes.
func _make_slot_visual(item_id: String, count: int, on_click: Callable) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(48, 48)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.45, 0.45)
	panel.add_theme_stylebox_override("panel", style)

	var icon = ColorRect.new()
	icon.anchor_left = 0.15
	icon.anchor_right = 0.85
	icon.anchor_top = 0.15
	icon.anchor_bottom = 0.85
	icon.color = ItemSlotScript.ITEM_COLORS.get(item_id, Color(0.5, 0.5, 0.5))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	var label = Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 0.95
	label.anchor_top = 0.55
	label.anchor_bottom = 1.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.text = str(count) if count > 0 else ""
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	panel.tooltip_text = ItemSlotScript.ITEM_NAMES.get(item_id, item_id)
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			on_click.call()
	)
	return panel

func _refresh_all() -> void:
	_refresh_stock_grid()
	_refresh_player_grid()
	_refresh_staging_grid(_wanted_grid, _wanted_items)
	_refresh_staging_grid(_offer_grid, _offered_items)
	_update_cost_display()

func _refresh_stock_grid() -> void:
	for child in _stock_grid.get_children():
		child.queue_free()
	for item_id in STOCK_ITEMS:
		var remaining = _remaining_stock(item_id) - _wanted_items.get(item_id, 0)
		if remaining <= 0:
			continue
		var slot = _make_slot_visual(item_id, remaining, _on_stock_item_clicked.bind(item_id))
		_stock_grid.add_child(slot)

# Player's real inventory count minus whatever's currently staged in the offer box
func _available_count(item_id: String) -> int:
	return _count_of(item_id) - _offered_items.get(item_id, 0)

func _refresh_player_grid() -> void:
	for child in _player_grid.get_children():
		child.queue_free()
	var seen: Dictionary = {}
	for slot in GameData.inventory_slots:
		if slot["item"] == "":
			continue
		seen[slot["item"]] = seen.get(slot["item"], 0) + slot["count"]
	for item_id in seen.keys():
		var avail = _available_count(item_id)
		if avail <= 0:
			continue
		var slot = _make_slot_visual(item_id, avail, _on_player_item_clicked.bind(item_id))
		_player_grid.add_child(slot)

func _refresh_staging_grid(grid: GridContainer, items: Dictionary) -> void:
	for child in grid.get_children():
		child.queue_free()
	for item_id in items.keys():
		var slot = _make_slot_visual(item_id, items[item_id], _on_staged_item_clicked.bind(grid, items, item_id))
		grid.add_child(slot)

# "respec" is its own category — those two items don't belong to either
# registry, and cost differently (both ore AND herb, not one or the other).
func _category_of(item_id: String) -> String:
	if GameData.RESPEC_REGISTRY.has(item_id):
		return "respec"
	if GameData.HERB_REGISTRY.has(item_id):
		return "herb"
	if GameData.ORE_REGISTRY.has(item_id):
		return "ore"
	return ""

func _on_stock_item_clicked(item_id: String) -> void:
	var already_wanted = _wanted_items.get(item_id, 0)
	if already_wanted >= _remaining_stock(item_id):
		return
	_wanted_items[item_id] = already_wanted + 1
	_refresh_stock_grid()
	_refresh_staging_grid(_wanted_grid, _wanted_items)
	_update_cost_display()

func _on_player_item_clicked(item_id: String) -> void:
	if not _is_valid_offer_item(item_id):
		return
	if _available_count(item_id) <= 0:
		return
	var cat = _category_of(item_id)
	var needed = _needed_ore() if cat == "ore" else _needed_herb()
	var have = _offered_count_of_category(cat)
	if have >= needed:
		return
	_offered_items[item_id] = _offered_items.get(item_id, 0) + 1
	_refresh_player_grid()
	_refresh_staging_grid(_offer_grid, _offered_items)
	_update_cost_display()

# Only accept an item as payment if the Wanted box currently needs that category —
# stops staging herbs when nothing wanted actually costs herbs, and vice versa.
func _is_valid_offer_item(item_id: String) -> bool:
	var cat = _category_of(item_id)
	if cat == "herb":
		return _needed_herb() > 0
	if cat == "ore":
		return _needed_ore() > 0
	return false

# Moleman's stock is finite and doesn't replenish — Respec Potions cap at 1
# (already tracked via mark_removed), regular herbs/ores cap at STOCK_LIMIT.
func _remaining_stock(item_id: String) -> int:
	if GameData.RESPEC_REGISTRY.has(item_id):
		return 0 if _is_respec_sold(item_id) else 1
	var scene_path = _moleman.get_tree().current_scene.scene_file_path
	var purchased = GameData.get_purchased_count(scene_path, _shop_key(item_id))
	return STOCK_LIMIT - purchased

# Ores cost herbs, herbs cost ores, respec potions cost both — summed across
# everything currently in the Wanted box, however mixed it is.
func _needed_ore() -> int:
	var total = 0
	for item_id in _wanted_items.keys():
		match _category_of(item_id):
			"herb": total += _wanted_items[item_id] * TRADE_RATE
			"respec": total += _wanted_items[item_id] * RESPEC_ORE_COST
	return total

func _needed_herb() -> int:
	var total = 0
	for item_id in _wanted_items.keys():
		match _category_of(item_id):
			"ore": total += _wanted_items[item_id] * TRADE_RATE
			"respec": total += _wanted_items[item_id] * RESPEC_HERB_COST
	return total

func _on_staged_item_clicked(grid: GridContainer, items: Dictionary, item_id: String) -> void:
	items[item_id] -= 1
	if items[item_id] <= 0:
		items.erase(item_id)
	_refresh_stock_grid()
	_refresh_staging_grid(grid, items)
	_refresh_player_grid()
	_update_cost_display()

func _count_of(item_id: String) -> int:
	var total = 0
	for slot in GameData.inventory_slots:
		if slot["item"] == item_id:
			total += slot["count"]
	return total

func _total_wanted() -> int:
	var total = 0
	for c in _wanted_items.values():
		total += c
	return total

func _offered_count_of_category(category: String) -> int:
	var total = 0
	for item_id in _offered_items.keys():
		if _category_of(item_id) == category:
			total += _offered_items[item_id]
	return total

func _update_cost_display() -> void:
	if _total_wanted() == 0:
		_cost_label.text = "Click items to buy, then items to pay with."
		_trade_button.disabled = true
		return
	var ore_needed = _needed_ore()
	var herb_needed = _needed_herb()
	var ore_have = _offered_count_of_category("ore")
	var herb_have = _offered_count_of_category("herb")
	var parts: Array = []
	if ore_needed > 0:
		parts.append("Ore: %d/%d" % [ore_have, ore_needed])
	if herb_needed > 0:
		parts.append("Herb: %d/%d" % [herb_have, herb_needed])
	_cost_label.text = "    ".join(parts)
	# Exact match required — over-offering blocks the trade the same as under-offering
	_trade_button.disabled = ore_have != ore_needed or herb_have != herb_needed

func _on_trade_pressed() -> void:
	if _trade_button.disabled:
		return
	for item_id in _offered_items.keys():
		_deduct_item(item_id, _offered_items[item_id])
	var scene_path = _moleman.get_tree().current_scene.scene_file_path
	for item_id in _wanted_items.keys():
		for i in _wanted_items[item_id]:
			GameData.add_item(item_id)
		if GameData.RESPEC_REGISTRY.has(item_id):
			GameData.mark_removed(scene_path, _shop_key(item_id))
		else:
			GameData.add_purchased_count(scene_path, _shop_key(item_id), _wanted_items[item_id])
	_wanted_items.clear()
	_offered_items.clear()
	_refresh_all()
	HUD.refresh_slots()

func _deduct_item(item_id: String, amount: int) -> void:
	var remaining = amount
	for slot in GameData.inventory_slots:
		if remaining <= 0:
			break
		if slot["item"] == item_id:
			var take = min(slot["count"], remaining)
			slot["count"] -= take
			remaining -= take
			if slot["count"] <= 0:
				slot["item"] = ""
				slot["count"] = 0

# Unique key per Moleman-instance-per-item, for both the respec sold-out flag
# and the regular stock purchase counter.
func _shop_key(item_id: String) -> String:
	return _moleman.name + "::" + item_id

func _is_respec_sold(item_id: String) -> bool:
	if _moleman == null:
		return false
	return GameData.is_removed(_moleman.get_tree().current_scene.scene_file_path, _shop_key(item_id))
