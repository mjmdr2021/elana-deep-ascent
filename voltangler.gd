extends "res://enemy.gd"

# VOLTANGLER — mini-boss, 2026-08-22 (name/spec per user request: "create
# mini boss... name it something related to angler fish, lanturn. spark,
# electricity, blob fish... witty one" -- "Voltangler," volt+angler).
# Extends enemy.gd like elemental_golem.gd, NOT a raw CharacterBody2D like
# the 3 story bosses -- stationary, no gravity, no standard melee, so this
# reuses the shared hp/on_hit/HP-bar/activation-radius plumbing instead of
# fighting a base class built around walking/attacking.
#
# Floats in place in water (placement-only for this first build -- no
# dynamic water-tile detection, see the design doc discussion). Cycles
# automatically between two states on a fixed timer:
#   DEFLATED (default) -- higher armor, base HP, continually emits a
#     pulsing AoE shock around itself (see _tick_pulsing_shock()).
#   INFLATED -- lower armor, +50% max HP (added as bonus/shield-style HP,
#     trimmed back off on deflate), and any landed hit shocks Elana as a
#     punish (see on_hit()/on_elemental_hit() below) instead of a
#     passive-area hazard. Also periodically rolls a chance to "show its
#     lantern" -- a brief window where the separate Lantern sub-part (see
#     voltangler_lantern.gd) is actually hittable; destroying it during that
#     window permanently disables her regen for the rest of the fight, same
#     one-way "solve it and it stays solved" shape as Broodspawner's web
#     anchors forcing her DOWN.
#
# No AttackZone/WallCheck nodes in the scene at all -- base_enemy.gd's own
# standard melee windup/cooldown cycle (_tick_attack()/_perform_attack())
# only ever activates if an AttackZone child exists (checked in _ready());
# omitting it means that whole system silently never engages, so every hit
# Elana takes from this boss comes from the custom shock mechanics below,
# not a punch.

enum State { DEFLATED, INFLATING, INFLATED, DEFLATING }

@export_group("State Cycle")
@export var deflated_duration: float = 8.0
@export var inflated_duration: float = 8.0
@export var state_transition_duration: float = 1.0

@export_group("Armor & HP")
# Retuned 2026-08-22 (was 80/40, base hp was 1000) -- user's exact spec:
# "make elemental golem have 90 armor. have voltangler have 2000 base hp.
# make the inflated be 50% bonus hp. deflated be 200, inflated be 50."
@export var deflated_defense: int = 200
@export var inflated_defense: int = 50
# Bonus HP while inflated, as a fraction of the deflated baseline -- added
# to both max_hp and current hp on inflate (shield-style, same idea as
# Elana's own overheal->shield conversion), trimmed back off (current hp
# clamped down to the smaller max) on deflate. _base_max_hp captures the
# true baseline in _ready(), since max_hp itself gets mutated by this every
# cycle. Was 0.25 (25%), retuned to 0.50 same message as the above.
@export var inflated_hp_bonus_pct: float = 0.50

@export_group("Regen")
# Renamed from regen_pct_per_sec (2026-08-23) -- user kept specifying this
# as a tick amount ("make it per .2 seconds", "make regen tick at .1 per
# second", then explicitly "5% per .1 sec"), not an annualized rate, so the
# field itself is now literally "% of max_hp restored per tick" instead of
# "% per second" -- direct, no rate/interval math to reconcile. %/of
# CURRENT max_hp, not a flat amount -- so it heals for more in raw numbers
# while inflated, since the base it's a percentage of is bigger then.
# Permanently disabled once the lantern's destroyed (see
# _lantern_destroyed/on_lantern_destroyed()).
@export var regen_pct_per_tick: float = 0.05
# How often a tick fires (2026-08-23, user request: "make regen tick at .1
# per second" -- was 0.2). Combined with regen_pct_per_tick (5%) above,
# current effective rate is 5% every 0.1s = 50%/sec. See _tick_regen().
@export var regen_tick_interval: float = 0.1

@export_group("Inflated Punish")
# Landing a hit while inflated shocks Elana back (2026-08-22, user's exact
# spec: "if inflated. elana gets shocked when attacks land on the mini
# boss") -- doesn't block the hit, she still damages the boss normally,
# this is purely retaliatory on top. Pure (non-elemental) damage, same
# convention Elemander's electrified water uses for its own shock-adjacent
# tick damage.
@export var on_hit_shock_damage: int = 4

@export_group("Deflated Pulsing Shock")
# Continuous AoE hazard while deflated (2026-08-22, user's exact spec: "if
# deflated, continually emits a pulsing shock") -- same pure-damage-plus-
# shock-status shape as the inflated punish above, just periodic/area
# instead of hit-triggered.
@export var pulsing_shock_damage: int = 6
@export var pulsing_shock_interval: float = 2.5

@export_group("Lantern Reveal")
# Only while inflated (2026-08-22, user's exact spec: "if inflated, theres
# a chance it shows its lanturn"). Rolled every lantern_reveal_check_interval
# seconds at lantern_reveal_chance odds; a hit succeeding only during
# lantern_reveal_duration destroys it (see voltangler_lantern.gd) --
# outside that window the Lantern's own Hurtbox has monitoring off entirely,
# so it's not just invulnerable, it's not a valid hit target at all.
@export var lantern_reveal_check_interval: float = 2.0
@export var lantern_reveal_chance: float = 0.25
@export var lantern_reveal_duration: float = 1.5

var _state: int = State.DEFLATED
var _state_timer: float = 0.0
var _base_max_hp: int = 0
var _lantern_destroyed: bool = false
var _lantern_revealed: bool = false
var _lantern_check_timer: float = 0.0
var _lantern_reveal_timer: float = 0.0
var _pulsing_shock_timer: float = 0.0
var _regen_tick_timer: float = 0.0

@onready var _body_sprite: AnimatedSprite2D = $AnimatedSprite2D
# 2026-09-06, user explicit: "the fin is only for the big version. not the
# deflated version... fin is just consistent animation" -- separate node
# from _body_sprite, played once in _ready() and never touched again except
# for .visible, so it loops continuously on its own regardless of the body's
# deflated/big state swaps.
@onready var _fin_sprite: AnimatedSprite2D = $Fin
@onready var _lantern: Node2D = $Lantern
@onready var _lantern_hurtbox: Area2D = $Lantern/Hurtbox
@onready var _lantern_glow: Sprite2D = $Lantern/Glow
@onready var _pulsing_shock_zone: Area2D = $PulsingShockZone

func _ready() -> void:
	super._ready()
	enemy_type = GameData.EnemyType.STATIONARY
	_base_max_hp = max_hp
	defense = deflated_defense
	_lantern.boss_ref = self
	_lantern_hurtbox.monitoring = false
	_lantern_glow.visible = false
	_body_sprite.play("deflated")
	# Played once, never restarted — see _fin_sprite's own comment above.
	# Starts hidden; _start_inflate()'s transition reveals it once actually
	# INFLATED, _start_deflate()'s hides it again.
	_fin_sprite.visible = false
	_fin_sprite.play("flutter")

# base_enemy.gd's own _update_sprite() (called every physics frame from
# _physics_process()) auto-picks "attack"/"walk"/"idle" off movement/attack
# timers and unconditionally sets flip_h off `direction` -- none of which
# apply here (no AttackZone, enemy_type STATIONARY so velocity/direction
# never change, and the body's only 2 animations are "deflated"/"big", so
# that generic switch would just never match anything anyway). Skipped
# entirely for the same reason ceiling_grabber.gd/mantrap.gd do -- full
# manual control via _ready()/_start_inflate()/_start_deflate() instead.
func _update_sprite() -> void:
	pass

# Floats -- no falling, no ground needed. base_enemy.gd's own version
# unconditionally adds gravity unless is_on_floor(), which would just sink
# her since she's never meant to touch a floor at all.
func _apply_gravity(_delta: float) -> void:
	velocity.y = 0.0

# Deliberately bypasses enemy.gd's own override (`$AttackZone.position.x =
# ...`, no null-guard, unlike every other optional-node lookup in this
# codebase) -- there's no AttackZone node in this scene at all (see the
# header comment on why: no standard melee for this boss, only the custom
# shock mechanics), so calling up through enemy.gd would hard-error on a
# missing node. Reimplements base_enemy.gd's own two-line version directly
# instead of chaining through the one level that breaks.
func _update_zones() -> void:
	$AggroZone.position.x = aggro_zone_offset * direction

# 2026-09-06, real bug found (user: "like voltangler is patrolling. is it
# fixed?") -- enemy.gd's own _move() (never overridden here before now)
# checks `if target:` BEFORE ever looking at enemy_type, so setting
# enemy_type = STATIONARY in _ready() never actually did anything once
# Elana entered the 500x300 AggroZone -- base_enemy.gd's own _ready() wires
# up AggroZone's body_entered/exited unconditionally (never disconnected
# here), so target got set and the generic chase branch
# (`velocity.x = chase_speed * direction`) overrode STATIONARY outright,
# visibly sliding her toward/away from Elana as target crossed
# stop_distance. Always stationary here instead, ignoring target entirely
# -- Voltangler was never designed to chase (see this file's own header
# comment: "Floats in place... no standard melee"); target is only ever
# read by enemy.gd's own chase/WallCheck logic, nothing in this boss's own
# custom mechanics (pulsing shock, on-hit punish, lantern reveal) needs it.
func _move(_delta: float) -> void:
	velocity.x = 0

func _physics_process(delta: float) -> void:
	# 2026-09-06, real bug found (user: "voltangler should not be moving") --
	# every non-magic weapon hit sets _pending_knockback whenever
	# GameData.weapon_knockback_x/y != 0.0 (hit_handler.gd's on_hit()),
	# which base_enemy.gd's own _physics_process() (called via super below)
	# writes straight to velocity before move_and_slide() -- same mechanism
	# Mantrap explicitly guards against to stay rooted. Voltangler never had
	# that guard despite being designed stationary (enemy_type STATIONARY
	# only zeroes velocity in _move(), which is skipped entirely while
	# is_stunned -- exactly the state a knockback hit puts her in). Same
	# fix, same spot mantrap.gd uses -- discard any queued push before
	# super() gets a chance to consume it.
	_pending_knockback = Vector2.ZERO
	super._physics_process(delta)
	_tick_state_cycle(delta)
	_tick_regen(delta)
	match _state:
		State.INFLATED:
			_tick_lantern_reveal(delta)
		State.DEFLATED:
			_tick_pulsing_shock(delta)

func _tick_state_cycle(delta: float) -> void:
	match _state:
		State.DEFLATED:
			_state_timer += delta
			if _state_timer >= deflated_duration:
				_start_inflate()
		State.INFLATED:
			_state_timer += delta
			if _state_timer >= inflated_duration:
				_start_deflate()
		State.INFLATING, State.DEFLATING:
			pass  # resolved by the tween callbacks in _start_inflate()/_start_deflate()

func _start_inflate() -> void:
	_state = State.INFLATING
	_state_timer = 0.0
	defense = inflated_defense
	var bonus: float = _base_max_hp * inflated_hp_bonus_pct
	max_hp = _base_max_hp + int(bonus)
	hp = min(max_hp, hp + bonus)
	# 2026-09-06, real sprite art added -- previously tweened _body_visual's
	# scale 1.0->inflated_scale here as a placeholder-ColorRect stand-in for
	# actually being bigger. Real, natively-sized art exists for both states
	# now (deflated small fish vs. big spiky pufferfish), so no scaling at
	# all — just an interval matching the same state_transition_duration
	# timing the old tween used, then swap sprites/reveal the fin once she's
	# actually INFLATED (user explicit: keep showing deflated art through the
	# whole transition, don't pop early).
	var tween := create_tween()
	tween.tween_interval(state_transition_duration)
	tween.tween_callback(func():
		_state = State.INFLATED
		_body_sprite.play("big")
		_fin_sprite.visible = true
	)

func _start_deflate() -> void:
	_state = State.DEFLATING
	_state_timer = 0.0
	defense = deflated_defense
	max_hp = _base_max_hp
	hp = min(hp, max_hp)
	_hide_lantern()
	var tween := create_tween()
	tween.tween_interval(state_transition_duration)
	tween.tween_callback(func():
		_state = State.DEFLATED
		_body_sprite.play("deflated")
		_fin_sprite.visible = false
	)

# %-based regen, deliberately separate from base_enemy.gd's own flat
# hp_regen field (stays 0, unused) -- needs to read max_hp fresh each frame
# since inflate/deflate changes it, a flat amount wouldn't scale with that.
# Deliberately does NOT respect regen_delay_timer (2026-08-23 fix -- had
# been checking it, matching the "pause healing briefly after taking
# damage" rule every other regen in this codebase follows, but base_enemy.gd
# sets that to 3.0s on every single hit she takes -- during an actual fight
# she's getting hit constantly, so that guard was active almost the entire
# time and regen barely ever actually ran. User's original spec was
# explicit: "regenerates constantly" -- this is now truly unconditional
# aside from the lantern/death/full-hp checks below. Ticks in discrete
# regen_tick_interval chunks (2026-08-23, see that export's own comment)
# rather than smoothly every physics frame -- regen_pct_per_tick is applied
# directly each tick, no rate/interval math needed.
func _tick_regen(delta: float) -> void:
	if _lantern_destroyed or hp <= 0 or hp >= max_hp:
		return
	_regen_tick_timer -= delta
	if _regen_tick_timer > 0.0:
		return
	_regen_tick_timer = regen_tick_interval
	hp = min(max_hp, hp + max_hp * regen_pct_per_tick)

func _tick_lantern_reveal(delta: float) -> void:
	if _lantern_destroyed:
		return
	if _lantern_revealed:
		_lantern_reveal_timer -= delta
		if _lantern_reveal_timer <= 0.0:
			_hide_lantern()
		return
	_lantern_check_timer -= delta
	if _lantern_check_timer <= 0.0:
		_lantern_check_timer = lantern_reveal_check_interval
		if randf() < lantern_reveal_chance:
			_show_lantern()

# Source of truth voltangler_lantern.gd's own on_hit() checks before letting
# a hit actually register (2026-08-23, see that file's own comment) --
# doesn't just trust Hurtbox.monitoring stayed correctly synced with the
# visual/reveal state, asks the real state directly. Only true during an
# actual reveal window (which itself only ever happens while INFLATED, so
# "only show it on inflated" falls out of this for free), never once the
# lantern's destroyed.
func is_lantern_vulnerable() -> bool:
	return _lantern_revealed and not _lantern_destroyed

func _show_lantern() -> void:
	_lantern_revealed = true
	_lantern_reveal_timer = lantern_reveal_duration
	# 2026-09-06, user explicit: "the 2 sprites of the inflated version. just
	# use copy 6. copy 7 is the lantern show. use copy 7 when doing the
	# lantern show thing" -- body swaps to the dedicated "lantern" pose
	# (copy 7) for the reveal window instead of copy 6/7 alternating as a
	# generic "big" idle loop.
	_body_sprite.play("lantern")
	# Same is_instance_valid() guards as _hide_lantern() below, for the same
	# reason -- only ever reached via _tick_lantern_reveal(), which already
	# checks _lantern_destroyed first, so this is defensive/symmetric rather
	# than fixing a currently-reachable crash.
	if is_instance_valid(_lantern_hurtbox):
		_lantern_hurtbox.monitoring = true
	if is_instance_valid(_lantern_glow):
		_lantern_glow.visible = true
		_lantern_glow.modulate.a = 1.0

func _hide_lantern() -> void:
	_lantern_revealed = false
	# Reverts the "lantern" pose (copy 7) _show_lantern() swapped to, back
	# to the normal "big" idle (copy 6). Harmless when called from
	# _start_deflate() too (before the body's even shown "lantern" this
	# cycle, or right as she's deflating) -- the deflate transition's own
	# tween_callback overwrites this to "deflated" a moment later regardless.
	if is_instance_valid(_body_sprite):
		_body_sprite.play("big")
	# 2026-08-23 fix ("Invalid assignment of property or key 'monitoring'...
	# on a base object of type 'previously freed'") -- this line was missing
	# the same is_instance_valid() guard _lantern_glow already had right
	# below it. _hide_lantern() is called unconditionally from
	# _start_deflate() every single deflate cycle, not just from
	# on_lantern_destroyed() -- once the lantern's actually been destroyed
	# and queue_free()'d, the very next deflate hit this stale reference.
	if is_instance_valid(_lantern_hurtbox):
		_lantern_hurtbox.monitoring = false
	if is_instance_valid(_lantern_glow):
		_lantern_glow.visible = false

# Called by voltangler_lantern.gd the instant it's actually destroyed
# (2026-08-22, user's exact spec: "elana can destroy it and disable healing
# of the boss") -- permanent for the rest of the fight, no reset condition,
# same one-way shape as Broodspawner's anchors-destroyed->DOWN trigger.
# Logged (2026-08-23, user request: "at a moment regen stops. idk when. can
# you add log when lantern is broken") -- this is the exact, only moment
# regen permanently stops, so the timestamp/hp-at-the-time here directly
# answers "when."
# Generic death hook hit_handler.gd's own _die() already calls on any enemy
# that implements it (2026-08-23) -- sets the permanent boss-reward flag
# (see GameData.voltangler_defeated's own comment), same pattern
# ant_queen.gd/elemental_golem.gd already use for their own rewards.
func on_death() -> void:
	GameData.voltangler_defeated = true

func on_lantern_destroyed() -> void:
	_lantern_destroyed = true
	print("[Voltangler] LANTERN DESTROYED at hp=%.0f/%d — regen permanently disabled" % [hp, max_hp])
	_hide_lantern()

func _tick_pulsing_shock(delta: float) -> void:
	_pulsing_shock_timer -= delta
	if _pulsing_shock_timer > 0.0:
		return
	_pulsing_shock_timer = pulsing_shock_interval
	_spawn_pulsing_shock_visual()
	for body in _pulsing_shock_zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			_shock_player(body, pulsing_shock_damage)

# 2026-09-06, user explicit: "for the voltangler deflated pulsing electric
# shock. show color rect or radius glow when doing the pulse" -- previously
# fired with zero visual feedback at all. Same radial-fade-and-free
# technique spark_jelly.gd's own _spawn_pulse_visual() already uses for its
# near-identical AOE pulse, for consistency -- a ring scaled to the actual
# PulsingShockZone radius (read from its own CollisionShape2D rather than a
# hardcoded number, so it can't drift out of sync if that shape's ever
# retuned), fanning out and fading regardless of whether Elana's actually
# in range this cycle (a hazard telegraph, not a hit-confirm).
func _spawn_pulsing_shock_visual() -> void:
	var shape: CircleShape2D = _pulsing_shock_zone.get_node("CollisionShape2D").shape
	var radius: float = shape.radius
	var poly = Polygon2D.new()
	poly.color = Color(1.0, 0.95, 0.3, 0.35)
	var pts := PackedVector2Array()
	for i in 32:
		var a = (float(i) / 32.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.global_position = global_position
	poly.z_index = 3
	get_parent().add_child(poly)
	var tween = get_tree().create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.4)
	tween.tween_callback(poly.queue_free)

func _shock_player(player: Node, damage: int) -> void:
	if player.has_method("take_damage"):
		player.take_damage(damage, false, self)
	if player.has_method("apply_shock"):
		player.apply_shock(GameData.SHOCK_STUN_DURATION)

# Retaliatory punish, inflated only (2026-08-22, see on_hit_shock_damage's
# own comment) -- fires before the actual hit resolves (super.on_hit()
# below), same ordering elemental_golem.gd uses for its own Shock Coat
# punish; doesn't block or reduce the incoming damage in any way, purely
# additive.
func on_hit(hit_direction: int, damage: int = 10, is_magic: bool = false, attacker: Node = null) -> void:
	if _state == State.INFLATED and attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player"):
		_shock_player(attacker, on_hit_shock_damage)
	super.on_hit(hit_direction, damage, is_magic, attacker)

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	if _state == State.INFLATED and attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player"):
		_shock_player(attacker, on_hit_shock_damage)
	super.on_elemental_hit(element, hit_direction, damage, attacker)
