class_name CameraController
extends Camera2D

## Điều khiển Camera2D: pan + zoom cho cả touch (mobile) và chuột (PC/web).
## Gắn script này lên Camera2D. Không cần cấu hình thêm Input Map.

@export_group("Zoom")
@export var min_zoom_value: float = 0.25
@export var max_zoom_value: float = 4.0
@export var wheel_zoom_step: float = 0.12
@export var pinch_zoom_sensitivity: float = 1.0
@export var zoom_smooth_speed: float = 14.0
@export var zoom_at_cursor: bool = true

@export_group("Pan")
@export var pan_enabled: bool = true
@export var drag_button: MouseButton = MOUSE_BUTTON_LEFT

@export_group("Bounds (optional)")
@export var limit_bounds: bool = false
@export var bounds_rect: Rect2 = Rect2(-2000, -2000, 4000, 4000)

var _target_zoom: Vector2 = Vector2.ONE
var _touches: Dictionary = {} # index -> Vector2 screen pos
var _last_pinch_dist: float = 0.0
var _last_pinch_center: Vector2 = Vector2.ZERO
var _is_pinch: bool = false
var _is_dragging: bool = false


func _ready() -> void:
	_target_zoom = zoom
	# Đảm bảo camera là current khi scene bắt đầu.
	make_current()
	_clamp_target_zoom()


func _process(delta: float) -> void:
	if zoom_smooth_speed > 0.0:
		zoom = zoom.lerp(_target_zoom, clampf(delta * zoom_smooth_speed, 0.0, 1.0))
	else:
		zoom = _target_zoom
	if limit_bounds:
		_clamp_position_to_bounds()


func _unhandled_input(event: InputEvent) -> void:
	# Chuột: wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_add_zoom(1.0 + wheel_zoom_step, event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_add_zoom(1.0 / (1.0 + wheel_zoom_step), event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == drag_button:
			_is_dragging = event.pressed
		# Kết thúc phóng to bằng touch/magnify gesture (trackpad) - fallback
		if event is InputEventMagnifyGesture:
			_add_zoom(event.factor, event.position)
			return

	if event is InputEventMagnifyGesture:
		_add_zoom(event.factor, event.position)
		return

	# Touch: gom 2 ngón để pinch, 1 ngón để pan
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event)
		return

	# Chuột: kéo để pan (1 ngón tương đương)
	if event is InputEventMouseMotion and pan_enabled:
		if _is_dragging and _touches.is_empty():
			# Không đang pinch bằng touch thì mới pan bằng chuột
			var delta: Vector2 = event.relative
			# relative ở screen space -> chia cho zoom để ra world space, đảo chiều
			position -= delta / _target_zoom
			if limit_bounds:
				_clamp_position_to_bounds()
			get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
		_is_pinch = _touches.size() >= 2

	if _touches.size() == 2:
		_is_pinch = true
		var pts: Array = _touch_points()
		_last_pinch_dist = pts[0].distance_to(pts[1])
		_last_pinch_center = (pts[0] + pts[1]) * 0.5
	elif _touches.size() < 2:
		_last_pinch_dist = 0.0
		_is_pinch = false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position

	if _touches.size() >= 2 and pan_enabled:
		var pts: Array = _touch_points()
		var cur_dist: float = pts[0].distance_to(pts[1])
		var cur_center: Vector2 = (pts[0] + pts[1]) * 0.5

		if _last_pinch_dist > 0.0:
			var factor: float = cur_dist / _last_pinch_dist
			# Áp sensitivity: 1.0 = 1:1, >1 nhạy hơn
			if pinch_zoom_sensitivity != 1.0:
				factor = 1.0 + (factor - 1.0) * pinch_zoom_sensitivity
			_add_zoom(factor, cur_center)
			# Pan theo di chuyển của tâm pinch (hai ngón trượt cùng chiều)
			var center_delta: Vector2 = cur_center - _last_pinch_center
			if center_delta.length_squared() > 0.01:
				position -= center_delta / _target_zoom
				if limit_bounds:
					_clamp_position_to_bounds()

		_last_pinch_dist = cur_dist
		_last_pinch_center = cur_center
		get_viewport().set_input_as_handled()
	elif _touches.size() == 1 and pan_enabled:
		# 1 ngón: pan theo finger
		var delta: Vector2 = event.relative
		position -= delta / _target_zoom
		if limit_bounds:
			_clamp_position_to_bounds()
		get_viewport().set_input_as_handled()


func _touch_points() -> Array:
	var pts: Array = []
	for k in _touches.keys():
		pts.append(_touches[k])
	return pts


func _add_zoom(factor: float, screen_anchor: Vector2) -> void:
	if factor == 0.0:
		return
	var new_zoom: Vector2 = _target_zoom * factor
	new_zoom.x = clampf(new_zoom.x, min_zoom_value, max_zoom_value)
	new_zoom.y = clampf(new_zoom.y, min_zoom_value, max_zoom_value)

	if zoom_at_cursor:
		# Giữ điểm thế giới dưới con trỏ cố định khi đổi zoom.
		var vp_size: Vector2 = get_viewport_rect().size
		# Công thức: world = pos + (screen - vp/2) / zoom
		# => new_pos = old_pos + (screen - vp/2) * (1/old_zoom - 1/new_zoom)
		var screen_offset: Vector2 = screen_anchor - vp_size * 0.5
		# Tránh chia 0
		if _target_zoom.x != 0.0 and _target_zoom.y != 0.0 and new_zoom.x != 0.0 and new_zoom.y != 0.0:
			var diff: Vector2 = Vector2(
				screen_offset.x * (1.0 / _target_zoom.x - 1.0 / new_zoom.x),
				screen_offset.y * (1.0 / _target_zoom.y - 1.0 / new_zoom.y)
			)
			position += diff

	_target_zoom = new_zoom
	if limit_bounds:
		_clamp_position_to_bounds()


func _clamp_target_zoom() -> void:
	_target_zoom.x = clampf(_target_zoom.x, min_zoom_value, max_zoom_value)
	_target_zoom.y = clampf(_target_zoom.y, min_zoom_value, max_zoom_value)


func _clamp_position_to_bounds() -> void:
	position.x = clampf(position.x, bounds_rect.position.x, bounds_rect.position.x + bounds_rect.size.x)
	position.y = clampf(position.y, bounds_rect.position.y, bounds_rect.position.y + bounds_rect.size.y)
