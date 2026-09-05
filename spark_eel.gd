extends "res://flying_enemy.gd"

# Swims freely (extends flying_enemy.gd for gravity-free 2D movement,
# matching "eel" better than a gravity-bound ground walker) — but only
# while it's actually on a water tile. Out of water, real gravity kicks in
# (overrides flying_enemy.gd's own no-op _apply_gravity) so it falls like
# any grounded thing, naturally dropping back into water below it instead
# of hovering stranded over dry land. Only chases while Elana herself is in
# water — the instant she's not, it goes passive (falls through to
# flying_enemy.gd's normal patrol/hover instead of chasing) rather than
# following her onto dry land. Also still ticks damage every
# out_of_water_tick_interval while it itself isn't on a water tile (same
# rule/helper as Spark Jelly, water_check.gd), covering the case where
# it's stranded/falling rather than actively chasing.
@export var out_of_water_tick_damage: int = 4
@export var out_of_water_tick_interval: float = 1.0
# 2026-09-06, user explicit: "make the eel be like the normal enemy, that
# they stop when the attack zone is in range" -- flying_enemy.gd's own
# chase branch (used unmodified by Ice Wisp, which deliberately WANTS to
# keep closing in with no attack of its own) homes velocity straight at
# Elana's exact center every single frame with no stop condition, unlike
# enemy.gd's ground-chase _move() (its own stop_distance) which halts once
# close enough for AttackZone -- offset to one side of the body -- to
# actually line up. The eel is the only flying_enemy.gd-based enemy that
# still uses that generic AttackZone contact-attack cycle (Spark Jelly/
# Flies both disconnect it for their own attack mechanics), so it's the
# one that actually needs this, same default value enemy.gd uses.
@export var stop_distance: float = 23.0

var _out_of_water_timer: float = 0.0

# 2026-09-05, real sprite art added -- base_enemy.gd's own _update_sprite()
# assumes the art faces left by default and mirrors it (flip_h = true) when
# facing right (direction > 0, see its own comment above that line). The
# sparkEel1-4.png art is drawn facing RIGHT by default (user confirmed),
# the opposite convention -- left uninverted, it'd show the eel backwards
# whenever direction is at its default/positive (facing-right) state.
# Inverted here instead of touching the shared base (every other enemy's
# art already matches that convention correctly).
func _update_sprite() -> void:
	super._update_sprite()
	if _sprite:
		_sprite.flip_h = direction < 0

func _apply_gravity(delta: float) -> void:
	if WaterCheck.is_water(global_position, get_tree()):
		super._apply_gravity(delta)
	elif not is_on_floor():
		velocity.y += gravity * delta

func _move(delta: float) -> void:
	# 2026-09-05, real bug found (user: "why did the eel swim upwards... i
	# think it chased me") -- the target-water check below only looks at
	# WHERE ELANA IS, never where the eel itself is. flying_enemy.gd's own
	# chase branch does a direct `velocity = (target.global_position -
	# global_position).normalized() * chase_speed`, a full overwrite of
	# velocity.y -- so as long as she stayed in water, the eel kept homing
	# straight at her even after its OWN chase arc carried it up out of the
	# water and into open air, discarding whatever _apply_gravity() had just
	# added that same frame. Out of water, always just fall instead --
	# gravity already ran this frame above, nothing here should touch
	# velocity until it's back on a water tile.
	if not WaterCheck.is_water(global_position, get_tree()):
		return
	# Hides target for just this call instead of actually clearing it — the
	# real aggro state (AggroZone's target) needs to survive Elana dipping
	# in and out of water while still in range, since body_entered only
	# refires on a fresh zone entry, not every time she resurfaces.
	if target and not WaterCheck.is_water(target.global_position, get_tree()):
		var real_target = target
		target = null
		super._move(delta)
		target = real_target
		return
	if target:
		_move_chase(delta)
		return
	super._move(delta)

# Same stop_distance shape as enemy.gd's own ground-chase _move() — x-only,
# matching AttackZone's own offset (flying_enemy.gd's _update_zones() only
# ever repositions it along .position.x, never y) so stopping here is what
# actually lets that zone reach her instead of flying straight through.
func _move_chase(_delta: float) -> void:
	var dist = abs(target.global_position.x - global_position.x)
	direction = 1 if target.global_position.x >= global_position.x else -1
	if dist > stop_distance:
		velocity = (target.global_position - global_position).normalized() * chase_speed
	else:
		velocity = Vector2.ZERO

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	# 2026-09-06, real bug found (user: "why does eel die so quick when
	# touching a bit air") -- this used to reset to 0.0 while in water, but
	# 0.0 is also the "timer's up, deal damage" trigger value the countdown
	# below checks (<= 0.0) -- so the very first frame back out of water,
	# `_out_of_water_timer -= delta` went straight negative and fired an
	# INSTANT damage tick, skipping the full out_of_water_tick_interval
	# grace period entirely. Bobbing at the surface (briefly clipping air
	# over and over) meant an instant hit on every single re-exit. Re-arms
	# to the full interval instead, same as the reset-on-tick line below --
	# a countdown timer should re-arm to full, not to its own expiry value.
	if WaterCheck.is_water(global_position, get_tree()):
		_out_of_water_timer = out_of_water_tick_interval
		return
	_out_of_water_timer -= delta
	if _out_of_water_timer <= 0.0:
		_out_of_water_timer = out_of_water_tick_interval
		hp -= out_of_water_tick_damage
		GameData.spawn_damage_number(out_of_water_tick_damage, global_position)
		if hp <= 0 and is_instance_valid($HitHandler):
			$HitHandler._die()
