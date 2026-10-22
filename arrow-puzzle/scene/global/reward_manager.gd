extends Control
class_name RewardManager
var first_open_home: bool = true
var first_time_app: bool = false
var is_show_daily_reward: bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.game_event.scene_changed.connect(func (scene):
		match scene:
			GameEnum.SceneName.Home:
				check_open_daily_reward()
		)
func check_open_daily_reward()->void:
	var last_checkin = Global.game_data.player_data.last_checkin
	var date_dict = Time.get_date_dict_from_system()
	if !last_checkin.size():
		first_time_app = true
		Global.game_data.player_data.daily_count = 1
	else:
		if (last_checkin[0] != date_dict['year'] || 
			last_checkin[1] != date_dict['month'] ||
			last_checkin[2] != date_dict['day']):
				Global.game_data.player_data.daily_count = clampi(Global.game_data.player_data.daily_count + 1, 0, 7)
		else:
			is_show_daily_reward = true
	Global.game_data.player_data.last_checkin = [
		int(date_dict['year']),
		int(date_dict['month']),
		int(date_dict['day'])]
	Global.game_data.player_data.save()
	if not first_time_app and not is_show_daily_reward:
		is_show_daily_reward = true
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.DailyReward, true)
# rewards: [{ "reward_type": GameEnum.RewardType, "quantity": int }, ...]
func claim_reward(rewards: Array) -> void:
	var game_data = Global.game_data
	for reward in rewards:
		var quantity: int = reward["quantity"]
		match reward["reward_type"]:
			GameEnum.RewardType.Coin:
				game_data.coins.value += quantity
			GameEnum.RewardType.Hint:
				game_data.booster_hint.value += quantity
			GameEnum.RewardType.Eraser:
				game_data.booster_eraser.value += quantity
			GameEnum.RewardType.MagicGlasses:
				game_data.booster_magic_glasses.value += quantity
			GameEnum.RewardType.Ruler:
				game_data.booster_ruler.value += quantity
	game_data.save_data()
