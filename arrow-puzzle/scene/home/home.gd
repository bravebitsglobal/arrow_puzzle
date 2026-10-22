extends Control
class_name HomeScene
@onready var tab: HBoxContainer = $PanelBottom/MarginContainer/MarginContainer/Tab
var active_tab: int = -1
const DEFAULT_ACTIVE_TAB = 0
const TAB_ANIMATION_DURATION = 0.2

@onready var challenge: Control = $Challenge
@onready var main: Control = $Main
var tab_content: Array
@onready var texture_highlight: TextureRect = $PanelBottom/MarginContainer/Control/TextureHighlight
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tab_content = [main, null, null, challenge]
	Global.game_data.home_tab.subscribe(func (tab):
		change_active_tab.call_deferred(tab)
		)
	bind_tab_buttons()
	Global.game_event.scene_changed.emit(GameEnum.SceneName.Home)

func bind_tab_buttons():
	for i in range(tab.get_children().size()):
		var node: TextureButton = tab.get_child(i)
		node.pressed.connect(func ():
			Global.game_data.home_tab.value = i
			)
func change_active_tab(new_tab: int)->void:
	if active_tab == new_tab:
		return
	var new_node: Control = tab.get_child(new_tab)
	if active_tab == -1:
		texture_highlight.size = new_node.size
		texture_highlight.visible = true
		texture_highlight.global_position = new_node.global_position
	else:
		texture_highlight.size = new_node.size
		var tween = create_tween().set_parallel(true)
		tween.tween_property(texture_highlight, "global_position", new_node.global_position, TAB_ANIMATION_DURATION)
	active_tab = new_tab
	var show_challenge = active_tab == 3
	if show_challenge:
		if !Global.game_data.player_data.is_show_challenge_welcome_page:
			Global.game_event.request_visible_popup.emit(GameEnum.PopupType.ChallengeWelcome, true)
			
	for i in range(tab_content.size()):
		if tab_content[i]:
			tab_content[i].visible = active_tab == i
