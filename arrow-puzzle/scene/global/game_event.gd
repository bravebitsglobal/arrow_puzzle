extends RefCounted
class_name GameEvent
enum UserAction{
	FirstArrow,
	GameStart
}
#ui panel
signal request_visible_popup(popup_type: PopupManager.PopupType, visible: bool)
#game event
signal game_restart
signal game_start
signal active_game_booster(booster: Global.Booster)
signal game_booster_done(booster: Global.Booster)
signal user_action(action: UserAction, data: Dictionary)
signal game_focus_to_arrow(arrow_idx: int)
signal register_tutorial_target(id: String, node: Node)
signal unregister_tutorial_target(id: String)
