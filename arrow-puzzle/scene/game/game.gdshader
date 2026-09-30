shader_type canvas_item;

// Tham số làm mờ màn hình phía sau (screen texture)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float lod : hint_range(0.0, 5.0) = 100; // Độ mờ blur
uniform vec4 color_tint : source_color = vec4(0.0, 0.0, 0.0, 0.8); // Màu phủ nhẹ + độ trong suốt

void fragment() {
    // Lấy ảnh của màn hình phía sau và áp dụng mipmap để làm mờ
    vec4 color = textureLod(screen_texture, SCREEN_UV, lod);
    // Trộn với màu tối nhạt
    COLOR = mix(color, color_tint, color_tint.a);
}