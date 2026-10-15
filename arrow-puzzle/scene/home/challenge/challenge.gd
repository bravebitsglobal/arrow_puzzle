extends Control
class_name Challenge
@onready var calendar: Control = $Calendar

const WEEKDAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
@export var cell_size: Vector2 = Vector2(120, 120)
@onready var date_container: GridContainer = $Calendar/DateContainer
@onready var button_play: Button = $ButtonPlay


var month: int 
var year: int
var date: int
var resolved_date: PackedInt32Array
var enable_date: PackedInt32Array
var date_nodes: Dictionary[int, Day] = {}
var last_select_date: int = 0
func _ready() -> void:
	var date_dict = Time.get_date_dict_from_system()
	month = date_dict['month']
	year = date_dict['year']
	resolved_date = Global.game_data.player_data.get_challenge_dates(year, month)
	render_calendar()
	for i in date_container.get_children():
		i.clicked.connect(_on_date_clicked)
	button_play.pressed.connect(_on_play_click)
func _on_play_click()->void:
	if !(year && month && date):
		Global.popup_manager.show_toast("Please select a date")
		return
	Global.game_data.current_challenge.value = [year, month, date]
	get_tree().change_scene_to_file("res://scene/game/game.tscn")
func _on_date_clicked(_date: int)->void:
	date = _date
	if enable_date.has(date):
		date_nodes[date].set_state('selected')
	if last_select_date:
		date_nodes[last_select_date].set_state('enable')
	last_select_date = date
func get_days_in_month(_year: int, _month: int) -> int:
	var days_in_months = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if _month == 2 and ((_year % 4 == 0 and _year % 100 != 0) or (_year % 400 == 0)):
		return 29
	return days_in_months[_month]
func render_calendar()->void:
	var days = get_days_in_month(year, month)
	var unix_time = Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": 1,
		"hour": 0, "minute": 0, "second": 0
	})
	var now_dict = Time.get_datetime_dict_from_system()
	var date_dict = Time.get_date_dict_from_unix_time(unix_time)
	var weekday = date_dict['weekday']
	for i in date_container.get_children():
		i.modulate = Color(0,0,0,0)
	enable_date = []
	date_nodes.clear()
	for i in range(days):
		var child: Day = date_container.get_child(weekday + i)
		date_nodes[i + 1] = child
		child.modulate = Color(1,1,1,1)
		child.set_date(i + 1)
		if i < now_dict['day']:
			enable_date.append(i + 1)
			child.set_state('enable')
		else:
			child.set_state('disable')
	for i in resolved_date:
		var date_item = date_container.get_child(weekday + i - 1)
		date_item.set_state('resolved')
