extends Control
class_name PopupDailyReward
@onready var reward_container: HBoxContainer = $TextureRect/Reward/RewardContainer
@onready var day_container: Control = $TextureRect/DayContainer
@export var reward_item_scene: PackedScene
@onready var button_claim: Button = $TextureRect/ButtonClaim
@onready var button_close: TextureButton = $TextureRect/ButtonClose

var day_selected: int = -1
func _ready() -> void:
	button_close.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.DailyReward, false)
		)
	for i in range(7):
		var day: DailyDay = day_container.get_child(i)
		day.pressed.connect(func ():
			_on_day_clicked(i))
	button_claim.pressed.connect(_on_button_claim_pressed)
	render_ui()
func render_ui()->void:
	var daily_count = Global.game_data.player_data.daily_count
	var daily_received = Global.game_data.player_data.daily_received
	for i in range(7):
		var day: DailyDay = day_container.get_child(i)
		if daily_received.has(i):
			day.set_state('claimed')
		else:
			if i < daily_count:
				day.set_state('unclaim')
			else:
				day.set_state('locked')
func _on_button_claim_pressed()->void:
	var can_claim = (day_selected < Global.game_data.player_data.daily_count &&
						not Global.game_data.player_data.daily_received.has(day_selected))
	if not can_claim:
		return
	Global.reward_manager.claim_reward(GameEnum.DAILY_REWARDS[day_selected])
	Global.game_data.player_data.daily_received.append(day_selected)
	if Global.game_data.player_data.daily_received.size()==7:
		Global.game_data.player_data.daily_received = []
		Global.game_data.player_data.daily_count = 0
	Global.game_data.player_data.save()
	render_ui()
func _on_day_clicked(idx: int)->void:
	if idx == day_selected:
		return
	if day_selected > -1:
		day_container.get_child(day_selected).set_select(false)
	day_container.get_child(idx).set_select(true)
	day_selected = idx
	var rewards = GameEnum.DAILY_REWARDS[idx]
	for i in reward_container.get_children():
		i.queue_free()
	for r in rewards:
		var item: Reward = reward_item_scene.instantiate()
		item.set_data.call_deferred(r)
		reward_container.add_child(item)
	var can_claim = (idx < Global.game_data.player_data.daily_count &&
						not Global.game_data.player_data.daily_received.has(idx))
	button_claim.visible = can_claim
