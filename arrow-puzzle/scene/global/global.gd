extends Control
const COINS_PER_LEVEL: int = 10
var level: Observable = Observable.new()
var coins: Observable = Observable.new()
var player_data: PlayerData = PlayerData.new()

func _ready() -> void:
	player_data = player_data.load()
	level.value = player_data.level
	coins.value = player_data.coins
	print("Player data ", player_data.level)
func save_data():
	player_data.level = level.value
	player_data.coins = coins.value
	print("save data ", level.value, ":", coins.value)
	player_data.save()
