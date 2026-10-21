extends Control
class_name DailyDay
@onready var claimed: TextureRect = $Claimed
@onready var unclaim: TextureRect = $Unclaim
@onready var selected: TextureRect = $Selected
func set_state(state: String)->void:
	unclaim.visible = false
	claimed.visible = false
	selected.visible = false
	match state:
		'claimed':
			claimed.visible = true
		'unclaim':
			unclaim.visible = true
		'selected':
			selected.visible = true
