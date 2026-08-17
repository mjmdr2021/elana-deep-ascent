extends "res://enemy.gd"

# Hangs dormant on the ceiling — same detection shape/pattern as
# ceiling_dropper.gd (a tall, narrow strip reshaped from the normal
# AggroZone in _ready(), checked via the standard `target` base_enemy.gd
# already sets when something walks into it, not a custom signal handler).
# Instead of dropping, it grabs: a tongue lashes down and pulls Elana up to
# the ceiling, holding her there (elana.gd's new is_trapped status — locked
# in place, but NOT stunned in the sense of blocking her attack input,
# since escaping means fighting back) while ticking small, infrequent
# damage. Landing hits_to_break hits on it while held snaps the tongue and
# frees her; the tongue then needs tongue_regen_time before it can grab
# again, unless the grabber dies first (on_death() below always releases
# her regardless of state).
enum GrabState { DORMANT, GRABBING, HOLDING, BROKEN }

@export var detect_width: float = 24.0
@export var detect_height: float = 220.0
@export var detect_offset_y: float = 110.0
@export var grab_pull_time: float = 0.3
@export var hold_tick_damage: int = 3
@export var hold_tick_interval: float = 3.0  # "small damage over long intervals"
@export var hits_to_break: int = 3
@export var tongue_regen_time: float = 8.0
@export var hold_offset: Vector2 = Vector2(0, 24)  # where she's held, relative to the grabber
const NORMAL_AGGRO_SIZE := Vector2(100, 32)

var _state: GrabState = GrabState.DORMANT
var _grab_timer: float = 0.0
var _hold_tick_timer: float = 0.0
var _break_hits: int = 0
var _regen_timer: float = 0.0
var _held_target: Node = null

@onready var _tongue: Line2D = $Tongue

func _ready() -> void:
	super._ready()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(detect_width, detect_height)
	$AggroZone/CollisionShape2D.shape = shape
	$AggroZone/CollisionShape2D.position = Vector2.ZERO
	$AggroZone.position = Vector2(0, detect_offset_y)
	# Never physically collides or falls — stays embedded in ceiling art the
	# same way ceiling_dropper.gd's own dormant CollisionShape2D does, and
	# unlike that one, this never re-enables it (the grabber itself never
	# drops or chases).
	$CollisionShape2D.disabled = true
	# Same fix Ant Queen needed — AttackZone can independently detect Elana
	# and fire the generic base_enemy.gd windup->attack cycle regardless of
	# this script's own state machine, since it isn't gated by `target`/
	# aggro at all. Ceiling Grabber's only "attack" is the grab/hold above.
	$AttackZone.collision_mask = 0
	_tongue.visible = false

# Skip the base class's per-frame AggroZone/eye-glow repositioning — it
# would fight the custom hang-below shape set above, same guard
# ceiling_dropper.gd uses.
func _update_zones() -> void:
	pass

func _move(delta: float) -> void:
	match _state:
		GrabState.DORMANT:
			velocity = Vector2.ZERO
			if target:
				_start_grab(target)
		GrabState.GRABBING:
			velocity = Vector2.ZERO
			_update_tongue_visual(_held_target.global_position if is_instance_valid(_held_target) else global_position)
			_grab_timer -= delta
			if _grab_timer <= 0.0:
				_finish_grab()
		GrabState.HOLDING:
			velocity = Vector2.ZERO
			if not is_instance_valid(_held_target):
				_reset_after_release()
				return
			_update_tongue_visual(_held_target.global_position)
			_hold_tick_timer -= delta
			if _hold_tick_timer <= 0.0:
				_hold_tick_timer = hold_tick_interval
				_held_target.take_damage(hold_tick_damage, false, self)
		GrabState.BROKEN:
			velocity = Vector2.ZERO
			_regen_timer -= delta
			if _regen_timer <= 0.0:
				_state = GrabState.DORMANT

func _start_grab(body: Node) -> void:
	_state = GrabState.GRABBING
	_grab_timer = grab_pull_time
	_held_target = body
	_tongue.visible = true

func _finish_grab() -> void:
	if not is_instance_valid(_held_target):
		_reset_after_release()
		return
	_state = GrabState.HOLDING
	_break_hits = 0
	_hold_tick_timer = hold_tick_interval
	if _held_target.has_method("apply_trap"):
		_held_target.apply_trap(self, hold_offset)

func _update_tongue_visual(target_pos: Vector2) -> void:
	_tongue.global_position = global_position
	_tongue.points = PackedVector2Array([Vector2.ZERO, target_pos - global_position])

# Every landed hit while HOLDING counts toward breaking the tongue, on top
# of whatever damage it already does through the normal on_hit()/
# on_elemental_hit() flow below — escaping isn't free, it's real damage
# too, just also a fixed hit-count regardless of how much damage those
# hits happened to deal.
func _register_break_hit() -> void:
	if _state != GrabState.HOLDING:
		return
	_break_hits += 1
	if _break_hits >= hits_to_break:
		_break_tongue()

func _break_tongue() -> void:
	if is_instance_valid(_held_target) and _held_target.has_method("release_trap"):
		_held_target.release_trap()
	_reset_after_release()
	_state = GrabState.BROKEN
	_regen_timer = tongue_regen_time

func _reset_after_release() -> void:
	_held_target = null
	_tongue.visible = false

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, attacker: Node = null) -> void:
	super.on_hit(hit_direction, damage, is_magic, attacker)
	_register_break_hit()

func on_elemental_hit(element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	super.on_elemental_hit(element, hit_direction, damage, attacker)
	_register_break_hit()

# Generic base_enemy.gd death hook (hit_handler.gd's _die() calls this if
# present) — releases her regardless of state if the grabber dies while
# holding her, same as the tongue breaking, just via a kill instead.
func on_death() -> void:
	if is_instance_valid(_held_target) and _held_target.has_method("release_trap"):
		_held_target.release_trap()
	_reset_after_release()
