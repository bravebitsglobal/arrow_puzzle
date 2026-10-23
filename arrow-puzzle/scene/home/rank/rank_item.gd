extends Control
class_name RankItem
@onready var avatar: Avatar = $Avatar
@onready var label_name: Label = $NinePatchRect/LabelName
@onready var label_rank: Label = $NinePatchRect/LabelRank
@onready var label_score: Label = $NinePatchRect/LabelScore
func set_data(rank: int, score: int, player_name: String, avatar_id: int)->void:
	avatar.set_avatar(avatar_id)
	label_rank.text = str(rank)
	label_name.text = player_name
	label_score.text = "Score: %d" % score
	
