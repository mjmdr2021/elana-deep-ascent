extends Node2D

# Permanent "explored trail" fog of war — three visual states:
#   1. Never explored: this node's overlay stays fully opaque black over that
#      spot — pitch black, nothing visible at all, no preview.
#   2. Explored, Glint's light not currently there: overlay is erased
#      (transparent) here, showing whatever's underneath — CanvasModulate's
#      own dim ambient color, "dark but visible."
#   3. Explored + Glint's light currently reaching this spot: same erased
#      overlay, but now showing full brightness from her own live light on
#      top of the ambient.
# The overlay (FogOverlay, a scene-authored child — see the @onready
# section below) is a full-SCREEN ColorRect (same always-covers-everything
# anchoring as BootCover below), NOT a world-space sprite sized to the
# sliding window — an earlier version tried exactly that (position/scale
# the sprite to match the window) and left real gaps at the screen edges
# whenever the camera showed more area than the window covered. A shader
# (fog_overlay.gdshader) samples the small window texture using a world-
# space lookup instead: for any screen pixel whose world position falls
# outside the window's current data, it outputs solid black rather than
# leaving that pixel uncovered — the overlay structurally can't have gaps
# because it never stops covering the full screen, no matter what the
# window/camera are doing. A separate BootCover child guarantees full
# coverage from frame 0 too, before this dynamic system has even finished
# loading (the shader's uniform values — the actual window texture, world
# rects, etc — aren't populated until _ready() runs).
#
# Also wall-aware — CanvasModulate's dim ambient is uniform across the
# whole world, so an erase brush with no wall check would still show that
# dim tone through walls/platforms (confirmed — a blind circle alone let
# rooms above stacked platforms show through). This is the ONLY thing
# enforcing that — Glint's own light rendering isn't wall-blocked (a
# Light2D shadow_enabled + occluder system was built and validated for
# that, then deliberately dropped: not needed), so this file alone is what
# keeps the PERMANENT trail from marking never-actually-seen areas as
# explored.
#
# Visibility is computed with recursive shadowcasting (see
# _visible_cells()), not physics raycasts — several raycasting variants
# were tried first (angle-bucketed, per-pixel, multi-sample) and each had
# its own artifact (bleed-through, hard corner shadows, aliasing at finer
# resolution). Shadowcasting is the standard technique for exactly this
# problem in grid-based games (used by NetHack, Brogue, etc.): it works
# directly on the tile grid, recursively scanning outward in 8 octants and
# tracking visible angle-slope ranges symbolically instead of approximating
# from sampled rays — deterministic, no interpolation/sampling artifacts.
#
# Sliding window: the FULL exploration record (_full_image) covers the
# whole world_rect and is never itself uploaded to the GPU — only a small,
# fixed-size _window_image/_window_texture (WINDOW_SIZE, in mask pixels) is
# actually displayed, recentered on her as she moves. ImageTexture.update()
# re-uploads its ENTIRE image every call; doing that with one texture
# covering a full open-world map, every frame she's moving, would not
# scale (this test scene's small world_rect made that cost invisible, but
# the real map is far bigger). A fixed-size window bounds the GPU upload
# cost regardless of total map size — recentering (recopy + reupload) is
# still bounded by that same small size, so it's cheap even though it also
# happens on demand rather than every frame.

# World-space rectangle this fog covers — must contain everywhere the player
# can go in this scene. Tune per-scene in the Inspector; too small clips
# exploration at the edges, too large wastes mask resolution.
@export var world_rect: Rect2 = Rect2(-200, -200, 700, 500)
# 1 mask pixel per this many world pixels — lower = smoother/finer erased
# trail but a bigger mask image to paint/store/persist.
@export var mask_scale: float = 4.0
# Smaller than Glint's own 128px light radius, on purpose — erasing every
# physics frame instead of only every repaint_distance means consecutive
# stamps overlap heavily regardless of radius (a frame of movement is only
# a few px), so a tighter radius reads as a closer-fitting trail instead of
# one big blurry blob, without leaving gaps.
@export var brush_radius: float = 72.0  # world px, soft-edged
# Save-to-GameData throttle only (see _erase_at()) — the visual erase now
# runs every physics frame for smoothness, but re-encoding the whole mask
# to PNG + base64 and writing it to GameData is real, avoidable cost if
# done that often too; only the persisted save needs throttling.
@export var save_interval: float = 0.5  # seconds
# Fixed display-window size, in mask pixels — generously large enough to
# comfortably cover a full screen at typical zoom plus margin, so
# recentering happens rarely during normal movement, not every frame.
# Independent of world_rect's own size.
@export var window_size: Vector2i = Vector2i(200, 150)
# How close (world px) to the window's edge before recentering it.
@export var window_recenter_margin: float = 64.0
# World px — a circle this size around Elana's own position is always fully
# revealed regardless of mask/brush state (see fog_overlay.gdshader). Kept
# tight to just her sprite, not a bonus vision radius (well under
# brush_radius/Glint's own light range).
@export var elana_reveal_radius: float = 28.0
# World px — how far outside elana_reveal_radius the cutout eases back to
# normal fog sampling, instead of a hard-edged circle. Must stay > 0 (the
# shader's smoothstep needs distinct start/end values).
@export var elana_reveal_softness: float = 20.0

var _full_image: Image
var _window_image: Image
var _window_texture: ImageTexture
var _window_origin: Vector2i = Vector2i.ZERO  # top-left, in full-image mask px
var _terrain: TileMap
var _mask_size: Vector2i
var _save_timer: float = 0.0
var _mask_dirty: bool = false

# Both scene-authored children (not created via .new() in script) — see
# glint.tscn's BodyShape for the same reasoning: real nodes are visible/
# tunable in the editor instead of hidden in code.
#   FogOverlay (CanvasLayer > ColorRect, full-screen anchored — same
#     structure as BootCover just below): the actual dynamic fog display.
#     Its ShaderMaterial (fog_overlay.gdshader) is a scene-authored
#     resource, not built via ShaderMaterial.new() in script — an earlier
#     version constructed it at runtime and hit a render-thread race
#     ("version_get_shader: Parameter version is null", spamming every
#     frame, overlay rendering as solid white) that a scene-loaded
#     material resource doesn't have. Script only ever pushes dynamic
#     uniform values into the already-existing material below.
#   BootCover (CanvasLayer > ColorRect, full-screen, opaque black): exists
#     from frame 0 with zero script dependency, so there's never a gap
#     where the map is visible before the real fog is ready — building/
#     loading the full exploration image for a large map can take a
#     noticeable moment. Hidden once _ready() finishes below.
@onready var _overlay: ColorRect = $FogOverlay/ColorRect
@onready var _overlay_material: ShaderMaterial = _overlay.material
@onready var _boot_cover: CanvasLayer = $BootCover

func _ready() -> void:
	# First TileMap sibling — not hardcoded to the name "Terrain" so this
	# still works if a scene names/nests it differently.
	for sibling in get_parent().get_children():
		if sibling is TileMap:
			_terrain = sibling
			break
	_mask_size = Vector2i((world_rect.size / mask_scale).ceil())
	window_size = Vector2i(min(window_size.x, _mask_size.x), min(window_size.y, _mask_size.y))
	_full_image = Image.create(_mask_size.x, _mask_size.y, false, Image.FORMAT_LA8)
	# Opaque black everywhere — fully hides the world until erased.
	_full_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_load_saved_mask()

	_window_image = Image.create(window_size.x, window_size.y, false, Image.FORMAT_LA8)
	_window_texture = ImageTexture.create_from_image(_window_image)

	_overlay_material.set_shader_parameter("window_tex", _window_texture)

	_recenter_window((_mask_size - window_size) / 2)
	_boot_cover.visible = false

func _physics_process(delta: float) -> void:
	var elana = get_tree().get_first_node_in_group("player")
	if elana == null:
		return
	_ensure_window_covers_view()
	_overlay_material.set_shader_parameter("elana_world_pos", elana.global_position)
	_overlay_material.set_shader_parameter("elana_reveal_radius", elana_reveal_radius)
	_overlay_material.set_shader_parameter("elana_reveal_softness", elana_reveal_softness)
	_erase_at(elana.global_position)
	# Glint is elana.gd's own "Glint" child (see elana.gd's get_node("Glint")
	# calls) — she floats near Elana normally but can detach and fly ahead
	# independently during scouting (GameData.glint_scouting), so erasing
	# only around Elana would leave scouted-ahead areas unrevealed even
	# though her light was genuinely there. Doesn't affect window sizing/
	# position — that's tied to the camera (see _ensure_window_covers_view),
	# not to either character's position directly.
	var glint := elana.get_node_or_null("Glint")
	if glint != null:
		_erase_at(glint.global_position)
	if not _mask_dirty:
		return
	_save_timer += delta
	if _save_timer < save_interval:
		return
	_save_timer = 0.0
	_mask_dirty = false
	GameData.fog_mask_png = Marshalls.raw_to_base64(_full_image.save_png_to_buffer())

# Keeps the display window both big enough and correctly positioned to
# cover whatever's actually on screen — tied to whichever Camera2D is
# currently active (Elana's own, or Glint's ScoutCamera during scouting,
# via get_viewport().get_camera_2d()), not fixed to either character's
# position, since the camera is what actually determines what's visible
# and it doesn't always match either of their exact positions (drag/
# smoothing offsets, or a completely different camera during scouting).
# Confirmed by testing: a fixed window_size sized for normal zoom left the
# real map's edges of screen uncovered whenever the camera zoomed out
# further than that (e.g. boss fights) — this makes the window always
# exceed whatever the camera is actually showing, at any zoom level.
const WINDOW_VIEW_MARGIN: float = 1.5  # safety multiplier over the raw visible area

func _ensure_window_covers_view() -> void:
	var viewport := get_viewport()
	if viewport.get_camera_2d() == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	# Derived from the viewport's actual canvas transform — the exact
	# world<->screen mapping Godot uses to render THIS frame — instead of
	# reconstructed by hand from camera.global_position/zoom. That
	# reconstruction was a real bug: Camera2D's on-screen position can lag
	# behind its own global_position (drag margins/position smoothing), so
	# the hand-built version visibly diverged from the true view during
	# fast vertical movement — confirmed by testing: jumping dragged the
	# whole fog overlay out of alignment, and Elana's own reveal circle
	# (see elana_world_pos below) sat visibly offset from her. The canvas
	# transform can't diverge from the true view because it IS the true
	# view, whatever the camera is doing to produce it.
	var screen_to_world: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var world_top_left: Vector2 = screen_to_world * Vector2.ZERO
	var world_bottom_right: Vector2 = screen_to_world * viewport_size
	var visible_world_size: Vector2 = world_bottom_right - world_top_left
	var camera_world_origin: Vector2 = world_top_left
	_overlay_material.set_shader_parameter("camera_world_origin", camera_world_origin)
	_overlay_material.set_shader_parameter("camera_world_size", visible_world_size)

	var padded_world_size: Vector2 = visible_world_size * WINDOW_VIEW_MARGIN
	var required_size := Vector2i(
		int(ceil(padded_world_size.x / mask_scale)),
		int(ceil(padded_world_size.y / mask_scale)))
	required_size.x = min(required_size.x, _mask_size.x)
	required_size.y = min(required_size.y, _mask_size.y)
	var camera_local: Vector2 = (camera_world_origin + visible_world_size / 2.0 - world_rect.position) / mask_scale
	if required_size.x > window_size.x or required_size.y > window_size.y:
		# Only ever grows, never shrinks back down once zoomed back in —
		# keeps this simple (no texture-recreation churn from repeatedly
		# resizing up and down) at the cost of a bit of wasted GPU memory
		# after the one time she's near a boss/wide-zoom area. Still
		# bounded well below full-map size regardless.
		window_size = Vector2i(max(required_size.x, window_size.x), max(required_size.y, window_size.y))
		_window_image = Image.create(window_size.x, window_size.y, false, Image.FORMAT_LA8)
		_window_texture = ImageTexture.create_from_image(_window_image)
		_overlay_material.set_shader_parameter("window_tex", _window_texture)
		_recenter_window(Vector2i(camera_local) - window_size / 2)
		return
	_maybe_recenter_on(camera_local)

# Recenters the display window on this LOCAL (mask-pixel) position if it's
# within window_recenter_margin of the window's current edge. Cheap to
# call every frame — the check itself is just arithmetic; the recopy+
# reupload it can trigger is bounded by window_size, not map size.
func _maybe_recenter_on(local_pos: Vector2) -> void:
	var margin_px: float = window_recenter_margin / mask_scale
	var min_edge: Vector2 = Vector2(_window_origin) + Vector2(margin_px, margin_px)
	var max_edge: Vector2 = Vector2(_window_origin + window_size) - Vector2(margin_px, margin_px)
	if local_pos.x >= min_edge.x and local_pos.x <= max_edge.x \
			and local_pos.y >= min_edge.y and local_pos.y <= max_edge.y:
		return
	_recenter_window(Vector2i(local_pos) - window_size / 2)

func _recenter_window(new_origin: Vector2i) -> void:
	new_origin.x = clampi(new_origin.x, 0, max(0, _mask_size.x - window_size.x))
	new_origin.y = clampi(new_origin.y, 0, max(0, _mask_size.y - window_size.y))
	_window_origin = new_origin
	_sync_window()
	# Tells the shader where in world-space the window texture's data now
	# sits, so it can map any screen pixel's world position into the
	# window's UV space (see fog_overlay.gdshader) instead of relying on
	# this node being positioned/scaled to match, like the old sprite was.
	_overlay_material.set_shader_parameter("window_world_origin", world_rect.position + Vector2(_window_origin) * mask_scale)
	_overlay_material.set_shader_parameter("window_world_size", Vector2(window_size) * mask_scale)

# Copies the current window region out of the full-map record and
# re-uploads it — the only place the GPU texture actually gets touched,
# always at the fixed window_size regardless of world_rect's total size.
func _sync_window() -> void:
	_window_image.blit_rect(_full_image, Rect2i(_window_origin, window_size), Vector2i.ZERO)
	_window_texture.update(_window_image)

# ── Recursive shadowcasting ──────────────────────────────────────────────────
# Standard reference algorithm (the one popularized for roguelike FOV):
# 8 octants, each defined by a coordinate transform; within an octant, scan
# row by row outward from the origin, tracking a shrinking (start_slope,
# end_slope) range of currently-visible angles. A blocking cell narrows the
# range and spawns a recursive sub-scan for the arc just before it.
const _OCTANTS: Array = [
	[1, 0, 0, 1], [0, 1, 1, 0],
	[0, -1, 1, 0], [-1, 0, 0, 1],
	[-1, 0, 0, -1], [0, -1, -1, 0],
	[0, 1, -1, 0], [1, 0, 0, -1],
]

func _is_blocking_cell(cell: Vector2i) -> bool:
	if _terrain == null:
		return false
	var data := _terrain.get_cell_tile_data(0, cell)
	return data != null and data.get_collision_polygons_count(0) > 0

# Returns every grid cell visible from origin_cell within max_radius cells,
# as a Dictionary used purely as a set (Vector2i -> true).
func _visible_cells(origin_cell: Vector2i, max_radius: int) -> Dictionary:
	var visible: Dictionary = {origin_cell: true}
	for octant in _OCTANTS:
		_scan_octant(origin_cell, 1, 1.0, 0.0, max_radius, octant, visible)
	# The immediate ring around her is always visible regardless of what
	# the slope math decides — cells right next to the origin are exactly
	# where shadowcasting's slope comparisons are most prone to edge-case
	# misses (confirmed by testing: an isolated black square right next to
	# her with nothing actually blocking it).
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			visible[origin_cell + Vector2i(dx, dy)] = true
	return visible

func _scan_octant(origin: Vector2i, start_row: int, start_slope: float, end_slope: float,
		max_radius: int, xform: Array, visible: Dictionary) -> void:
	var xx: int = xform[0]
	var xy: int = xform[1]
	var yx: int = xform[2]
	var yy: int = xform[3]
	var radius_sq: int = max_radius * max_radius
	var current_start: float = start_slope
	for distance in range(start_row, max_radius + 1):
		var dy: int = -distance
		var blocked := false
		var new_start: float = current_start
		for dx in range(-distance, 1):
			var l_slope: float = (dx - 0.5) / (dy + 0.5)
			var r_slope: float = (dx + 0.5) / (dy - 0.5)
			if r_slope > current_start:
				continue
			if l_slope < end_slope:
				break
			var actual: Vector2i = origin + Vector2i(dx * xx + dy * xy, dx * yx + dy * yy)
			if dx * dx + dy * dy <= radius_sq:
				visible[actual] = true
			var cell_blocks: bool = _is_blocking_cell(actual)
			if blocked:
				if cell_blocks:
					new_start = r_slope
					continue
				else:
					blocked = false
					current_start = new_start
			else:
				if cell_blocks and distance < max_radius:
					blocked = true
					_scan_octant(origin, distance + 1, current_start, l_slope, max_radius, xform, visible)
					new_start = r_slope
		if blocked:
			break

func _erase_at(world_pos: Vector2) -> void:
	if _terrain == null:
		return
	var origin_cell: Vector2i = _terrain.local_to_map(_terrain.to_local(world_pos))
	var cell_size: Vector2 = Vector2(_terrain.tile_set.tile_size)
	var max_radius_cells: int = int(ceil(brush_radius / cell_size.x)) + 1
	var visible: Dictionary = _visible_cells(origin_cell, max_radius_cells)

	var center: Vector2 = (world_pos - world_rect.position) / mask_scale
	var radius_px: float = brush_radius / mask_scale
	var min_x := int(max(0, floor(center.x - radius_px)))
	var max_x := int(min(_mask_size.x - 1, ceil(center.x + radius_px)))
	var min_y := int(max(0, floor(center.y - radius_px)))
	var max_y := int(min(_mask_size.y - 1, ceil(center.y + radius_px)))
	var erased := false
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dist: float = Vector2(x, y).distance_to(center)
			if dist > radius_px:
				continue
			var pixel_world: Vector2 = world_rect.position + Vector2(x, y) * mask_scale
			# Bilinear blend across the 4 nearest cells instead of a hard
			# per-cell yes/no — visibility is computed per 16px tile, which
			# would otherwise show as a blocky cutoff at every tile
			# boundary; this fades smoothly across each boundary the same
			# way the brush's own outer edge already does.
			var frac_cell: Vector2 = _terrain.to_local(pixel_world) / cell_size
			var cell_floor := Vector2i(int(floor(frac_cell.x)), int(floor(frac_cell.y)))
			var t: Vector2 = frac_cell - Vector2(cell_floor)
			var v00: float = 1.0 if visible.has(cell_floor) else 0.0
			var v10: float = 1.0 if visible.has(cell_floor + Vector2i(1, 0)) else 0.0
			var v01: float = 1.0 if visible.has(cell_floor + Vector2i(0, 1)) else 0.0
			var v11: float = 1.0 if visible.has(cell_floor + Vector2i(1, 1)) else 0.0
			var visibility_factor: float = lerp(lerp(v00, v10, t.x), lerp(v01, v11, t.x), t.y)
			if visibility_factor <= 0.0:
				continue
			# smoothstep, not a straight linear ramp — eases in/out at the
			# brush edge instead of fading at a constant, slightly harsh
			# rate all the way from center to edge.
			var strength: float = smoothstep(0.0, 1.0, 1.0 - (dist / radius_px)) * visibility_factor
			var existing_alpha: float = _full_image.get_pixel(x, y).a
			var new_alpha: float = min(existing_alpha, 1.0 - strength)
			if new_alpha < existing_alpha:
				_full_image.set_pixel(x, y, Color(0.0, 0.0, 0.0, new_alpha))
				erased = true
	if not erased:
		return
	_mask_dirty = true
	# Only worth re-syncing the display if the erased area actually falls
	# within the current window — still correct without this check (the
	# next recenter would pick up the change anyway), just avoids a wasted
	# reupload for erasing that happened just outside what's on screen.
	var window_world := Rect2(
		world_rect.position + Vector2(_window_origin) * mask_scale,
		Vector2(window_size) * mask_scale)
	if window_world.intersects(Rect2(world_pos - Vector2.ONE * brush_radius, Vector2.ONE * brush_radius * 2.0)):
		_sync_window()

func _load_saved_mask() -> void:
	if GameData.fog_mask_png == "":
		return
	var loaded := Image.new()
	var bytes: PackedByteArray = Marshalls.base64_to_raw(GameData.fog_mask_png)
	# Only trusted if it matches this scene's own mask size — a save made
	# with a different world_rect/mask_scale (or in a different scene)
	# would otherwise erase at the wrong positions instead of failing safe.
	if loaded.load_png_from_buffer(bytes) == OK and loaded.get_size() == _mask_size:
		_full_image = loaded
