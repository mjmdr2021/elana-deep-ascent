extends TileMap

const MOLTEN_TICK_DAMAGE: int = 0
const MOLTEN_TICK_INTERVAL: float = 0.5
const TILE_LAYER: int = 0
const FEET_OFFSET: float = 20.0  # Elana's origin isn't at her feet — sample below it

var _molten_tick_timer: float = 0.0

func _process(delta: float) -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana == null:
		return
	var local_pos = to_local(elana.global_position + Vector2(0, FEET_OFFSET))
	var cell = local_to_map(local_pos)
	var data = get_cell_tile_data(TILE_LAYER, cell)
	var hazard = data.get_custom_data("hazard") if data else ""

	if "on_slippery_tile" in elana:
		elana.on_slippery_tile = (hazard == "slippery")

	if hazard == "molten":
		_molten_tick_timer -= delta
		if _molten_tick_timer <= 0.0:
			_molten_tick_timer = MOLTEN_TICK_INTERVAL
			# GameData.calc_damage() floors all damage to at least 1 (by
			# design, for real combat) — passing 0 straight through would
			# still deal 1 per tick. Skip the call entirely instead.
			if MOLTEN_TICK_DAMAGE > 0:
				elana.take_damage(MOLTEN_TICK_DAMAGE, true, null, "fire")
	else:
		_molten_tick_timer = 0.0
