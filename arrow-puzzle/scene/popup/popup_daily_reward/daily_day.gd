extends Button
class_name DailyDay
@onready var claimed: TextureRect = $Claimed
@onready var unclaim: TextureRect = $Unclaim
@onready var selected: TextureRect = $Selected
@onready var locked: TextureRect = $Locked
@export var day: int 
@onready var label: Label = $Label
@onready var effect_select: Control = $EffectSelect

func _ready() -> void:
	label.text = "Day %d" % day
func set_state(state: String)->void:
	unclaim.visible = false
	claimed.visible = false
	selected.visible = false
	locked.visible = false
	match state:
		'claimed':
			claimed.visible = true
		'unclaim':
			unclaim.visible = true
		'locked':
			locked.visible = true
func set_select(is_select: bool)->void:
	effect_select.visible = is_select
