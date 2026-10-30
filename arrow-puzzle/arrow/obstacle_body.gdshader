shader_type canvas_item;

// Thân arrow obstacle: pattern xám (frozen/bomb/crate) tô 2 tông theo màu arrow.
// Vùng đen của pattern -> target_color tối, vùng trắng -> target_color sáng.

uniform vec4 target_color : source_color = vec4(1.0, 0.33, 0.73, 1.0);
uniform sampler2D pattern : repeat_enable, filter_linear_mipmap;
// Số ô pattern trên mỗi độ rộng thân (nhỏ hơn -> pattern to hơn).
uniform float pattern_scale = 0.5;
uniform float dark = 0.55;
uniform float light = 0.3;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	float p = texture(pattern, UV * pattern_scale).r;
	vec3 c = mix(target_color.rgb * dark, mix(target_color.rgb, vec3(1.0), light), p);
	COLOR = vec4(c, 1.0) * modulate;
}
