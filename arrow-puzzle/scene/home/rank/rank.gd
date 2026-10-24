extends Control
@export var rank_item_scene: PackedScene
@onready var rank_item_container: VBoxContainer = $ScrollContainer/MarginContainer/RankItemContainer

func _ready() -> void:
	visibility_changed.connect(func ():
		if visible:
			load_data()
			)
func load_data()->void:
	Global.popup_manager.show_loading()
	for i in rank_item_container.get_children():
		i.queue_free()
	var leader = await Global.api.get_leaderboard('alltime')
	print("leader ", leader)
	var entries = leader.data.entries
	for i in entries:
		var node: RankItem = rank_item_scene.instantiate()
		rank_item_container.add_child(node)
		var name = i.displayName
		if !name:
			name = "Unknown Player"
		var avatar = i.avatar if i.avatar != null else 0
		node.set_data(i.rank, i.score, name, avatar)
	Global.popup_manager.hide_loading()
