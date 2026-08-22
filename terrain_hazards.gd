extends TileMap

const MOLTEN_TICK_DAMAGE: int = 8  # was 0 (disabled placeholder) — now live
const MOLTEN_TICK_INTERVAL: float = 0.5
const TILE_LAYER: int = 0
# Second layer, added in-editor (Inspector -> Layers -> Add Element),
# starts completely empty and invisible. Elemander's Fire Dash paints cells
# onto it temporarily (see elemander.gd's _spawn_fire_patch()) to make
# specific tiles molten without touching the shared tile data every other
# placement of that same floor tile uses — any tile present here at all
# counts as molten, regardless of what its own custom data says.
const MOLTEN_OVERLAY_LAYER: int = 1
# Third layer, same idea as the molten one — Elemander's Frost Beam paints a
# trail of cells onto this one as its endpoint moves (see elemander.gd's
# _mark_slippery_at_endpoint()). Any tile present here counts as slippery.
const SLIPPERY_OVERLAY_LAYER: int = 2
# Fourth layer — Elemander's Electric Storm electrifies every "surface"==
# "water" cell in the room at once (see elemander.gd's
# _electrify_all_water()) for the storm's duration. Only ever painted onto
# real water cells, but same "any tile present = active" rule as the others.
const ELECTRIFIED_OVERLAY_LAYER: int = 3
const ELECTRIFIED_TICK_DAMAGE: int = 1
const ELECTRIFIED_TICK_INTERVAL: float = 0.3
const FEET_OFFSET: float = 20.0  # Elana's origin isn't at her feet — sample below it
# 2026-08-22, user request: "return the respawn of tiles. respawn em after
# 30 seconds?" -- see _break_tile()/_pending_respawns. Re-added after being
# built once, then explicitly reverted, earlier this same session.
@export var breakable_tile_respawn_time: float = 30.0

var _molten_tick_timer: float = 0.0
var _electrified_tick_timer: float = 0.0
# Cells currently broken and waiting to respawn (2026-08-22, see
# _break_tile()) -- Vector2i cell used as a set (value unused, just presence)
# so a cell already mid-respawn can't get double-scheduled/double-cascaded.
var _pending_respawns: Dictionary = {}
# Cached once in _ready() — a TileMap's own layer count can't change at
# runtime, so re-deriving it from get_layers_count() at every call site
# (previously 5, 3 of them every single physics frame in _process()) was
# pure repeated cost for an answer that never changes for the life of the
# scene.
var _has_molten_overlay: bool = false
var _has_slippery_overlay: bool = false
var _has_electrified_overlay: bool = false

# Overrides whatever alpha you set in the editor — tinted so every cell an
# attack paints onto an overlay is visible exactly where it is, rather than
# a fully invisible functional-only layer. Since painted cells copy the
# same tile picture as the real floor underneath, this reads as "that exact
# tile is glowing," not a mismatched shape.
func _ready() -> void:
	# set_layer_modulate() hard-crashes (out-of-bounds C++ error, not a
	# catchable exception) on a layer index that doesn't exist yet — same
	# guard _process() already needs for get_cell_source_id(), so a TileMap
	# that hasn't had the overlay layers added yet (e.g. a fresh test scene)
	# fails safe instead of crashing on load. Cached here, once, instead of
	# re-checked at every call site (see the vars' own comment above).
	var layers: int = get_layers_count()
	_has_molten_overlay = layers > MOLTEN_OVERLAY_LAYER
	_has_slippery_overlay = layers > SLIPPERY_OVERLAY_LAYER
	_has_electrified_overlay = layers > ELECTRIFIED_OVERLAY_LAYER
	if _has_molten_overlay:
		set_layer_modulate(MOLTEN_OVERLAY_LAYER, Color(1.0, 0.4, 0.1, 0.6))
	if _has_slippery_overlay:
		set_layer_modulate(SLIPPERY_OVERLAY_LAYER, Color(0.4, 0.85, 1.0, 0.6))
	if _has_electrified_overlay:
		set_layer_modulate(ELECTRIFIED_OVERLAY_LAYER, Color(1.0, 1.0, 0.2, 0.7))
	# Ant Queen's death reward (elana.gd's take_damage()) only halves damage
	# from an attacker tagged "hazards" — molten damage below was passing
	# null as the attacker, so it could never match regardless of the tile
	# itself being a hazard. This TileMap now IS the attacker for that hit.
	add_to_group("hazards")

func _process(delta: float) -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana == null:
		return
	var local_pos = to_local(elana.global_position + Vector2(0, FEET_OFFSET))
	var cell = local_to_map(local_pos)
	var data = get_cell_tile_data(TILE_LAYER, cell)
	var hazard = data.get_custom_data("hazard") if data else ""
	# get_cell_source_id() hard-crashes (out-of-bounds C++ error, not a
	# catchable exception) on a layer index that doesn't exist yet — guarded
	# the same way the electrified layer below already was, so a TileMap
	# that hasn't had the overlay layers added yet (e.g. a fresh test scene)
	# fails safe instead of crashing every frame. Uses the cached bool from
	# _ready() instead of re-querying get_layers_count() every frame.
	var overlay_molten = _has_molten_overlay \
		and get_cell_source_id(MOLTEN_OVERLAY_LAYER, cell) != -1
	var overlay_slippery = _has_slippery_overlay \
		and get_cell_source_id(SLIPPERY_OVERLAY_LAYER, cell) != -1
	# Electrified is about being IN a body of water, not standing ON a
	# hazardous floor tile — water can be several tiles deep with solid
	# ground at the bottom, and the instant she's standing on that ground
	# the feet-offset point (tuned for "what floor tile is she on") pierces
	# straight through the water into the ground tile beneath it, even
	# though the rest of her is still visibly submerged. Sampled at her
	# actual origin instead — same point WaterCheck.is_water() uses for
	# _in_water — so this checks "is she in the water," not "what's under
	# her feet."
	var water_cell = local_to_map(to_local(elana.global_position))
	# get_cell_source_id() hard-crashes (out-of-bounds C++ error, not a
	# catchable exception) on a layer index that doesn't exist yet — guard
	# against the 4th layer not being added yet instead of taking the whole
	# game down over one missing editor step. Uses the cached bool from
	# _ready() instead of re-querying get_layers_count() every frame.
	var overlay_electrified = _has_electrified_overlay \
		and get_cell_source_id(ELECTRIFIED_OVERLAY_LAYER, water_cell) != -1

	if "on_slippery_tile" in elana:
		elana.on_slippery_tile = (hazard == "slippery") or overlay_slippery
	# Broodspawner's arena floor — same custom-data convention as the other
	# hazards, just read directly (no overlay layer needed, nothing paints
	# "webFloor" temporarily the way molten/slippery/electrified do).
	# (2026-08-21: "web" split into "webFloor"/"webWall" custom-data tags —
	# on_web_tile only cares about the floor variant.)
	# (2026-08-22 bug fix: comparing against the bare "webFloor" string never
	# matched anything once Broodspawner's own per-layer rework tagged real
	# tiles "webFloor1".."webFloor4"/"webBridge1".."webBridge4" instead --
	# on_web_tile had been permanently stuck false since that rework, the
	# whole web-wrap mechanic dead in the water. begins_with() matches any
	# layer's tag, same convention broodspawner.gd's own WEBFLOOR_HAZARD_NAMES/
	# WEBBRIDGE_HAZARD_NAMES arrays already use.)
	if "on_web_tile" in elana:
		elana.on_web_tile = hazard.begins_with("webFloor") or hazard.begins_with("webBridge")
	# webBridge specifically (2026-08-22, user request: "when walking on
	# webBridge, elana sinks and triggers the web wrap even when moving") --
	# drives a different rule in elana.gd's _tick_web_wrap() than plain
	# webFloor, so it needs its own flag rather than folding into on_web_tile.
	if "on_web_bridge_tile" in elana:
		elana.on_web_bridge_tile = hazard.begins_with("webBridge")

	# Standing in water while over a molten tile (e.g. water pooled above
	# lava, or the sampled feet-position straddling both) douses it — same
	# "wet = fireproof" rule apply_player_burn() in elana.gd already
	# respects for the burn status, applied here too since this is a direct
	# damage tick, not that status effect.
	var in_water: bool = "_in_water" in elana and elana._in_water
	if (hazard == "molten" or overlay_molten) and not in_water:
		_molten_tick_timer -= delta
		if _molten_tick_timer <= 0.0:
			_molten_tick_timer = MOLTEN_TICK_INTERVAL
			# GameData.calc_damage() floors all damage to at least 1 (by
			# design, for real combat) — passing 0 straight through would
			# still deal 1 per tick. Skip the call entirely instead.
			if MOLTEN_TICK_DAMAGE > 0:
				elana.take_damage(MOLTEN_TICK_DAMAGE, true, self, "fire")
	else:
		_molten_tick_timer = 0.0

	# Electrified water — 1 pure (non-elemental, no resist) damage every
	# 0.3s while touching, plus a continuous SHOCK (not a hard stun/freeze —
	# apply_shock() blocks input the same way but deliberately leaves
	# velocity untouched, so momentum carries through instead of snapping
	# to a dead stop) reapplied every frame of contact (its own
	# max(timer, duration) merge keeps it alive the whole time she's in
	# there, same refresh trick apply_slow() already relies on elsewhere)
	# that only actually starts counting down 0.5s after she leaves.
	if overlay_electrified:
		if "apply_shock" in elana:
			elana.apply_shock(GameData.SHOCK_STUN_DURATION)
		_electrified_tick_timer -= delta
		if _electrified_tick_timer <= 0.0:
			_electrified_tick_timer = ELECTRIFIED_TICK_INTERVAL
			elana.take_damage(ELECTRIFIED_TICK_DAMAGE, false, self)
	else:
		_electrified_tick_timer = 0.0
	_tick_breakable_terrain(elana)

# Breakable terrain prototype (2026-08-22, user request: "can we make
# terrain breakable... how will we do it? can we try making one in light
# test scene?") -- Approach A, whole-tile destruction. Tiles carry a new
# "breakable" bool custom-data flag (see cave_tileset.tres) — anything
# without it (the default) is unbreakable, no code change needed to make
# most terrain immune, only tiles explicitly opted in can ever be erased.
# Any weapon hit breaks a tagged tile in one hit (user's own choice for this
# first prototype pass — no HP/hit-count/cracked-visual-stage yet).
# Elana's melee Hitbox is an Area2D that detects other Area2Ds via
# area_entered ($Hitbox.area_entered -> _on_hitbox_area_entered(), matching
# every enemy Hurtbox) -- a TileMap's own collision is a physics BODY, not
# an Area2D, so that signal path can never fire for terrain at all. Instead
# this samples the Hitbox's own collision rect directly, every frame it's
# actively monitoring (i.e. mid-swing, any weapon), and breaks (see
# _break_tile()) any breakable tile that rect overlaps -- reusing the same
# get_cell_tile_data()/get_custom_data() reading this whole script already
# does for hazards. Duck-typed access into elana's own Hitbox child
# (get_node_or_null(), same defensive pattern every "X in elana"/"elana.Y"
# check elsewhere in this file already uses) so this never crashes if
# Elana's scene doesn't have a node by that name.
func _tick_breakable_terrain(elana: Node) -> void:
	var hitbox: Area2D = elana.get_node_or_null("Hitbox")
	if hitbox == null or not hitbox.monitoring:
		return
	var shape_node: CollisionShape2D = hitbox.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return
	var rect_shape: RectangleShape2D = shape_node.shape
	var half_size: Vector2 = rect_shape.size / 2.0
	var world_center: Vector2 = shape_node.global_position
	var corner_a: Vector2i = local_to_map(to_local(world_center - half_size))
	var corner_b: Vector2i = local_to_map(to_local(world_center + half_size))
	for x in range(min(corner_a.x, corner_b.x), max(corner_a.x, corner_b.x) + 1):
		for y in range(min(corner_a.y, corner_b.y), max(corner_a.y, corner_b.y) + 1):
			var cell := Vector2i(x, y)
			var tile_data: TileData = get_cell_tile_data(TILE_LAYER, cell)
			if tile_data and tile_data.get_custom_data("breakable"):
				_break_tile(cell)

# webBridge linked destruction (2026-08-22, user request: "if one web
# bridge is broken, all will be broken with same hazard name") -- read the
# tile's "hazard" custom data; if it's a webBridgeN tile (Broodspawner's own
# per-layer tag convention, see broodspawner.gd's WEBBRIDGE_HAZARD_NAMES),
# find every OTHER cell on the map sharing that EXACT same hazard string
# ("same hazard name" means webBridge2 only chains to other webBridge2
# cells, never webBridge1/3/4) and break them all together via
# _break_single_tile(). Non-webBridge breakable tiles just break themselves,
# no scan needed.
# PERFORMANCE (2026-08-22 fix, found from real in-game lag on full_map.tscn
# once the cascade started firing): the very first version of this had each
# cascaded tile call itself recursively, so EVERY one of the N matching
# cells re-scanned the WHOLE map's get_used_cells() again -- O(cells ×
# matches) tile-data lookups in one frame, easily tens of thousands on a
# real level, not just a small test arena. Scanning get_used_cells() exactly
# ONCE per break event here, then calling the non-scanning
# _break_single_tile() for every match found, drops that back to a single
# O(cells) pass no matter how many webBridge segments share the tag.
func _break_tile(cell: Vector2i) -> void:
	var tile_data: TileData = get_cell_tile_data(TILE_LAYER, cell)
	var hazard: String = tile_data.get_custom_data("hazard") if tile_data else ""
	if hazard.begins_with("webBridge"):
		for matching_cell in get_used_cells(TILE_LAYER):
			var matching_data: TileData = get_cell_tile_data(TILE_LAYER, matching_cell)
			if matching_data and matching_data.get_custom_data("hazard") == hazard:
				_break_single_tile(matching_cell)
	else:
		_break_single_tile(cell)

# Erases one cell, then restores the exact same tile (source/atlas coords/
# alternate) after breakable_tile_respawn_time (2026-08-22, user request:
# "return the respawn of tiles. respawn em after 30 seconds?"). Called
# without awaiting it (same pattern broodspawner.gd relies on throughout) --
# _pending_respawns[cell] is set synchronously before the only await, so a
# cell already mid-respawn (including one already caught by a webBridge
# cascade) can't get double-scheduled, and a fresh get_cell_tile_data() on
# an erased cell already returns null anyway, so _tick_breakable_terrain()
# naturally stops calling _break_tile() again for it until it's actually
# back. Never does any scanning of its own -- _break_tile() above is the
# only thing that decides WHICH cells break, this just breaks one.
func _break_single_tile(cell: Vector2i) -> void:
	if cell in _pending_respawns:
		return
	var source_id: int = get_cell_source_id(TILE_LAYER, cell)
	var atlas_coords: Vector2i = get_cell_atlas_coords(TILE_LAYER, cell)
	var alternate: int = get_cell_alternative_tile(TILE_LAYER, cell)
	_pending_respawns[cell] = true
	erase_cell(TILE_LAYER, cell)
	await get_tree().create_timer(breakable_tile_respawn_time).timeout
	if is_instance_valid(self):
		set_cell(TILE_LAYER, cell, source_id, atlas_coords, alternate)
		_pending_respawns.erase(cell)
