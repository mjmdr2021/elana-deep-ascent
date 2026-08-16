extends StaticBody2D

# Breakable floor — solid ground until Elana lands a plunge attack on it,
# then it breaks open and lets her drop through. Width/height are adjusted
# in the editor by resizing $CollisionShape2D's RectangleShape2D — that's
# the single source of truth; the ColorRect placeholder and PlungeDetector
# both derive their size from it in _ready() below, so only that one shape
# needs touching.

@export var camera_trauma: float = 0.5
# Plain hit counter, not an HP pool — each landed plunge counts as exactly
# one hit regardless of weapon/damage, breaks once hits_taken reaches this.
@export var hits_to_break: int = 3
var _hits_taken: int = 0
var _original_color: Color
# How far PlungeDetector's shape extends above the solid floor's own top
# surface. It CANNOT just share the solid shape's exact size/position (that
# was the original bug here) — a falling body gets physically stopped by
# the solid collider right at that boundary before ever truly overlapping
# an identically-shaped, identically-placed Area2D (tangent contact, not
# real penetration), so body_entered never fires at all. Extending upward
# means the detector catches her while she's still airborne and falling,
# well before physics collision resolution would halt her on the solid box.
const PLUNGE_DETECT_MARGIN: float = 64.0

# Elana, while she's anywhere inside PlungeDetector (updated via body_
# entered/exited below) — null when she's not. Whether she's currently
# mid-plunge is tracked separately (_was_plunging) and re-checked every
# physics frame instead of relying solely on body_entered, since that only
# fires on a FRESH boundary crossing. After a non-breaking hit she's often
# still standing with part of her body inside this (deliberately tall)
# zone — if her next plunge doesn't jump high enough to fully clear it
# first, body_entered never fires again and the hit silently never
# registers, which is exactly the bug this polling catches instead.
var _body_in_zone: Node = null
var _was_plunging: bool = false

func _ready() -> void:
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	# ColorRect is just the visible placeholder (no sprite art yet) — sized
	# here from the shape itself rather than kept as its own separate size in
	# the editor, so resizing $CollisionShape2D's shape is the only thing
	# that needs touching; the placeholder can't drift out of sync with it.
	var solid_size: Vector2 = $CollisionShape2D.shape.size
	var half_size: Vector2 = solid_size / 2.0
	$ColorRect.offset_left = -half_size.x
	$ColorRect.offset_top = -half_size.y
	$ColorRect.offset_right = half_size.x
	$ColorRect.offset_bottom = half_size.y
	# Own shape (not the solid collider's), same width, taller — see
	# PLUNGE_DETECT_MARGIN above. Shifted up by half the extra height so its
	# bottom edge still lines up with the solid box's top surface and the
	# rest extends upward from there.
	var detect_shape := RectangleShape2D.new()
	detect_shape.size = Vector2(solid_size.x, solid_size.y + PLUNGE_DETECT_MARGIN)
	$PlungeDetector/CollisionShape2D.shape = detect_shape
	$PlungeDetector/CollisionShape2D.position.y = -PLUNGE_DETECT_MARGIN / 2.0
	$PlungeDetector.body_entered.connect(_on_plunge_detector_body_entered)
	$PlungeDetector.body_exited.connect(_on_plunge_detector_body_exited)
	_original_color = $ColorRect.color

func _on_plunge_detector_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_body_in_zone = body
		# Covers the original case too — arriving from well above, already
		# mid-plunge the instant she crosses in.
		_was_plunging = "is_plunge_attacking" in body and body.is_plunge_attacking
		if _was_plunging:
			_register_hit(body)

func _on_plunge_detector_body_exited(body: Node) -> void:
	if body == _body_in_zone:
		_body_in_zone = null
		_was_plunging = false

# Edge-detects the moment a plunge actually STARTS while she's anywhere in
# the zone — not just on a fresh boundary crossing. Catches the "already
# standing partway inside after a non-breaking hit, plunges again without
# fully leaving first" case _on_plunge_detector_body_entered() alone misses.
func _physics_process(_delta: float) -> void:
	if _body_in_zone == null or not is_instance_valid(_body_in_zone):
		return
	var plunging_now: bool = "is_plunge_attacking" in _body_in_zone and _body_in_zone.is_plunge_attacking
	if plunging_now and not _was_plunging:
		_register_hit(_body_in_zone)
	_was_plunging = plunging_now

# One hit per landed plunge — _was_plunging's false->true edge only fires
# once per plunge attempt regardless of how many physics frames she spends
# inside the zone during it.
func _register_hit(body: Node) -> void:
	_hits_taken += 1
	if body.has_method("add_camera_trauma"):
		body.add_camera_trauma(camera_trauma)
	if _hits_taken >= hits_to_break:
		_break()
	else:
		_flash_hit()

func _flash_hit() -> void:
	$ColorRect.color = Color.WHITE
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self):
		$ColorRect.color = _original_color

func _break() -> void:
	# Solid collision goes first — she falls through immediately rather than
	# waiting on the visual, and the detector disables so a second overlap
	# during the break animation can't double-fire.
	$CollisionShape2D.disabled = true
	$PlungeDetector.monitoring = false
	GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
	# Fade only, no scale — a scale-shrink would need a pivot_offset matched
	# to whatever size the ColorRect ends up resized to, which would silently
	# go stale the moment the width/height gets adjusted.
	var tween := create_tween()
	tween.tween_property($ColorRect, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)
