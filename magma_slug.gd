extends "res://enemy.gd"

# Slow ground crawler — normal enemy.gd chase/patrol, just at low speed —
# that drops a fire_trail_patch.tscn behind itself periodically while
# actually moving. Fire-immune, frost-weak (set on the .tscn via the
# existing fire_resist/frost_resist system).
const FIRE_TRAIL_SCENE = preload("res://fire_trail_patch.tscn")
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
	var patch = FIRE_TRAIL_SCENE.instantiate()
	patch.position = position
	get_parent().call_deferred("add_child", patch)
