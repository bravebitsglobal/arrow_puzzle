extends PanelBase
class_name PanelWin
@onready var button_claim: TextureButton = $HBoxContainer/ButtonClaim
@onready var button_claimx_2: TextureButton = $HBoxContainer/ButtonClaimx2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	panel_name = 'panel_game_win'
	button_claim.pressed.connect(_on_button_claim_pressed)
	button_claimx_2.pressed.connect(_on_claim_x2_pressed)
func _on_button_claim_pressed()->void:
	Global.game_event.game_next_level.emit()
	Global.game_data.level.value = Global.game_data.level.value + 1
	Global.game_data.coins.value = Global.game_data.coins.value + Global.COINS_PER_LEVEL
	Global.game_data.save_data()
	Global.game_event.request_visible_game_panel.emit(panel_name, false)
		
func _on_claim_x2_pressed()->void:
	var is_reward = await Global.ad_manager.show_user_reward()
	if !is_reward:
		return
	Global.game_data.level.value = Global.game_data.level.value + 1
	Global.game_data.coins.value = 	Global.game_data.coins.value + Global.COINS_PER_LEVEL * 2
	Global.game_data.save_data()
