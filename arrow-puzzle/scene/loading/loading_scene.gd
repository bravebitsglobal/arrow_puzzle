extends CanvasLayer
class_name LoadingScene
@onready var texture_progress_bar: TextureProgressBar = $Panel/TextureProgressBar
const LOADING_TIME: float = 0.5
@onready var label: Label = $Panel/TextureProgressBar/Label

func _ready() -> void:
	var tween = create_tween()
	tween.tween_property(texture_progress_bar, "value", 100, LOADING_TIME)
	texture_progress_bar.value_changed.connect(func (value: float):
		label.text = str(value) + "%")
	# Tween chạy song song với chuỗi API; chỉ chuyển scene khi cả hai xong và API thành công.
	if not await load_data():
		OS.alert("Không có kết nối mạng. Vui lòng kiểm tra lại và mở lại game.", "Mất kết nối")
		return
	if tween.is_running():
		await tween.finished
	get_tree().change_scene_to_file("res://scene/home/home.tscn")

# get_profile cần access token từ authen nên phải gọi sau authen.
func load_data() -> bool:
	var authen_res = await authen()
	if not authen_res.ok:
		return false
	var profile_res = await Global.api.get_profile()
	if not profile_res.ok or not profile_res.data is Dictionary:
		print("get profile failed: ", profile_res.code, " ", profile_res.error)
		return false
	var profile = profile_res.data.data
	profile.user_id = authen_res.data.user.id
	return true

# Đăng nhập GameHub bằng device id + country của thiết bị.
func authen() -> Dictionary:
	var res = await Global.api.device_register(get_device_id(), get_country())
	if not res.ok:
		print("authen failed: ", res.code, " ", res.error)
	return res

func get_device_id() -> String:
	var device_id = OS.get_unique_id()
	if device_id.is_empty():
		# Web/một số nền tảng không có unique id → sinh 1 lần rồi lưu lại.
		var player_data = Global.game_data.player_data
		if player_data.device_id.is_empty():
			player_data.device_id = "%d%d" % [Time.get_unix_time_from_system(), randi()]
			player_data.save()
		device_id = player_data.device_id
	return device_id

# Locale dạng "vi_VN" / "sr_Latn_RS" → mã vùng ở cuối ("VN", "RS"). Không có mã vùng thì trả rỗng.
func get_country() -> String:
	var parts = OS.get_locale().split("_")
	var region = parts[parts.size() - 1]
	return region.to_upper() if parts.size() > 1 and region.length() == 2 else ""
