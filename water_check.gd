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
static func is_water(world_pos: Vector2, tree: SceneTree) -> bool:
	var terrain = tree.current_scene.get_node_or_null("Terrain")
	if terrain == null or not (terrain is TileMap):
		return false
	var cell = terrain.local_to_map(terrain.to_local(world_pos))
	var data = terrain.get_cell_tile_data(0, cell)
	return data != null and data.get_custom_data("surface") == "water"
