extends Control
const COINS_PER_LEVEL: int = 10
const MAGIC_GLASSES_QUANTITY: int = 5
var game_data: GameData = GameData.new()
var game_event: GameEvent = GameEvent.new()
@onready var popup_manager: PopupManager = $CanvasLayer/PopupManager
@onready var ad_manager: AdManager = $AdManager
@onready var sound_manager: SoundManager = $SoundManager
@onready var api: Api = $API
@onready var reward_manager: RewardManager = $RewardManager
@onready var firebase_manager: FirebaseManager = $FirebaseManager

@export var api_endpoint: String
@export var game_token: String
func _init() -> void:
	game_data.load_data()
func is_debug()->bool:
	return OS.is_debug_build()
