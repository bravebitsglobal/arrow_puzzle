extends RefCounted
class_name Observable
signal on_change
var value:
	get:
		return value
	set(new_value):
		value = new_value
		on_change.emit(value)
func subscribe(callback: Callable)->void:
	callback.call(value)
	on_change.connect(callback)
