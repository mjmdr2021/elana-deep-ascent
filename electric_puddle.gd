extends Area2D

const STUN_DURATION: float = 0.5
const SHOCK_DAMAGE: int = 3
const COOLDOWN: float = 2.0

var _cooldown_timer: float = 0.0
var _was_inside: bool = false

func _process(delta):
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	var inside = false
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			inside = true
			if not _was_inside and _cooldown_timer <= 0.0 and body.has_method("apply_stun"):
				body.apply_stun(STUN_DURATION)
				body.take_damage(SHOCK_DAMAGE, true, null, "elec")
				_cooldown_timer = COOLDOWN
			break
	_was_inside = inside
