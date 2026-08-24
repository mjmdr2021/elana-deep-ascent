extends AnimatableBody2D

# Mountain Judgement's rising terrain -- a real, independent physics body
# (2026-08-24, reworked per user: "lets make the terrain a different scene
# outside of graniteus... it should be rested on ground. its not attached
# to golem"). AnimatableBody2D is Godot's dedicated moving-platform body --
# a CharacterBody2D standing on top of one automatically rides along as it
# moves (via move_and_slide()'s own built-in platform inheritance), so
# Graniteus needs no special code to be carried up/down by this at all; he
# just naturally rests on it like any other floor.
#
# Spawned buried below ground (its CollisionShape2D/visual extend well
# below the root's own position, which is set to sit exactly at ground
# level) so its base never shows a gap as it rises -- reads as a mountain
# pushing up out of the earth, not a block floating up from nothing.
#
# rise()/fall() are timer-driven tweens (not collision-detected "reached
# height") -- matches how every other timed sequence in this codebase
# already works (Cobblecroak/Wyrmbat/Elemental Golem), simpler than
# polling for contact.
#
# collision_layer 1 -- the normal shared terrain layer, so this genuinely
# collides with Elana and loose ore pieces too, not just Graniteus
# (2026-08-24, user explicit: "i still want the terrain of the golem to be
# collision with me and the ores"). Briefly isolated onto its own dedicated
# layer (32) while chasing an ore-piece-stuck/FPS bug, but that turned out
# to be caused by _bounce_nearby_ore() repeatedly re-launching the same
# piece many times in a fraction of a second (fixed at the source with a
# cooldown in ore_piece.gd), not by this platform's own collision -- so
# there was no real reason left to keep ore pieces (or Elana) excluded from
# it, and reverted back to the shared layer.

@export var rise_height: float = 200.0
@export var rise_time: float = 1.0
@export var fall_time: float = 0.2

var _base_y: float = 0.0

func _ready() -> void:
	_base_y = position.y

func rise() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "position:y", _base_y - rise_height, rise_time)
	await tween.finished

func fall() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "position:y", _base_y, fall_time)
	await tween.finished
