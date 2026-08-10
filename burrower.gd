extends "res://enemy.gd"

# Starts fully hidden and burrowed on whatever tile it's placed on in the
# editor — invisible, unhittable, no chase/attack AI, nothing showing except
# a thin ColorRect mound at its feet (its own solid-body collision stays on
# throughout, purely so gravity settles it onto the floor like any other
# enemy — see _ready() for why that's safe). The instant Elana touches that
# mound it unburrows PERMANENTLY and becomes a completely normal enemy.gd
# chaser from then on (same chase/patrol/attack behavior as any other melee
# enemy) — it never burrows again.
@export var mound_size: Vector2 = Vector2(20, 4)
@export var mound_offset: Vector2 = Vector2(0, 8)
@export var direct_kill_range: float = 14.0
const NORMAL_AGGRO_SIZE: Vector2 = Vector2(100, 32)
const NORMAL_AGGRO_POS: Vector2 = Vector2(0, -8)
const MOUND_COLOR: Color = Color(0.5, 0.05, 0.08, 1)
const DETECTION_DELAY: float = 0.3

var _burrowed: bool = true
var _detecting: bool = false

func _ready() -> void:
	super._ready()
	# Suppress hittability/visibility/AI until touched — but its own
	# CollisionShape2D stays enabled the whole time. Elana's own collision
	# mask doesn't include the enemy layer at all (combat is purely
	# Hurtbox/Area2D-based, not physical-body collision), so a solid
	# Burrower can never block or bump her — it only settles onto the floor
	# via normal gravity from the moment the level loads, exactly like every
	# other enemy. Disabling it (the old approach) meant gravity never
	# resolved it against the ground while hidden, so it visibly dropped the
	# instant collision turned back on at unburrow.
	$Hurtbox.set_deferred("monitorable", false)
	$AnimatedSprite2D.visible = false
	$EyeGlow.visible = false
	if $AggroZone.body_entered.is_connected(_on_aggro_zone_body_entered):
		$AggroZone.body_entered.disconnect(_on_aggro_zone_body_entered)
	if $AggroZone.body_exited.is_connected(_on_aggro_zone_body_exited):
		$AggroZone.body_exited.disconnect(_on_aggro_zone_body_exited)
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)
	# Reshape AggroZone into the mound's own footprint as the touch trigger.
	# AttackZone is left completely alone so it's ready to work normally the
	# instant this becomes a real chasing/attacking enemy.
	var shape := RectangleShape2D.new()
	shape.size = mound_size
	$AggroZone/CollisionShape2D.shape = shape
	$AggroZone/CollisionShape2D.position = Vector2.ZERO
	$AggroZone.position = mound_offset
	$AggroZone.body_entered.connect(_on_mound_entered)
	$AggroZone.body_exited.connect(_on_mound_exited)
	$ColorRect.color = MOUND_COLOR
	$ColorRect.offset_left = mound_offset.x - mound_size.x / 2.0
	$ColorRect.offset_right = mound_offset.x + mound_size.x / 2.0
	$ColorRect.offset_top = mound_offset.y - mound_size.y / 2.0
	$ColorRect.offset_bottom = mound_offset.y + mound_size.y / 2.0
	$ColorRect.visible = true

func _move(delta: float) -> void:
	if _burrowed:
		velocity.x = 0
		return
	super._move(delta)

# base_enemy.gd's _update_zones() repositions AggroZone.x every physics
# frame off aggro_zone_offset (captured before we moved it), and enemy.gd's
# own override also repositions AttackZone — both would fight the mound
# placement above every single frame if left running while burrowed.
func _update_zones() -> void:
	if _burrowed:
		return
	super._update_zones()

# A motion-sensor style detection window, not a fire-and-forget delay:
# entering the mound starts a 0.3s countdown, but only unburrows if she's
# STILL overlapping it when the countdown finishes. Stepping off cancels it
# (_on_mound_exited below) — a quick pass-through won't trigger it.
func _on_mound_entered(body: Node) -> void:
	if not _burrowed or _detecting or not body.is_in_group("player"):
		return
	_detecting = true
	await get_tree().create_timer(DETECTION_DELAY).timeout
	if is_instance_valid(self) and _detecting and _burrowed:
		_unburrow(body)
	_detecting = false

func _on_mound_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_detecting = false

# Generic elana.gd hook — while burrowed, plunge attacks never deal normal
# HP damage (always returns true, skipping elana.gd's own _plunge_hit()).
# Three outcomes instead: landing precisely on the mound is an instant kill
# regardless of weapon; a warhammer plunge anywhere in its (much wider)
# AOE just unburrows it with no damage; every other weapon does nothing.
# Once unburrowed it's a normal chaser again — falls through to normal
# plunge damage from then on.
func on_plunge_hit(elana: Node, _hit_dir: int, _dmg: int) -> bool:
	if not _burrowed:
		return false
	var dist = elana.global_position.distance_to(global_position + mound_offset)
	if dist <= direct_kill_range:
		# Disarm the separate mound-touch detector immediately — landing a
		# direct hit means she's standing right on the mound too, so
		# _on_mound_entered() may already be mid-countdown (or fire this
		# same frame). Without this, its 0.3s timer can still resolve
		# during the 0.5s death delay below and call _unburrow() on an
		# already-dying Burrower.
		_burrowed = false
		_detecting = false
		hp = 0
		if is_instance_valid($HitHandler):
			$HitHandler._die()
		return true
	if GameData.current_weapon == "warhammer":
		_unburrow(elana)
		return true
	return true

func _unburrow(body: Node) -> void:
	_burrowed = false
	$ColorRect.visible = false
	$AnimatedSprite2D.visible = true
	$EyeGlow.visible = true
	$Hurtbox.set_deferred("monitorable", true)
	if $AggroZone.body_entered.is_connected(_on_mound_entered):
		$AggroZone.body_entered.disconnect(_on_mound_entered)
	if $AggroZone.body_exited.is_connected(_on_mound_exited):
		$AggroZone.body_exited.disconnect(_on_mound_exited)
	# Restore AggroZone to its normal enemy.tscn shape/position and
	# reconnect the generic chase/attack wiring — from here it's a plain
	# enemy.gd chaser, indistinguishable from any other melee enemy.
	var aggro_shape := RectangleShape2D.new()
	aggro_shape.size = NORMAL_AGGRO_SIZE
	$AggroZone/CollisionShape2D.shape = aggro_shape
	$AggroZone/CollisionShape2D.position = NORMAL_AGGRO_POS
	$AggroZone.body_entered.connect(_on_aggro_zone_body_entered)
	$AggroZone.body_exited.connect(_on_aggro_zone_body_exited)
	$AttackZone.body_entered.connect(_on_attack_zone_body_entered)
	$AttackZone.body_exited.connect(_on_attack_zone_body_exited)
	# Surprise hit on the reveal itself, on top of it becoming a normal
	# chaser from here on.
	body.take_damage(attack_damage, false, self)
	body.add_camera_trauma(0.4)
	target = body
	deaggro_timer = 0.0
