shader_type canvas_item;

// Shader gắn trực tiếp lên Line2D thân arrow. Tại mỗi khớp gấp khúc:
// - mask_texture: xoá phần thân nằm ngoài mask (vùng trong suốt của mask.png).
// - alpha_texture: vẽ đè viền pixel (alpha.png) lên khớp.
// Hướng gốc của 2 ảnh: 2 nhánh thân đi LÊN và sang PHẢI, góc ngoài ở dưới-trái.

const int MAX_JOINTS = 64;

uniform sampler2D alpha_texture : filter_nearest;
uniform sampler2D mask_texture : filter_nearest;
// xy = vị trí khớp (toạ độ local của Line2D), z = góc xoay (radian) so với hướng gốc.
uniform vec3 joints[MAX_JOINTS];
uniform int joint_count = 0;
// Cạnh ô vuông khớp (px) = độ rộng Line2D.
uniform float joint_size = 40.0;
uniform float overlay_strength : hint_range(0.0, 1.0) = 1.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	for (int i = 0; i < joint_count; i++) {
		vec2 d = local_pos - joints[i].xy;
		float half_size = joint_size * 0.5;
		if (abs(d.x) > half_size || abs(d.y) > half_size) {
			continue;
		}
		// Đưa điểm về hệ toạ độ gốc của ảnh: xoay ngược góc của khớp.
		float c = cos(joints[i].z);
		float s = sin(joints[i].z);
		vec2 base = vec2(d.x * c + d.y * s, -d.x * s + d.y * c);
		vec2 uv = clamp(base / joint_size + 0.5, 0.0, 1.0);

		color.a *= texture(mask_texture, uv).a;
		vec4 overlay = texture(alpha_texture, uv);
		color.rgb = mix(color.rgb, overlay.rgb, overlay.a * overlay_strength);
		break;
	}
	COLOR = color;
}
