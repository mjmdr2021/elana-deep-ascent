extends Area2D

# Wyrmbat's Tail Spike projectile -- reworked 2026-08-24 per user: "lets
# rename the bat spike to TailSpike, tailspike will be like the spike of
# hollow fang. long and with collision. and goes on until it hits terrain."
# Same shape as hollowfang_spike.gd: long real CollisionShape2D, travels in
# a straight line (aimed at Elana's position when thrown, not homing) until
# it physically collides with real terrain (collision_mask = 1,
# body_entered signal) -- no longer stops at a fixed target_position/
# distance check, and no longer uses spike.png (plain ColorRect visual
# instead, like hollowfang_spike.gd's own).
#
# Passes THROUGH Elana on hit (damages her once, keeps flying) -- unchanged
# from the original version. Once it hits terrain, sticks there
# INDEFINITELY (not Hollowfang's own auto-vanish-after-a-beat) -- 2026-08-24,
# user explicit: "leaves spike regardless... one spike per spike tail," and
# stays until Graniteus's Boulder Roll actually touches it (real collision,
# see _on_body_entered() below), which consumes it directly.
#
# Two explicit states (2026-08-24, user: "have the tailspike have two
# states, traveling and pinned on terrain") -- Boulder Roll's jump-over
# interaction only triggers against a PINNED spike, never one still
# mid-flight (TRAVELING), even if Graniteus happens to touch its flight path.
enum State { TRAVELING, PINNED }
var state: int = State.TRAVELING

const HIT_RADIUS: float = 14.0
@export var speed: float = 700.0
@export var damage: int = 15
@export var lifetime: float = 3.0  # safety cap if it never hits terrain

var aim_direction: Vector2 = Vector2.RIGHT
var _hit_player: bool = false
# Excludes Wyrmbat's own body from the widened collision_mask below (same
# "exclude the spawner" pattern hollowfang_spike.gd's own source field
# uses) -- set by wyrmbat.gd's _do_spike_tail() right after instantiating.
var source: Node = null

func _ready() -> void:
	add_to_group("enemy_projectiles")
	add_to_group("hazards")
	# Precise group for Graniteus's Boulder Roll <-> TailSpike interaction
	# (2026-08-24) to find these specifically, not everything in "hazards".
	add_to_group("wyrmbat_tailspike")
	collision_layer = 0
	# Terrain (1) + bosses (2) -- 2026-08-24, user: "if tailspike hits
	# graniteus, when not pinned, the tailspike disappears instead and not
	# make graniteus jump." Widened from terrain-only so _on_body_entered()
	# can tell the two apart (see there).
	collision_mask = 3
	# Brief grace period before terrain collision goes live -- Wyrmbat fires
	# this while she's still right up against the ceiling (her combat-fly
	# only ever moves horizontally, never drops her down), so without this
	# it detects the ceiling the instant it spawns and self-lands before
	# ever visibly traveling (2026-08-24, user report: "wyrm not throwing
	# spikes now"). Also covers the new bosses-layer mask -- without it, it'd
	# self-detect Wyrmbat's own body the instant it spawns at her position,
	# same class of bug.
	monitoring = false
	body_entered.connect(_on_body_entered)
	rotation = aim_direction.angle()
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		monitoring = true

func _physics_process(delta: float) -> void:
	if state == State.PINNED:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_land()
		return
	global_position += aim_direction * speed * delta
	if not _hit_player:
		var elana = get_tree().get_first_node_in_group("player")
		if elana and global_position.distance_to(elana.global_position) <= HIT_RADIUS:
			_hit_player = true
			if elana.has_method("take_damage"):
				elana.take_damage(damage, false, self)
			# No _land() here -- keeps flying through her, doesn't stop.

func _on_body_entered(body: Node) -> void:
	if body == source:
		return
	# 2026-08-24, real bug found: Elana's own player body sits on
	# collision_layer 2, the SAME layer both Wyrmbat and Graniteus share --
	# not a "bosses-only" layer like the mask below assumed. So this signal
	# was ALSO firing on real contact with her, and since she's not in the
	# "bosses" group it fell through to _land(), pinning the spike the
	# instant it physically touched her instead of passing through (user
	# report: "tail spikes doesnt go through elana"). The proximity-based
	# damage check above still worked independently, so it looked like she
	# was being hit correctly right up until the spike visibly stopped dead
	# on her. Now explicitly ignored -- she's handled entirely by that
	# separate proximity check, real collision with her should never land it.
	if body.is_in_group("player"):
		return
	if body.is_in_group("bosses"):
		if state == State.TRAVELING:
			# Hit while still mid-flight -- disappears outright rather than
			# pinning into terrain (2026-08-24, user explicit).
			queue_free()
			return
		# PINNED -- real touch from Graniteus while Boulder Rolling triggers
		# his jump-over directly (2026-08-24, user: "it should touch the
		# spike to trigger the jump" -- replaced an earlier distance-based
		# poll on his side that went through two failed tuning passes).
		# trigger_boulder_roll_spike_jump() only actually fires (and
		# returns true) while he's mid-roll; some other boss/state merely
		# brushing a pinned spike does nothing and leaves it alone.
		if body.has_method("trigger_boulder_roll_spike_jump") and body.trigger_boulder_roll_spike_jump():
			queue_free()
		return
	_land()

func _land() -> void:
	if state == State.PINNED:
		return
	state = State.PINNED
	set_physics_process(false)
