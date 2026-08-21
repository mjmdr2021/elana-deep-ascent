extends Area2D

# Lingering poison puddle left behind wherever a Poison Spit projectile hits
# terrain. Anyone standing in it gets poisoned continuously — same
# reapply-every-frame-with-a-short-duration trick pollen_puffer.gd's cloud
# uses, so it decays out naturally ~1s after leaving instead of needing
# explicit removal code for the status itself. The puddle object as a whole
# still has its own lifetime and fades out.

@export var poison_damage: int = 3
const LIFETIME: float = 6.0
const FADE_TIME: float = 1.0

var _lifetime_remaining: float = LIFETIME

@onready var _color_rect: ColorRect = $ColorRect

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player

func _physics_process(delta: float) -> void:
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		queue_free()
		return
	if _lifetime_remaining < FADE_TIME:
		_color_rect.modulate.a = _lifetime_remaining / FADE_TIME
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("apply_player_poison"):
			body.apply_player_poison(poison_damage, 2)
