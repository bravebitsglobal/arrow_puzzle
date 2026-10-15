shader_type canvas_item;

// Đổi màu vùng hồng của texture arrow sang target_color, giữ nguyên shading
// (sáng/tối, highlight) và các chi tiết khác màu: mắt đen/trắng, miệng/má đỏ.
// Gắn lên node Arrow, các con bật use_parent_material để dùng chung.

uniform vec4 target_color : source_color = vec4(1.0, 0.33, 0.73, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;

// Hue của hồng gốc (đo từ texture: ~0.90).
uniform float source_hue : hint_range(0.0, 1.0) = 0.9;
// Độ sáng (luma) trung bình của vùng hồng gốc: pixel bằng mức này ra đúng target_color,
// tối hơn -> target tối đi, sáng hơn -> pha dần về trắng.
uniform float reference_luma : hint_range(0.05, 0.95) = 0.72;
// Dải hue coi là "hồng": đổi hoàn toàn trong hue_inner, mờ dần tới hue_outer.
// Miệng/má (hue ~0.97-1.0) nằm ngoài hue_outer nên giữ nguyên.
uniform float hue_inner : hint_range(0.0, 0.5) = 0.045;
uniform float hue_outer : hint_range(0.0, 0.5) = 0.065;
// Pixel gần xám (mắt, viền trắng) không đổi.
uniform float min_saturation : hint_range(0.0, 1.0) = 0.12;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec4 col = COLOR;
	vec3 src = rgb2hsv(col.rgb);

	float dh = abs(src.x - source_hue);
	dh = min(dh, 1.0 - dh);
	float mask = 1.0 - smoothstep(hue_inner, hue_outer, dh);
	mask *= smoothstep(min_saturation, min_saturation + 0.1, src.y);

	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 recolored;
	if (luma <= reference_luma) {
		recolored = target_color.rgb * (luma / reference_luma);
	} else {
		recolored = mix(target_color.rgb, vec3(1.0), (luma - reference_luma) / (1.0 - reference_luma));
	}

	COLOR = vec4(mix(col.rgb, recolored, mask * strength), col.a);
}
