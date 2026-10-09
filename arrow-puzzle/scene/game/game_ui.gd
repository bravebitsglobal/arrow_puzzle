extends CanvasLayer
class_name GameUI
@onready var label_line: Label = $PanelGame/TopPanel/Panel/TextureRect/LabelLine
@onready var button_claim: TextureButton = $PanelWin/HBoxContainer/ButtonClaim
@onready var button_claimx_2: TextureButton = $PanelWin/HBoxContainer/ButtonClaimx2
@onready var label_level: Label = $PanelGame/TopPanel/HBoxContainer/Level/LabelLevel
@onready var label_coin: Label = $PanelGame/TopPanel/HBoxContainer/Coin/LabelCoin
@onready var live_container: HBoxContainer = $PanelGame/TopPanel/HBoxContainer/LiveContainer
@onready var button_hint: TextureButton = $PanelGame/BottomPanel/ButtonHint
@onready var button_eraser: TextureButton = $PanelGame/BottomPanel/ButtonEraser
@onready var button_magic_glasses: TextureButton = $PanelGame/BottomPanel/ButtonMagicGlasses
@onready var button_ruler: TextureButton = $PanelGame/BottomPanel/ButtonRuler
@onready var select_eraser_arrow: ColorRect = $PanelGame/SelectEraserArrow
@onready var first_arrow: ColorRect = $PanelGame/BottomPanel/FirstArrow

func _ready() -> void:
	Global.game_data.active_tutorial.subscribe(_on_active_tutorial_changed)
	Global.game_data.remain_lines.subscribe(func (lines):
		label_line.text = str(lines))
	Global.game_data.level.subscribe(func(lvl):
		label_level.text = str(lvl))
	Global.game_data.coins.subscribe(func(coins):
		label_coin.text = str(coins))
	Global.game_data.lives.subscribe(render_live)
	button_hint.pressed.connect(_on_booster_hint_click)
	button_eraser.pressed.connect(_on_booster_eraser_click)
	button_magic_glasses.pressed.connect(_on_booster_magic_glasses_click)
	button_ruler.pressed.connect(_on_booster_ruler_click)
	Global.game_event.game_booster_done.connect(_on_booster_active_done)
	Global.game_data.booster_hint.subscribe(func (quantity):
		if quantity:
			button_hint.get_node("TexturePlus").visible = false
			button_hint.get_node("Quantity").visible = true
			button_hint.get_node("Quantity/Label").text = str(quantity)
		else:
			button_hint.get_node("TexturePlus").visible = true
			button_hint.get_node("Quantity").visible = false
			)
	Global.game_data.booster_eraser.subscribe(func (quantity):
		if quantity:
			button_eraser.get_node("TexturePlus").visible = false
			button_eraser.get_node("Quantity").visible = true
			button_eraser.get_node("Quantity/Label").text = str(quantity)
		else:
			button_eraser.get_node("TexturePlus").visible = true
			button_eraser.get_node("Quantity").visible = false
			)
	Global.game_data.booster_magic_glasses.subscribe(func (quantity):
		if quantity:
			button_magic_glasses.get_node("TexturePlus").visible = false
			button_magic_glasses.get_node("Quantity").visible = true
			button_magic_glasses.get_node("Quantity/Label").text = str(quantity)
		else:
			button_magic_glasses.get_node("TexturePlus").visible = true
			button_magic_glasses.get_node("Quantity").visible = false	)
	Global.game_data.booster_ruler.subscribe(func (quantity):
		if quantity:
			button_ruler.get_node("TexturePlus").visible = false
			button_ruler.get_node("Quantity").visible = true
			button_ruler.get_node("Quantity/Label").text = str(quantity)
		else:
			button_ruler.get_node("TexturePlus").visible = true
			button_ruler.get_node("Quantity").visible = false)
func _on_active_tutorial_changed(step)->void:
	if !step:
		first_arrow.visible = false
	else:
		if step.action == "focus_an_arrow":
			first_arrow.visible = true
func _on_booster_hint_click()->void:
	if Global.game_data.animating.value:
		return
	print("not active tutorial ", Global.game_data.active_tutorial.value)
	if Global.game_data.active_tutorial.value:
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
		{"booster": GameEnum.Booster.Hint})
		return
	if Global.game_data.booster_hint.value:
		Global.game_data.booster_hint.value = Global.game_data.booster_hint.value - 1
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.Hint})
	else:
		await Global.ad_manager.show_user_reward()
		Global.game_data.booster_hint.value = 3
	Global.game_data.save_data()
func _on_booster_eraser_click()->void:
	if Global.game_data.animating.value:
		return
	if Global.game_data.active_tutorial.value:
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.Eraser})
		select_eraser_arrow.visible = true
		return
	if Global.game_data.booster_eraser.value:
		Global.game_data.booster_eraser.value = Global.game_data.booster_eraser.value - 1
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.Eraser})
		select_eraser_arrow.visible = true
	else:
		await Global.ad_manager.show_user_reward()
		Global.game_data.booster_eraser.value = 3
	Global.game_data.save_data()
func _on_booster_magic_glasses_click()->void:
	if Global.game_data.animating.value:
		return
	if Global.game_data.active_tutorial.value:
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.MagicGlasses})
		return
	if Global.game_data.booster_magic_glasses.value:
		Global.game_data.booster_magic_glasses.value = Global.game_data.booster_magic_glasses.value - 1
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.MagicGlasses})
	else:
		await Global.ad_manager.show_user_reward()
		Global.game_data.booster_magic_glasses.value = 3
	Global.game_data.save_data()
func _on_booster_ruler_click()->void:
	if Global.game_data.animating.value:
		return
	if Global.game_data.active_tutorial.value:
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.Ruler})
		return
	if Global.game_data.booster_ruler.value:
		Global.game_data.booster_ruler.value = Global.game_data.booster_ruler.value - 1
		Global.game_event.user_action.emit(GameEnum.UserAction.ActiveBooster, 
			{"booster": GameEnum.Booster.Ruler})
		Global.game_data.is_ruler.value = true
	else:
		await Global.ad_manager.show_user_reward()
		Global.game_data.booster_ruler.value = 3
	Global.game_data.save_data()
func render_live(lives: int)->void:
	if !live_container:
		return
	for i in range(Global.game_data.MAX_LIVE):
		live_container.get_child(i).get_child(0).visible = i < lives
func _on_booster_active_done(booster: GameEnum.Booster)->void:
	match(booster):
		GameEnum.Booster.Eraser:
			select_eraser_arrow.visible = false
