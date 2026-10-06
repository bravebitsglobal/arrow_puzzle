shader_type canvas_item;

// Texture của hình ảnh alpha (hình ảnh chính)
uniform sampler2D alpha_texture : filter_linear_mipmap, repeat_enable;

// Texture của mask (để xóa phần thừa)
uniform sampler2D mask_texture : filter_linear_mipmap, repeat_enable;

// Góc xoay (radian) để phù hợp với các hướng khớp khác nhau
uniform float rotation_angle : hint_range(0.0, 6.28318530718) = 0.0;

// Tỷ lệ scale của texture
uniform vec2 texture_scale = vec2(1.0, 1.0);

// Offset của texture
uniform vec2 texture_offset = vec2(0.0, 0.0);

// Hàm xoay UV coordinates
vec2 rotate_uv(vec2 uv, float angle, vec2 center) {
    // Dịch chuyển về tâm
    vec2 translated = uv - center;

    // Xoay
    float cos_angle = cos(angle);
    float sin_angle = sin(angle);
    vec2 rotated = vec2(
        translated.x * cos_angle - translated.y * sin_angle,
        translated.x * sin_angle + translated.y * cos_angle
    );

    // Dịch chuyển về vị trí ban đầu
    return rotated + center;
}

void fragment() {
    // Tính UV sau khi scale và offset
    vec2 uv = UV * texture_scale + texture_offset;

    // Xoay UV quanh tâm (0.5, 0.5)
    vec2 rotated_uv = rotate_uv(uv, rotation_angle, vec2(0.5, 0.5));

    // Lấy màu từ alpha texture
    vec4 alpha_color = texture(alpha_texture, rotated_uv);

    // Lấy mask value (sử dụng kênh alpha hoặc luminance của mask)
    vec4 mask_color = texture(mask_texture, rotated_uv);

    // Tính mask value: nếu mask có màu (không phải đen) thì giữ lại
    // Sử dụng luminance hoặc alpha channel của mask
    float mask_value = max(mask_color.a, (mask_color.r + mask_color.g + mask_color.b) / 3.0);

    // Apply mask: chỉ hiển thị phần có mask
    COLOR = alpha_color;
    COLOR.a *= mask_value;
}
