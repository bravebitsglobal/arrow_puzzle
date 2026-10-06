extends Control
@onready var calendar: Control = $Calendar

signal day_selected(date: String)

const WEEKDAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
@export var cell_size: Vector2 = Vector2(120, 120)


func _ready() -> void:
	var today := Time.get_date_dict_from_system()
	generate(today.year, today.month)


## Tạo lịch của tháng (year, month) rồi add_child vào Calendar. Tuần bắt đầu từ thứ Hai.
func generate(year: int, month: int) -> void:
	for child in calendar.get_children():
		child.queue_free()

	var box := VBoxContainer.new()
	calendar.add_child(box)

	var title := Label.new()
	title.text = "%s %d" % [MONTHS[month - 1], year]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 7
	box.add_child(grid)

	for w in WEEKDAYS:
		var label := Label.new()
		label.text = w
		label.custom_minimum_size = Vector2(cell_size.x, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(label)

	# Ô trống trước ngày 1 (weekday của Godot: 0 = Chủ nhật → đổi sang 0 = thứ Hai).
	var first_weekday: int = (_weekday(year, month, 1) + 6) % 7
	for i in first_weekday:
		var empty := Control.new()
		empty.custom_minimum_size = cell_size
		grid.add_child(empty)

	var today := Time.get_date_dict_from_system()
	var today_key: int = today.year * 10000 + today.month * 100 + today.day
	for day in range(1, _days_in_month(year, month) + 1):
		var date_key := year * 10000 + month * 100 + day
		var button := Button.new()
		button.text = str(day)
		button.custom_minimum_size = cell_size
		# Ngày tương lai chưa chơi được.
		button.disabled = date_key > today_key
		if date_key == today_key:
			button.modulate = Color(1, 0.85, 0.3)
		var date := "%04d-%02d-%02d" % [year, month, day]
		button.pressed.connect(func(): day_selected.emit(date))
		grid.add_child(button)


func _weekday(year: int, month: int, day: int) -> int:
	var unix := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day})
	return Time.get_datetime_dict_from_unix_time(unix).weekday


func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	return 30 if month in [4, 6, 9, 11] else 31
