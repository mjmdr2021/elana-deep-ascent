extends "res://flying_enemy.gd"

# Flying, no attack of its own (AttackZone disconnected) — unlike Healer
# Wisp it does NOT flee; flying_enemy.gd's own unmodified chase _move()
# already flies it toward Elana once aggro'd, which is exactly what it
# wants (staying close keeps its aura on her). Brittle — deliberately low
# HP on the .tscn, so it's a real "kill it fast to shut the aura off"
# priority target, not a tanky flier.
@export var aura_radius: float = 70.0
@export var aura_slow_factor: float = 0.6

func _ready() -> void:
	super._ready()
	if $AttackZone.body_entered.is_connected(_on_attack_zone_body_entered):
		$AttackZone.body_entered.disconnect(_on_attack_zone_body_entered)
	if $AttackZone.body_exited.is_connected(_on_attack_zone_body_exited):
		$AttackZone.body_exited.disconnect(_on_attack_zone_body_exited)

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	var elana = get_tree().get_first_node_in_group("player")
	if elana and global_position.distance_to(elana.global_position) <= aura_radius:
		elana.apply_slow(aura_slow_factor, 0.3, "frost")
