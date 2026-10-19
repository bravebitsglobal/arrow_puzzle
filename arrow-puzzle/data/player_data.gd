extends Resource
class_name PlayerData


@export var level: int = 0
@export var coins: int = 0
@export var booster_hint: int = 0
@export var booster_eraser: int = 0
@export var booster_magic_glasses: int = 0
@export var booster_ruler: int = 0
@export var tutorial_step: int = 0
@export var challenges: Dictionary[String, PackedInt32Array] = {}
@export var is_show_challenge_welcome_page: bool = false
@export var setting_enable_music: bool = true
@export var setting_enable_sfx: bool = true
const SAVE_PATH = "user://player_data.tres"
func set_challenge_resolved(year: int, month: int, date: int)->void:
	var key = '%04d-%02d' % [year, month]
	if !challenges.has(key):
		challenges.set(key, [date])
	else:
		if !challenges[key].has(date):
			challenges[key].append(date)
	save()
func get_challenge_dates(year: int, month: int)->PackedInt32Array:
	var key = '%04d-%02d' % [year, month]
	if !challenges.has(key):
		return []
	else:
		return challenges[key]
func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)

func load() -> PlayerData:
	if ResourceLoader.exists(SAVE_PATH):
		return ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerData
	return PlayerData.new()
