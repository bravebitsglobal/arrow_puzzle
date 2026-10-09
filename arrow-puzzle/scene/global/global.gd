extends Control
const COINS_PER_LEVEL: int = 10
const MAGIC_GLASSES_QUANTITY: int = 5
var game_data: GameData = GameData.new()
var game_event: GameEvent = GameEvent.new()
@onready var popup_manager: PopupManager = $CanvasLayer/PopupManager
@onready var ad_manager: AdManager = $AdManager
@onready var api: Api = $API
@export var api_endpoint: String
@export var game_token: String

func _ready() -> void:
	game_data.load_data()
