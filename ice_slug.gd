extends "res://enemy.gd"

# Frost counterpart to magma_slug.gd — same slow-crawler shape, drops
# ice_trail_patch.tscn (slow, not burn) behind itself while moving.
# Frost-immune, fire-weak on the .tscn.
const ICE_TRAIL_SCENE = preload("res://ice_trail_patch.tscn")
@export var trail_interval: float = 0.5

var _trail_timer: float = 0.0

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	if abs(velocity.x) < 5.0:
		return
	_trail_timer -= delta
	if _trail_timer <= 0.0:
		_trail_timer = trail_interval
		_spawn_trail()

func _spawn_trail() -> void:
	var patch = ICE_TRAIL_SCENE.instantiate()
	patch.position = position
	get_parent().call_deferred("add_child", patch)
