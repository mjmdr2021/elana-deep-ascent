shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.75, 0.55, 0.25, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 1.0;
uniform bool enabled = false;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (enabled && col.a < 0.5) {
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
			col = outline_color;
		}
	}
	COLOR = col;
}
