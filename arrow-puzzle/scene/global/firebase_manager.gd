extends Control
class_name FirebaseManager
## Gửi event tới Firebase Analytics qua plugin Godotx Firebase (Android).
## Cấu hình lấy từ res://google-services.json (export option firebase/android_config_file).
## Trên editor/web/desktop không có plugin → chỉ print ra console.
##
## Dùng qua Global.firebase_manager:
##   Global.firebase_manager.log_event("level_start", {"level": 5})
##   Global.firebase_manager.log_level_end(5, true)
## Tên event/param: tối đa 40 ký tự, chỉ chữ/số/_, bắt đầu bằng chữ. Giá trị: String/int/float/bool.

const CORE_SINGLETON := "GodotxFirebaseCore"
const ANALYTICS_SINGLETON := "GodotxFirebaseAnalytics"
const MAX_NAME_LENGTH: int = 40
const MAX_STRING_VALUE_LENGTH: int = 100

var core: Object
var analytics: Object
var is_ready: bool = false
# Event gọi trước khi analytics khởi tạo xong → giữ lại, gửi khi ready.
var pending_events: Array[Dictionary] = []


func _ready() -> void:
	if not Engine.has_singleton(CORE_SINGLETON) or not Engine.has_singleton(ANALYTICS_SINGLETON):
		print("[Firebase] plugin not available on this platform, events are only printed")
		return
	core = Engine.get_singleton(CORE_SINGLETON)
	analytics = Engine.get_singleton(ANALYTICS_SINGLETON)
	core.core_initialized.connect(_on_core_initialized)
	core.core_error.connect(func(msg: String): print("[Firebase] core error: ", msg))
	analytics.analytics_initialized.connect(_on_analytics_initialized)
	analytics.analytics_error.connect(func(msg: String): print("[Firebase] analytics error: ", msg))
	core.initialize()
	hooks()
func hooks()->void:
	Global.game_event.active_game_booster.connect(func (booster: GameEnum.Booster):
		log_event("booster_use_%d" % [booster])
		)
func _on_core_initialized(success: bool) -> void:
	if success:
		analytics.initialize()

func _on_analytics_initialized(success: bool) -> void:
	if not success:
		return
	# Export option privacy_safe_defaults tắt thu thập mặc định → bật lại khi khởi động.
	analytics.set_analytics_collection_enabled(true)
	# Plugin chỉ nhận chuỗi "granted"/"denied".
	analytics.set_consent({
		"analytics_storage": "granted",
		"ad_storage": "granted",
		"ad_user_data": "granted",
		"ad_personalization": "granted",
	})
	is_ready = true
	for event in pending_events:
		analytics.log_event(event.name, event.params)
	pending_events.clear()

## Gửi 1 event bất kỳ.
func log_event(event_name: String, params: Dictionary = {}) -> void:
	var clean_name := _sanitize_name(event_name)
	var clean_params := _sanitize_params(params)
	if Global.development:
		print("[Firebase] event ", clean_name, " ", clean_params)
	if analytics == null:
		return
	if not is_ready:
		pending_events.append({"name": clean_name, "params": clean_params})
		return
	analytics.log_event(clean_name, clean_params)

# ----------------------------------------------------------------
# Event có sẵn của game
# ----------------------------------------------------------------

func log_screen_view(screen_name: String) -> void:
	log_event("screen_view", {"screen_name": screen_name, "screen_class": screen_name})

func log_level_start(level: int) -> void:
	log_event("level_start", {"level": level})

func log_level_end(level: int, success: bool) -> void:
	log_event("level_end", {"level": level, "success": success})

func log_challenge_start(date: String) -> void:
	log_event("challenge_start", {"date": date})

func log_ad_impression(ad_type: String, placement: String) -> void:
	log_event("ad_impression_custom", {"ad_type": ad_type, "placement": placement})

func log_earn_currency(currency: String, value: int, source: String) -> void:
	log_event("earn_virtual_currency", {"virtual_currency_name": currency, "value": value, "source": source})

func log_spend_currency(currency: String, value: int, item_name: String) -> void:
	log_event("spend_virtual_currency", {"virtual_currency_name": currency, "value": value, "item_name": item_name})

## Ghi log lỗi/thông tin dạng event (Analytics không có API log text riêng).
func log_message(message: String, level: String = "info") -> void:
	log_event("app_log", {"level": level, "message": message})

# ----------------------------------------------------------------
# Chuẩn hoá theo giới hạn của Firebase Analytics
# ----------------------------------------------------------------

func _sanitize_name(value: String) -> String:
	var regex := RegEx.create_from_string("[^A-Za-z0-9_]")
	var clean := regex.sub(value.strip_edges(), "_", true)
	# Firebase yêu cầu tên bắt đầu bằng chữ cái.
	if clean.is_empty() or not (clean.unicode_at(0) in range(65, 91) or clean.unicode_at(0) in range(97, 123)):
		clean = "e_" + clean
	return clean.left(MAX_NAME_LENGTH)

func _sanitize_params(params: Dictionary) -> Dictionary:
	var result := {}
	for key in params:
		var value = params[key]
		match typeof(value):
			TYPE_INT, TYPE_FLOAT:
				pass
			TYPE_BOOL:
				value = 1 if value else 0
			_:
				value = str(value).left(MAX_STRING_VALUE_LENGTH)
		result[_sanitize_name(str(key))] = value
	return result
