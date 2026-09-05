extends "res://enemy.gd"

# Mantrap (renamed from "Venus Flytrap" 2026-09-05) -- a fully stationary
# plant enemy. Never chases, never uses the generic melee attack cycle
# (extends enemy.gd for the shared HP/hit/death plumbing only, same "too
# different a behavior shape" reasoning ceiling_grabber.gd already makes
# for its own grab-and-hold mechanic, which this closely mirrors).
#
# Standing in contact with it for grab_delay seconds triggers a grab:
# first a brief FULL stun (can't move OR attack -- the "gotcha" moment),
# then an ongoing HOLD (reuses elana.gd's is_trapped system, same as
# ceiling_grabber.gd) where she can't move/dodge but CAN fight back --
# ticking small damage the whole time. Unlike Ceiling Grabber, there's no
# partial hit-count break-free: the ONLY way out is killing it (user
# explicit: "by killing it inside... only lets go when dead").
#
# Invulnerable outside the HOLDING state (user explicit: "elana cant
# attack it when not grabbed") -- on_hit()/on_elemental_hit() below are a
# no-op unless it's actually holding her, so the only way to ever damage
# it is to let it grab you first.
enum GrabState { DORMANT, GRABBING, STUNNED, HOLDING }

@export var grab_delay: float = 0.3  # user spec: dwell-check before the grab actually triggers
@export var stun_duration: float = 1.0  # user spec: full lock right after the grab
@export var hold_tick_damage: int = 5
@export var hold_tick_interval: float = 1.0  # user spec: damage over time every 1 second
@export var hold_offset: Vector2 = Vector2(0, -8)  # where she's held, relative to the plant

var _state: GrabState = GrabState.DORMANT
var _state_timer: float = 0.0
var _hold_tick_timer: float = 0.0
var _held_target: Node = null
var _elana_in_zone: bool = false

func _ready() -> void:
	super._ready()
	# 2026-09-05, real bug found (user: "remember to always make the
	# collision stuff or area stuff in scene!") -- AggroZone's detection
	# shape used to be built here in script (RectangleShape2D.new()), the
	# same violation ceiling_grabber.gd's own _ready() also has. Moved to a
	# real authored RectangleShape2D in mantrap.tscn instead -- AggroZone
	# and its CollisionShape2D are both positioned/sized there now, nothing
	# left to set up here.
	# Rooted -- the grab above is its only "attack," same as
	# ceiling_grabber.gd disabling this for the same reason.
	$AttackZone.collision_mask = 0
	# Inherited from enemy.tscn's chase-enemy template, defaults to a
	# straight-down ray -- meaningless for a rooted plant that never
	# checks walls/ledges, and visibly shows up as a red debug arrow.
	$WallCheck.enabled = false
	# 2026-09-05, real bug found (user: "why did it still grab me even if
	# im out of aggro collision zone?"): the inherited `target` field
	# doesn't clear the instant she leaves AggroZone -- base_enemy.gd gives
	# every enemy a 2s deaggro_timer grace period first (for normal chase
	# enemies, so a momentary gap doesn't drop pursuit), only clearing
	# `target` once THAT expires. Since grab_delay (0.3s) is far shorter
	# than that 2s window, briefly touching the zone and immediately
	# backing out still let the grab complete. Tracks live overlap
	# independently instead -- doesn't touch/replace the base's own
	# target/deaggro_timer handling (still runs normally alongside this),
	# just doesn't use it for the dwell-check.
	$AggroZone.body_entered.connect(_on_zone_entered)
	$AggroZone.body_exited.connect(_on_zone_exited)
	# 2026-09-05, user explicit: "make the enemy be above elana in terms of
	# z index. so it means the mantrap is covering elana." Elana's own
	# sprite sits at z_index 2 (elana.gd's _ready()) -- 3 renders above it,
	# same level other "draws on top of her" effects in this codebase
	# already use.
	$AnimatedSprite2D.z_index = 3

func _on_zone_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_zone = true

func _on_zone_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_elana_in_zone = false

# Rooted -- never affected by knockback/knockup (user explicit). Discards
# any queued push BEFORE base_enemy.gd's own _physics_process() gets a
# chance to consume it (that base logic reads _pending_knockback and
# writes it straight to velocity, then move_and_slide() applies it -- it's
# the same field hit_handler.gd's on_hit() sets for every enemy on any
# weapon hit). Everything else in that function (gravity, HP bar, sprite,
# move_and_slide) still runs normally via super().
func _physics_process(delta: float) -> void:
	_pending_knockback = Vector2.ZERO
	super._physics_process(delta)

# 2026-09-05, real bug found (user: "its still on sprite 1 when grab
# mode"): base_enemy.gd's own _update_sprite() runs every physics frame
# right after _move() and picks an animation purely from movement/attack
# state (idle/walk/attack) -- since Mantrap never moves or attacks, it
# computed "idle" every single tick and force-called .play() on it,
# stomping whatever _start_stun()/_start_hold() had just set to "grab"
# moments earlier in that same frame. Skipped entirely -- animation is
# fully manual here (see _ready()'s initial "idle" and _start_stun()'s
# "grab"/frame 2), same guard _update_zones() below already uses for a
# different piece of the same "this isn't a walking/chasing enemy" reason.
func _update_sprite() -> void:
	pass

# Skip the base class's per-frame AggroZone/eye-glow repositioning (it
# assumes a walking/chasing enemy) -- same guard ceiling_grabber.gd uses.
func _update_zones() -> void:
	pass

func _move(delta: float) -> void:
	match _state:
		GrabState.DORMANT:
			velocity = Vector2.ZERO
			if _elana_in_zone and target:
				_start_grab(target)
		GrabState.GRABBING:
			velocity = Vector2.ZERO
			# Dwell-check: if she leaves before grab_delay is up, the grab
			# never happens at all (user explicit: "if elana is still in
			# collision after .3 seconds it grabs her" -- implying it
			# doesn't if she isn't). Gated on the real live-overlap flag,
			# not `target` -- see _ready()'s own comment for why.
			if not _elana_in_zone:
				_state = GrabState.DORMANT
				return
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_stun(target)
		GrabState.STUNNED:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				_start_hold()
		GrabState.HOLDING:
			velocity = Vector2.ZERO
			if not is_instance_valid(_held_target):
				_held_target = null
				return
			_hold_tick_timer -= delta
			if _hold_tick_timer <= 0.0:
				_hold_tick_timer = hold_tick_interval
				_held_target.take_damage(hold_tick_damage, false, self)

func _start_grab(body: Node) -> void:
	_state = GrabState.GRABBING
	_state_timer = grab_delay
	_held_target = body

# Full stun -- she can't move OR attack for stun_duration, distinct from
# HOLDING below (user explicit: "the stun is after the grab," i.e. this
# fires first, then the ongoing can-attack hold begins once it ends).
# This is also the moment the grab actually lands (the 0.3s dwell in
# GRABBING was only the check, not the grab itself) -- user explicit:
# "when grabbing. use the 3rd sprite" -- shows frame 3 immediately right
# here, not delayed to _start_hold() a full second later (that was wrong).
func _start_stun(body: Node) -> void:
	_state = GrabState.STUNNED
	_state_timer = stun_duration
	$AnimatedSprite2D.animation = "grab"
	$AnimatedSprite2D.frame = 2
	if body.has_method("apply_stun"):
		body.apply_stun(stun_duration)

func _start_hold() -> void:
	if not is_instance_valid(_held_target):
		_state = GrabState.DORMANT
		return
	_state = GrabState.HOLDING
	_hold_tick_timer = hold_tick_interval
	if _held_target.has_method("apply_trap"):
		_held_target.apply_trap(self, hold_offset)

# Invulnerable unless actively holding her -- the only way to ever damage
# it is to let it grab you first (user explicit).
func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	if _state != GrabState.HOLDING:
		return
	super.on_hit(hit_direction, damage, is_magic, attacker)

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	if _state != GrabState.HOLDING:
		return
	super.on_elemental_hit(element, hit_direction, damage, attacker)

# Generic base_enemy.gd death hook (hit_handler.gd's _die() calls this if
# present) -- releases her the instant it actually dies, same as
# ceiling_grabber.gd's own on_death(). This is the ONLY way she's ever
# released, per user explicit spec -- no partial break-free.
func on_death() -> void:
	if is_instance_valid(_held_target) and _held_target.has_method("release_trap"):
		_held_target.release_trap()
	_held_target = null
