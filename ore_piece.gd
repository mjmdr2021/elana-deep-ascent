extends RigidBody2D

var ore_type: String = "ore1"
var target = null
var homing = false

# Safety cleanup -- 2026-08-24, defense against a piece that ends up
# somewhere Elana can never actually reach (wedged in geometry, ejected out
# of the playable area) sitting forever and quietly accumulating physics
# overhead across repeated boss attacks over a play session (user report:
# "then after some time, it lags again"). Auto-despawns if it's just never
# been collected, regardless of why.
const MAX_LIFETIME: float = 20.0
var _lifetime: float = 0.0

func _ready():
	add_to_group("ore_pieces")
	$PickupArea.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player"):
		target = body
		await get_tree().create_timer(0.15).timeout
		homing = true

func _physics_process(delta):
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		queue_free()
		return
	if homing and target:
		var dir = (target.global_position - global_position).normalized()
		linear_velocity = dir * 200
		if global_position.distance_to(target.global_position) < 10:
			target.pick_up(ore_type)
			queue_free()

# Real physics hop -- 2026-08-24, user: "make ore pieces also jump on the
# knock ups on the ground caused by graniteus." A genuine upward
# linear_velocity impulse (this is a RigidBody2D, unlike ore_node.gd's
# static bounce()), matching the same scatter-velocity range drop_ores()/
# _spill_ore() already use for their initial pop. Skipped once homing --
# don't want to disrupt a piece already flying to Elana for pickup.
#
# Cooldown added 2026-08-24 (user report: "when ores bounce, they
# sometimes vanish") -- Mountain Judgement's own bounce radius (60px) is
# wider than its mound spacing (26px), so as the wave sweeps past, a
# single ore piece can stay in range of several consecutive mounds and get
# this called on it many times within a fraction of a second -- resetting
# its velocity mid-arc over and over instead of one clean hop, which is
# exactly the kind of repeated-impulse spam that can eject a RigidBody2D
# through geometry or wedge it somewhere.
const BOUNCE_COOLDOWN_MS: int = 400
var _last_bounce_time_ms: int = -1000000

func bounce() -> void:
	if homing:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_bounce_time_ms < BOUNCE_COOLDOWN_MS:
		return
	_last_bounce_time_ms = now
	linear_velocity.y = randf_range(-300, -200)
