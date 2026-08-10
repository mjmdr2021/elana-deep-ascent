extends Area2D

const SLOW_FACTOR: float = 0.5
const REFRESH_DURATION: float = 0.3

func _process(_delta):
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("apply_slow"):
			body.apply_slow(SLOW_FACTOR, REFRESH_DURATION)
