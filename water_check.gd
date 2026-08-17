class_name WaterCheck
extends RefCounted

# Shared helper — checks whether a world position sits on a tile tagged
# "water" in the "surface" custom-data layer (added to cave_tileset.tres
# alongside the existing "hazard" layer — a separate layer since "water"
# isn't inherently hazardous to Elana the way "molten"/"slippery" are, it's
# an environmental tag enemies query, not a player hazard). You'll need to
# tag the actual water tiles yourself in the TileSet editor panel (Godot's
# per-tile custom data inspector) — this only adds the layer/reads it, it
# doesn't know which tiles are visually water.

# Must match terrain_hazards.gd's own constant — Frost Beam is allowed to
# freeze a water tile over (elemander.gd's _mark_slippery_at_endpoint()
# skips its usual "don't touch water" rule specifically for this layer), so
# while that overlay is active on a given cell, it reads as icy/solid
# rather than open water until the overlay's own timer clears it.
const SLIPPERY_OVERLAY_LAYER: int = 2

static func is_water(world_pos: Vector2, tree: SceneTree) -> bool:
	var terrain = tree.current_scene.get_node_or_null("Terrain")
	if terrain == null or not (terrain is TileMap):
		return false
	var cell = terrain.local_to_map(terrain.to_local(world_pos))
	var data = terrain.get_cell_tile_data(0, cell)
	if data == null or data.get_custom_data("surface") != "water":
		return false
	return terrain.get_cell_source_id(SLIPPERY_OVERLAY_LAYER, cell) == -1
