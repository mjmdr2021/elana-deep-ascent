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

var _molten_tick_timer: float = 0.0
var _electrified_tick_timer: float = 0.0
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
	if "on_web_tile" in elana:
		elana.on_web_tile = (hazard == "webFloor")

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
