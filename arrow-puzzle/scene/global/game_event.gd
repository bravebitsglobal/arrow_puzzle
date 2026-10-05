extends RefCounted
class_name GameEvent
#ui panel
signal request_visible_popup(popup_type: PopupManager.PopupType, visible: bool)
#game event
signal game_restart
signal game_start
signal active_game_booster(booster: Global.Booster)
signal game_booster_done(booster: Global.Booster)
