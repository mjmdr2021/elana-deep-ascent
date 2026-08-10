extends Area2D

const TELEGRAPH_TIME: float = 0.7
const ERUPT_TIME: float = 0.5
const COOLDOWN_TIME: float = 3.0
const FREEZE_DURATION: float = 2.0
const ERUPT_DAMAGE: int = 5

enum State { COOLDOWN, TELEGRAPH, ERUPTING }
var _state: State = State.COOLDOWN
var _timer: float = COOLDOWN_TIME
var _hit_this_eruption: bool = false

@onready var _visual: ColorRect = $ColorRect

func _process(delta):
	_timer -= delta
	match _state:
		State.COOLDOWN:
			_visual.modulate = Color.WHITE
			if _timer <= 0.0:
				_state = State.TELEGRAPH
				_timer = TELEGRAPH_TIME
		State.TELEGRAPH:
			_visual.modulate = Color(0.6, 0.9, 1.0)
			if _timer <= 0.0:
				_state = State.ERUPTING
				_timer = ERUPT_TIME
				_hit_this_eruption = false
		State.ERUPTING:
			_visual.modulate = Color(0.3, 0.8, 1.0)
			if not _hit_this_eruption:
				for body in get_overlapping_bodies():
					if body.is_in_group("player"):
						body.apply_freeze(FREEZE_DURATION)
						body.take_damage(ERUPT_DAMAGE, true, null, "frost")
						_hit_this_eruption = true
			if _timer <= 0.0:
				_state = State.COOLDOWN
				_timer = COOLDOWN_TIME
