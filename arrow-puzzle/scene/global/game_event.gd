extends RefCounted
class_name GameEvent
#ui panel
signal request_visible_popup(popup_type: PopupManager.PopupType, visible: bool)
#game event
signal game_restart
signal game_start
