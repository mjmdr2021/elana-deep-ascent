shader_type canvas_item;

// Small, fixed-size window texture (see fog_of_war.gd's sliding-window
// system) — kept small on purpose so uploading it stays cheap regardless
// of total map size. Sampled here using a world-space lookup instead of
// being displayed at its own native size/position, which is what let gaps
// appear at the screen edges when the camera showed more than the window
// itself covered.
uniform sampler2D window_tex : filter_linear;
// World-space rect the window texture currently covers.
uniform vec2 window_world_origin;
uniform vec2 window_world_size;
// The active camera's current world-space visible rect — recomputed by
// script every frame from its position/zoom/viewport size, so this always
// matches whatever's actually on screen, at any zoom level.
uniform vec2 camera_world_origin;
uniform vec2 camera_world_size;

// Elana's own current world position — a small area around her is forced
// toward fully transparent here, bypassing the window texture entirely.
// Without this, the mask's own erase brush (see fog_of_war.gd's
// _erase_at()) has a soft falloff at its edge, on purpose, for how the
// brush blends into unexplored space — but that same falloff means her own
// sprite could visibly dim right as she steps toward a new area, before
// the brush catches up. This cutout is independent of mask/brush timing
// entirely, so she's never dimmed by her own fog no matter what.
uniform vec2 elana_world_pos;
uniform float elana_reveal_radius;
// World px over which the cutout eases into the normal window sampling —
// a hard binary circle (distance <= radius) read as a sharp, obviously
// artificial ring around her; this blends it out gradually instead.
uniform float elana_reveal_softness;

void fragment() {
	// This quad always covers the full screen (anchored full-rect, same as
	// BootCover) — UV (0..1 across it) maps directly to the camera's
	// current visible world-space rect, not to the window's own bounds.
	vec2 world_pos = camera_world_origin + UV * camera_world_size;

	vec2 window_uv = (world_pos - window_world_origin) / window_world_size;
	vec4 window_color;
	// Outside the window's currently-loaded data — always opaque black,
	// never sampled/transparent. This is the actual fix: a screen area
	// the window hasn't caught up to yet fails toward "hidden" (safe),
	// never toward "revealed" (the bug we were chasing), because
	// there's no code path here that can show anything except
	// explicitly-sampled window data or this fallback black.
	if (window_uv.x < 0.0 || window_uv.x > 1.0 || window_uv.y < 0.0 || window_uv.y > 1.0) {
		window_color = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		window_color = texture(window_tex, window_uv);
	}

	// 1.0 right on top of her fading down to 0.0 by reveal_radius — mixed
	// against the normal window_color instead of switched between with an
	// if, so the cutout's own edge is as soft as its softness value, not a
	// binary ring.
	float dist_to_elana = distance(world_pos, elana_world_pos);
	float reveal_factor = 1.0 - smoothstep(elana_reveal_radius - elana_reveal_softness, elana_reveal_radius, dist_to_elana);
	COLOR = mix(window_color, vec4(0.0, 0.0, 0.0, 0.0), reveal_factor);
}
