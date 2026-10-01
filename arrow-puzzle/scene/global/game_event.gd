extends RefCounted
class_name GameEvent
#ui panel
signal request_visible_game_panel(panel_name: String, visible: bool)
#game event
signal game_retry
signal game_next_level
