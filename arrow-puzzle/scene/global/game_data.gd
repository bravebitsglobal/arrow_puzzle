extends RefCounted
class_name GameData
var level: Observable = Observable.new()
var coins: Observable = Observable.new()
var player_data: PlayerData = PlayerData.new()
func load_data()->void:
	player_data = player_data.load()
	level.value = player_data.level
	coins.value = player_data.coins
func save_data()->void:
	player_data.level = level.value
	player_data.coins = coins.value
	player_data.save()
