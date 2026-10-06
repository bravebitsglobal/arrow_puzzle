# Hướng dẫn sử dụng Joint Overlay Shader

## Mô tả
Shader này được dùng để vẽ đè hình ảnh lên các vị trí khớp của arrow, với khả năng xoay góc để phù hợp với các hướng khớp khác nhau.

## Cách sử dụng

### 1. Thêm Sprite2D vào scene
Thêm một `Sprite2D` node tại vị trí cần vẽ khớp

### 2. Áp dụng Material
- Load material: `res://arrow/joint_overlay_material.tres`
- Hoặc tạo ShaderMaterial mới với shader: `res://arrow/joint_overlay.gdshader`

### 3. Thiết lập góc xoay cho các hướng khớp khác nhau

Shader hỗ trợ xoay để phù hợp với 4 hướng khớp chữ L:

```gdscript
# Khớp hướng L (góc trái dưới) - 0 độ
material.set_shader_parameter("rotation_angle", 0.0)

# Khớp hướng ⌐ (góc phải dưới) - 90 độ
material.set_shader_parameter("rotation_angle", PI / 2.0)  # 1.5708

# Khớp hướng Γ (góc phải trên) - 180 độ
material.set_shader_parameter("rotation_angle", PI)  # 3.14159

# Khớp hướng ⌞ (góc trái trên) - 270 độ
material.set_shader_parameter("rotation_angle", 3.0 * PI / 2.0)  # 4.71239
```

### 4. Điều chỉnh scale và offset (tùy chọn)

```gdscript
# Scale texture
material.set_shader_parameter("texture_scale", Vector2(1.5, 1.5))

# Offset texture
material.set_shader_parameter("texture_offset", Vector2(0.1, 0.1))
```

## Ví dụ code

```gdscript
extends Sprite2D

func _ready():
    # Load material
    var joint_material = load("res://arrow/joint_overlay_material.tres").duplicate()
    material = joint_material
    
    # Thiết lập góc xoay cho khớp hướng L
    material.set_shader_parameter("rotation_angle", 0.0)
    
    # Đặt vị trí
    position = Vector2(175, 40)  # Vị trí khớp
```

## Tham số Shader

- `alpha_texture`: Texture hình ảnh chính (alpha.png)
- `mask_texture`: Texture mask để xóa phần thừa (mask.png)
- `rotation_angle`: Góc xoay (radian, 0.0 - 6.28318)
- `texture_scale`: Tỷ lệ scale của texture (Vector2)
- `texture_offset`: Offset của texture (Vector2)
