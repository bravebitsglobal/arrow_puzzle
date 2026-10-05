extends RefCounted
class_name GameData
const MAX_LIVE = 3
var level: Observable = Observable.new()
var coins: Observable = Observable.new()
var booster_hint: Observable = Observable.new(0)
var booster_eraser: Observable = Observable.new(0)
var booster_magic_glasses: Observable = Observable.new(0)
var booster_ruler: Observable = Observable.new(0)
var player_data: PlayerData = PlayerData.new()
#game
var remain_lines: Observable = Observable.new()
var lives: Observable = Observable.new(MAX_LIVE)
var animating: Observable = Observable.new(false)
var is_ruler: Observable = Observable.new(false)
func load_data()->void:
	player_data = player_data.load()
	level.value = player_data.level
	coins.value = player_data.coins
	booster_hint.value = player_data.booster_hint
	booster_eraser.value = player_data.booster_eraser
	booster_magic_glasses.value = player_data.booster_magic_glasses
	booster_ruler.value = player_data.booster_ruler
func save_data()->void:
	player_data.level = level.value
	player_data.coins = coins.value
	player_data.booster_hint = booster_hint.value
	player_data.booster_eraser = booster_eraser.value
	player_data.booster_magic_glasses = booster_magic_glasses.value
	player_data.booster_ruler = booster_ruler.value
	player_data.save()
