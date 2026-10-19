extends Control
class_name PopupChallengeWelcome
@onready var pagination_container: Panel = $NinePatchRect/PaginationContainer
@onready var pagination_cursor: Control = $NinePatchRect/PaginationContainer/PaginationCursor
@onready var page_container: Control = $NinePatchRect/PageContainer
@onready var button_continue: Button = $NinePatchRect/ButtonContinue

var pagination_tween: Tween
var hide_tween: Tween
var show_tween: Tween
const ANIMATE_TIME = 0.1
var page: int:
	set(value):
		page = value
		change_pagination(value)
		change_page_content(value)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for btn_idx in range(2):
		pagination_container.get_child(btn_idx).pressed.connect(func ():
			page = btn_idx)
	button_continue.pressed.connect(_on_btn_continue_click)
func _on_btn_continue_click():
	Global.game_data.player_data.is_show_challenge_welcome_page = true
	Global.game_data.save_data()
	Global.game_event.request_visible_popup.emit(GameEnum.PopupType.ChallengeWelcome, false)
	return
	#if !page:
		#page = 1
	#else:
		#Global.game_data.player_data.is_show_challenge_welcome_page = true
		#Global.game_data.save_data()
		#Global.game_event.request_visible_popup.emit(GameEnum.PopupType.ChallengeWelcome, false)
func change_pagination(idx: int)->void:
	var child = pagination_container.get_child(idx)
	if pagination_tween:
		pagination_tween.kill()
	pagination_tween = create_tween()
	pagination_tween.tween_property(pagination_cursor, "global_position", child.global_position, ANIMATE_TIME)
func change_page_content(idx: int)->void:
	if hide_tween:
		hide_tween.kill()
	if show_tween:
		show_tween.kill()
	hide_tween = create_tween()
	show_tween = create_tween()
	var hide_panel: Control
	var show_panel: Control
	for i in range(2):
		if i == idx:
			show_panel = page_container.get_child(i)
		else:
			hide_panel = page_container.get_child(i)
	hide_tween.tween_property(hide_panel, 'modulate', Color(1,1,1,0), ANIMATE_TIME)
	show_tween.tween_property(show_panel, 'modulate', Color(1,1,1,1), ANIMATE_TIME)
