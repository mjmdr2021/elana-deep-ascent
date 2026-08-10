extends "res://flying_enemy.gd"

# Swims freely (extends flying_enemy.gd for gravity-free 2D movement,
# matching "eel" better than a gravity-bound ground walker) — but only
# while it's actually on a water tile. Out of water, real gravity kicks in
# (overrides flying_enemy.gd's own no-op _apply_gravity) so it falls like
# any grounded thing, naturally dropping back into water below it instead
# of hovering stranded over dry land. Only chases while Elana herself is in
# water — the instant she's not, it goes passive (falls through to
# flying_enemy.gd's normal patrol/hover instead of chasing) rather than
# following her onto dry land. Also still ticks damage every
# out_of_water_tick_interval while it itself isn't on a water tile (same
# rule/helper as Spark Jelly, water_check.gd), covering the case where
# it's stranded/falling rather than actively chasing.
@export var out_of_water_tick_damage: int = 4
@export var out_of_water_tick_interval: float = 1.0

var _out_of_water_timer: float = 0.0

func _apply_gravity(delta: float) -> void:
	if WaterCheck.is_water(global_position, get_tree()):
		super._apply_gravity(delta)
	elif not is_on_floor():
		velocity.y += gravity * delta

func _move(delta: float) -> void:
	# Hides target for just this call instead of actually clearing it — the
	# real aggro state (AggroZone's target) needs to survive Elana dipping
	# in and out of water while still in range, since body_entered only
	# refires on a fresh zone entry, not every time she resurfaces.
	if target and not WaterCheck.is_water(target.global_position, get_tree()):
		var real_target = target
		target = null
		super._move(delta)
		target = real_target
		return
	super._move(delta)

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	if WaterCheck.is_water(global_position, get_tree()):
		_out_of_water_timer = 0.0
		return
	_out_of_water_timer -= delta
	if _out_of_water_timer <= 0.0:
		_out_of_water_timer = out_of_water_tick_interval
		hp -= out_of_water_tick_damage
		GameData.spawn_damage_number(out_of_water_tick_damage, global_position)
		if hp <= 0 and is_instance_valid($HitHandler):
			$HitHandler._die()
