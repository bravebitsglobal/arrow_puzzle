extends Control
class_name RankItem
@onready var avatar: Avatar = $NinePatchRect/Avatar
@onready var label_score: Label = $NinePatchRect/NinePatchRect/LabelScore
@onready var label_rank: Label = $NinePatchRect/NinePatchRect2/LabelRank
@onready var label_name: Label = $NinePatchRect/LabelName

func set_data(user_id: String, rank: int, score: int, player_name: String, avatar_id: int)->void:
	avatar.set_avatar(avatar_id)
	label_rank.text = str(rank)
	label_name.text = player_name
	label_score.text = str(score)
	print("profile ", Global.game_data.profile)
	
