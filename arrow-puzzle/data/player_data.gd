extends Resource
class_name PlayerData


@export var level: int = 0
@export var coins: int = 0
const SAVE_PATH = "user://player_data.tres"

func save() -> void:
	print("save ", level, ": coins: ", coins)
	ResourceSaver.save(self, SAVE_PATH)

func load() -> PlayerData:
	if ResourceLoader.exists(SAVE_PATH):
		print("load here")
		return ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerData
	return PlayerData.new() # Mặc định
