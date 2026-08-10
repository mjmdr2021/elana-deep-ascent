extends RigidBody2D

var ore_type: String = "ore1"
var target = null
var homing = false

func _ready():
	$PickupArea.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player"):
		target = body
		await get_tree().create_timer(0.15).timeout
		homing = true

func _physics_process(delta):
	if homing and target:
		var dir = (target.global_position - global_position).normalized()
		linear_velocity = dir * 200
		if global_position.distance_to(target.global_position) < 10:
			target.pick_up(ore_type)
			queue_free()
