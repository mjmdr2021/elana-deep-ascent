shader_type canvas_item;

// Hollowscale ward outline — traces the sprite's silhouette while charged
uniform vec4 outline_color : source_color = vec4(0.75, 0.55, 0.25, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 1.0;
uniform bool enabled = false;

// Hit flash — mixes toward flash_color regardless of the underlying pixel,
// a true overlay (unlike modulate's multiply, which can't redden black pixels)
uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

// Story-glow outline — same silhouette trace as the Hollowscale ward above,
// but driven by a continuous alpha (pulsed from script) instead of a hard
// on/off toggle, so it can fade in and out. Independent uniforms so a story
// beat and Hollowscale readiness never fight over the same outline.
uniform vec4 glow_outline_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float glow_outline_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	if (col.a < 0.5 && (enabled || glow_outline_alpha > 0.0)) {
		vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
		float hit = 0.0;
		hit += texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
		hit += texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
		hit += texture(TEXTURE, UV + vec2(0.0, size.y)).a;
		hit += texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
		hit += texture(TEXTURE, UV + vec2(size.x, size.y)).a;
		hit += texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
		hit += texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
		hit += texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
		if (hit > 0.0) {
			if (enabled) {
				col = outline_color;
			} else {
				col = vec4(glow_outline_color.rgb, glow_outline_alpha);
			}
		}
	}

	if (flash_amount > 0.0 && col.a > 0.0) {
		col.rgb = mix(col.rgb, flash_color.rgb, flash_amount);
	}

	COLOR = col;
}
