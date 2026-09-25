extends Node2D
var grid = [4144,4145,4146,4147,4244,4245,4246,4247,4344,4345,4346,4347,4444,4445,4446,4447,4544,4545,4546,4547,4644,4645,4646,4647,4744,4745,4746,4747,4844,4845,4846,4847,4944,4945,4946,4947,5044,5045,5046,5047,5144,5145,5146,5147,5244,5245,5246,5247]
@onready var line_container: Node2D = $LineContainer


var level_generator = LevelGenerator.new()
@export var arrow_scene: PackedScene
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var rs = level_generator.generate_level(grid, LevelGenerator.Difficulty.HARD)
	for a in rs:
		var line: Arrow = arrow_scene.instantiate()
		line_container.add_child(line)
		line.set_data(a)
		
