extends "res://enemy.gd"

# Rooted landmine-with-reach — never moves, ever. AggroZone is disconnected
# entirely so `target` can never get set (enemy.gd's _move() would otherwise
# chase once target is set, even for enemy_type STATIONARY, since that
# check comes first). The only thing it reacts to is AttackZone, left as
# base_enemy.gd's completely normal windup -> strike -> cooldown cycle —
# just resized bigger (whip reach) and re-centered on itself every frame
# (not offset to one side) so it can strike from any direction, repeating
# indefinitely for as long as something stays in reach. Tint swaps from a
# dim, easy-to-miss dormant green to a bright red the instant it's actually
# mid-windup or mid-strike, reusing those existing timers directly.
const REACH_SIZE: Vector2 = Vector2(40, 20)
const DORMANT_TINT: Color = Color(0.4, 0.6, 0.35, 1.0)
const STRIKE_TINT: Color = Color(1.6, 0.3, 0.3, 1.0)
const VISUAL_SIZE: float = 14.0

func _ready() -> void:
	# ColorRect's color must be set BEFORE super._ready() — base_enemy.gd
	# captures it as original_color for the hit-flash system at that point.
	$AnimatedSprite2D.visible = false
	$ColorRect.color = Color.WHITE
	$ColorRect.offset_left = -VISUAL_SIZE / 2.0
	$ColorRect.offset_top = -VISUAL_SIZE / 2.0
	$ColorRect.offset_right = VISUAL_SIZE / 2.0
	$ColorRect.offset_bottom = VISUAL_SIZE / 2.0
	$ColorRect.visible = true
	super._ready()
	modulate = DORMANT_TINT
	if $AggroZone.body_entered.is_connected(_on_aggro_zone_body_entered):
		$AggroZone.body_entered.disconnect(_on_aggro_zone_body_entered)
	if $AggroZone.body_exited.is_connected(_on_aggro_zone_body_exited):
		$AggroZone.body_exited.disconnect(_on_aggro_zone_body_exited)
	var shape := RectangleShape2D.new()
	shape.size = REACH_SIZE
	$AttackZone/CollisionShape2D.shape = shape
	$AttackZone/CollisionShape2D.position = Vector2.ZERO
	$AttackZone.position = Vector2.ZERO

# enemy.gd's own _update_zones() override re-offsets AttackZone to one side
# every frame (12.0 * direction) — put it back to centered every frame
# instead, since a rooted vine should be able to whip either direction.
func _update_zones() -> void:
	super._update_zones()
	$AttackZone.position = Vector2.ZERO

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	var striking = attack_windup_timer > 0.0 or attack_anim_timer > 0.0
	modulate = STRIKE_TINT if striking else DORMANT_TINT
