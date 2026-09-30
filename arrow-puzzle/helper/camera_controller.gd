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
# Sau khi pinch, khóa pan 1 ngón cho tới khi nhấc hết tay (tránh giật khi nhấc ngón lệch nhau)
var _pinch_lock: bool = false
# Điểm màn hình giữ cố định khi zoom (áp dụng dần trong _process theo zoom thực tế)
var _zoom_anchor: Vector2 = Vector2.ZERO


func _ready() -> void:
	_target_zoom = zoom
	# Đảm bảo camera là current khi scene bắt đầu.
	make_current()
	_clamp_target_zoom()


func _process(delta: float) -> void:
	var old_zoom: Vector2 = zoom
	if zoom_smooth_speed > 0.0 and not _is_pinch:
		zoom = zoom.lerp(_target_zoom, clampf(delta * zoom_smooth_speed, 0.0, 1.0))
	else:
		# Pinch: bám tay 1:1, không làm mượt để không trôi sau khi nhả
		zoom = _target_zoom
	if old_zoom != zoom:
		_apply_anchor_compensation(old_zoom, zoom)
	if limit_bounds:
		_clamp_position_to_bounds()


func _unhandled_input(event: InputEvent) -> void:
	# Bỏ qua sự kiện chuột giả lập từ touch, touch đã được xử lý riêng
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
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
			position -= delta / zoom
			if limit_bounds:
				_clamp_position_to_bounds()
			get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)

	if _touches.size() >= 2:
		_is_pinch = true
		_pinch_lock = true
		var pts: Array = _touch_points()
		_last_pinch_dist = pts[0].distance_to(pts[1])
		_last_pinch_center = (pts[0] + pts[1]) * 0.5
	else:
		_last_pinch_dist = 0.0
		_is_pinch = false
		if _touches.is_empty():
			_pinch_lock = false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position

	if _touches.size() >= 2:
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
			if pan_enabled and center_delta.length_squared() > 0.01:
				position -= center_delta / zoom
				if limit_bounds:
					_clamp_position_to_bounds()

		_last_pinch_dist = cur_dist
		_last_pinch_center = cur_center
		get_viewport().set_input_as_handled()
	elif _touches.size() == 1 and pan_enabled and not _pinch_lock:
		# 1 ngón: pan theo finger
		var delta: Vector2 = event.relative
		position -= delta / zoom
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
	_target_zoom = new_zoom
	_zoom_anchor = screen_anchor

	if _is_pinch or zoom_smooth_speed <= 0.0:
		# Áp ngay để camera bám tay; bù vị trí theo zoom thực tế
		var old_zoom: Vector2 = zoom
		zoom = _target_zoom
		_apply_anchor_compensation(old_zoom, zoom)
		if limit_bounds:
			_clamp_position_to_bounds()


## Giữ điểm thế giới dưới _zoom_anchor cố định khi zoom thực tế đổi từ old_zoom -> new_zoom.
## world = pos + (screen - vp/2) / zoom  =>  pos += (screen - vp/2) * (1/old - 1/new)
func _apply_anchor_compensation(old_zoom: Vector2, new_zoom: Vector2) -> void:
	if not zoom_at_cursor:
		return
	if old_zoom.x == 0.0 or old_zoom.y == 0.0 or new_zoom.x == 0.0 or new_zoom.y == 0.0:
		return
	var screen_offset: Vector2 = _zoom_anchor - get_viewport_rect().size * 0.5
	position += Vector2(
		screen_offset.x * (1.0 / old_zoom.x - 1.0 / new_zoom.x),
		screen_offset.y * (1.0 / old_zoom.y - 1.0 / new_zoom.y)
	)


func _clamp_target_zoom() -> void:
	_target_zoom.x = clampf(_target_zoom.x, min_zoom_value, max_zoom_value)
	_target_zoom.y = clampf(_target_zoom.y, min_zoom_value, max_zoom_value)


func _clamp_position_to_bounds() -> void:
	position.x = clampf(position.x, bounds_rect.position.x, bounds_rect.position.x + bounds_rect.size.x)
	position.y = clampf(position.y, bounds_rect.position.y, bounds_rect.position.y + bounds_rect.size.y)
