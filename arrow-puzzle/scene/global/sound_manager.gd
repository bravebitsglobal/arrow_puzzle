extends Control
class_name SoundManager
@onready var background_player: AudioStreamPlayer = $BackgroundPlayer
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@export var sounds: Dictionary[GameEnum.Sound, AudioStream]
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.game_event.on_setting_updated.connect(update_setting)
func update_setting():
	var music_bus_index = AudioServer.get_bus_index("Music")
	var sfx_bus_index = AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(music_bus_index, not Global.game_data.player_data.setting_enable_music)
	AudioServer.set_bus_mute(sfx_bus_index, not Global.game_data.player_data.setting_enable_sfx)
	
func play_sound(sound: GameEnum.Sound):
	sound_player.stream = sounds[sound]
	sound_player.play()
