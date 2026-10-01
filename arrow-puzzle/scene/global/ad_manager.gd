extends Control
class_name AdManager

## Phát khi load reward ad xong (success = true) hoặc lỗi (false).
signal reward_ad_loaded(success: bool)
## Phát khi kết thúc 1 lần show reward ad: rewarded = true nếu user đủ điều kiện nhận thưởng.
signal reward_ad_completed(rewarded: bool)

@export var reward_unit_id_android: String = "ca-app-pub-3940256099942544/5224354917"
@export var reward_unit_id_ios: String = "ca-app-pub-3940256099942544/1712485313"

var _rewarded_ad: RewardedAd
var _is_loading := false
var _is_showing := false
var _user_earned_reward := false

var _reward_listener := OnUserEarnedRewardListener.new()
var _load_callback := RewardedAdLoadCallback.new()
var _content_callback := FullScreenContentCallback.new()


func _ready() -> void:
	if not _is_supported():
		return
	MobileAds.initialize()

	_reward_listener.on_user_earned_reward = _on_user_earned_reward
	_load_callback.on_ad_loaded = _on_ad_loaded
	_load_callback.on_ad_failed_to_load = _on_ad_failed_to_load
	_content_callback.on_ad_dismissed_full_screen_content = _on_ad_dismissed
	_content_callback.on_ad_failed_to_show_full_screen_content = _on_ad_failed_to_show


func is_reward_ad_loaded() -> bool:
	return _rewarded_ad != null


## Load trước reward ad (chưa show). Trả về signal reward_ad_loaded(success).
## Dùng: var ok: bool = await ad_manager.load_reward_ad()
func load_reward_ad() -> Signal:
	if not _is_supported():
		reward_ad_loaded.emit.call_deferred(false)
	elif _rewarded_ad:
		reward_ad_loaded.emit.call_deferred(true)
	elif not _is_loading:
		_is_loading = true
		RewardedAdLoader.new().load(_get_unit_id(), AdRequest.new(), _load_callback)
	return reward_ad_loaded


## Show reward ad đã load trước đó. Trả về signal reward_ad_completed(rewarded).
## Chưa load xong → rewarded = false.
## Dùng: var rewarded: bool = await ad_manager.show_reward_ad()
func show_reward_ad() -> Signal:
	if _is_showing:
		return reward_ad_completed
	if not _rewarded_ad:
		_log("Reward ad chưa được load")
		reward_ad_completed.emit.call_deferred(false)
		return reward_ad_completed
	_is_showing = true
	_user_earned_reward = false
	_rewarded_ad.show_reward_ads(_reward_listener)
	return reward_ad_completed


## Load (nếu chưa có) rồi show reward ad. Trả về signal reward_ad_completed(rewarded).
## Dùng: var rewarded: bool = await ad_manager.show_user_reward()
func show_user_reward() -> Signal:
	_load_and_show()
	return reward_ad_completed


func _load_and_show() -> void:
	if _is_showing:
		return
	var loaded: bool = await load_reward_ad()
	if not loaded:
		reward_ad_completed.emit(false)
		return
	show_reward_ad()


#region Callbacks
func _on_ad_loaded(ad: RewardedAd) -> void:
	_is_loading = false
	ad.full_screen_content_callback = _content_callback
	_rewarded_ad = ad
	_log("Reward ad loaded")
	reward_ad_loaded.emit(true)


func _on_ad_failed_to_load(error: LoadAdError) -> void:
	_is_loading = false
	_log("Load reward ad lỗi: " + error.message)
	reward_ad_loaded.emit(false)


func _on_user_earned_reward(item: RewardedItem) -> void:
	_user_earned_reward = true
	_log("User earned reward: %d %s" % [item.amount, item.type])


func _on_ad_dismissed() -> void:
	# Deferred: phòng trường hợp callback earned reward tới sau dismissed.
	_finish_show.call_deferred()


func _on_ad_failed_to_show(error: AdError) -> void:
	_log("Show reward ad lỗi: " + error.message)
	_user_earned_reward = false
	_finish_show()


#endregion


func _finish_show() -> void:
	_destroy_ad()
	_is_showing = false
	reward_ad_completed.emit(_user_earned_reward)


func _destroy_ad() -> void:
	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null


func _get_unit_id() -> String:
	return reward_unit_id_ios if OS.get_name() == "iOS" else reward_unit_id_android


func _is_supported() -> bool:
	return true


func _log(message: String) -> void:
	print("[AdManager] " + message)
