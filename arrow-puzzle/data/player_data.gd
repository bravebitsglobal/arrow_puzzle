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
const SAVE_PATH = "user://player_data.tres"

func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)

func load() -> PlayerData:
	if ResourceLoader.exists(SAVE_PATH):
		return ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerData
	return PlayerData.new() # Mặc định
