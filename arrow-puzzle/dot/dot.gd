extends Sprite2D
class_name Dot
## Hieu ung vet: dot sang len + to ra roi tro ve trang thai cu.
const PULSE_SCALE: float = 1.8
const PULSE_IN_TIME: float = 0.08
const PULSE_OUT_TIME: float = 0.45
var base_modulate: Color
var base_scale: Vector2
var pulse_tween: Tween
# Da bat dau an (luc thang) thi khong cho pulse ghi de nua
var is_dissolving: bool = false
func _ready() -> void:
	base_modulate = self_modulate
	base_scale = scale
func pulse(color: Color) -> void:
	if is_dissolving:
		return
	if pulse_tween:
		pulse_tween.kill()
	var glow := color.lightened(0.3)
	glow.a = 1
	pulse_tween = create_tween()
	pulse_tween.tween_property(self, 'self_modulate', glow, PULSE_IN_TIME)
	pulse_tween.parallel().tween_property(self, 'scale', base_scale * PULSE_SCALE, PULSE_IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(self, 'self_modulate', base_modulate, PULSE_OUT_TIME)
	pulse_tween.parallel().tween_property(self, 'scale', base_scale, PULSE_OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
const DISSOLVE_TIME: float = 0.5
## An dot: co nho lai, phinh to + sang len, roi mo dan. delay de tao hieu ung lan toa.
func dissolve(delay: float) -> void:
	is_dissolving = true
	if pulse_tween:
		pulse_tween.kill()
	var glow := Color(1, 1, 1, 1)
	var faded := glow
	faded.a = 0
	pulse_tween = create_tween()
	pulse_tween.tween_interval(delay)
	pulse_tween.tween_property(self, 'scale', base_scale * 0.5, DISSOLVE_TIME * 0.2).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(self, 'scale', base_scale * 2.2, DISSOLVE_TIME * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tween.parallel().tween_property(self, 'self_modulate', glow, DISSOLVE_TIME * 0.35)
	pulse_tween.tween_property(self, 'self_modulate', faded, DISSOLVE_TIME * 0.45)
	pulse_tween.parallel().tween_property(self, 'scale', base_scale * 2.6, DISSOLVE_TIME * 0.45)
	pulse_tween.tween_callback(hide)
