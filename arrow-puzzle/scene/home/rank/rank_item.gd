extends Control
class_name RankItem
@onready var label_name: Label = $LabelName
@onready var other_player: NinePatchRect = $OtherPlayer
@onready var me: NinePatchRect = $Me
@onready var avatar: Avatar = $Avatar
@onready var label_rank: Label = $NinePatchRect3/LabelRank
@onready var label_score: Label = $NinePatchRect2/LabelScore
@onready var crown: TextureRect = $Crown

func set_data(user_id: String, rank: int, score: int, player_name: String, avatar_id: int)->void:
	avatar.set_avatar(avatar_id)
	label_rank.text = str(rank)
	label_name.text = player_name
	label_score.text = str(score)
	var is_me = Global.game_data.profile.value.user_id == user_id
	if is_me:
		other_player.visible = false
		me.visible = true
		crown.visible = true
	else:
		other_player.visible = true
		me.visible = false
		crown.visible = false
