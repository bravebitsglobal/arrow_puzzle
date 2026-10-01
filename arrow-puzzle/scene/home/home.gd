extends Control
class_name HomeScene
@onready var tab: HBoxContainer = $PanelBottom/Tab
var active_tab: int = -1
const DEFAULT_ACTIVE_TAB = 2
@onready var button_play: TextureButton = $PanelBottom/ButtonPlay
@onready var label_level: Label = $PanelBottom/ButtonPlay/LabelLevel
@onready var label_coins: Label = $PanelTop/Coin/LabelCoins

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	change_active_tab(DEFAULT_ACTIVE_TAB)
	bind_tab_buttons()
	Global.game_data.level.subscribe(func (level):
		label_level.text = "Level " + str(level)
		label_level.visible = level > 0
		)
	button_play.pressed.connect(func():
		get_tree().change_scene_to_file("res://scene/game/game.tscn")
		Global.game_data.level.value = Global.game_data.level.value + 1
		)
	Global.game_data.coins.subscribe(func (coins):
		label_coins.text = str(coins)
		)
func bind_tab_buttons():
	for i in range(tab.get_children().size()):
		var node: TextureButton = tab.get_child(i)
		node.pressed.connect(func ():
			print("user pressed tab ", i)
			change_active_tab(i)
			)
func change_active_tab(new_tab: int)->void:
	const DURATION = 0.2
	const SCALE = Vector2(2, 2)
	if active_tab == new_tab:
		return
	var tween = create_tween().set_parallel(true)
	if active_tab >= 0:
		var old_node = tab.get_child(active_tab)
		var old_icon_node = old_node.get_node("Icon")
		tween.tween_property(old_node, "custom_minimum_size", Vector2(200, 0), DURATION)
		tween.tween_property(old_node.get_node("Highlight"), "self_modulate", Color(1,1,1,0), DURATION)
		tween.tween_property(old_node.get_node("Label"), "self_modulate", Color(1,1,1,0), DURATION)
		tween.tween_property(old_icon_node, "scale", Vector2.ONE, DURATION)
		tween.tween_property(old_icon_node, "offset_transform_position", Vector2.ZERO, DURATION)
	var new_node = tab.get_child(new_tab)
	var new_icon_node = new_node.get_node("Icon")
	tween.tween_property(new_node, "custom_minimum_size", Vector2(300, 0), DURATION)
	tween.tween_property(new_node.get_node("Highlight"), "self_modulate", Color(1,1,1,1), DURATION)
	tween.tween_property(new_icon_node, "scale", SCALE, DURATION)
	tween.tween_property(new_node.get_node("Label"), "self_modulate", Color(1,1,1,1), DURATION)
	tween.tween_property(new_icon_node, "offset_transform_position", Vector2(0, -30), DURATION)
	active_tab = new_tab
