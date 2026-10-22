extends RefCounted
class_name GameEnum
enum Booster {
	Hint,
	Eraser,
	MagicGlasses,
	Ruler
}
enum UserAction {
	ResolveArrow,
	LevelStart,
	ActiveBooster,
}
enum PopupType {
	GameWin,
	OutOfLive,
	ChallengeWelcome,
	Setting,
	DailyReward,
	SelectAvatar
}
enum Sound {
	Click
}
enum RewardType{
	Coin,
	Hint,
	Eraser,
	MagicGlasses,
	Ruler
}
enum SceneName{
	Loading,
	Home,
	Game
}
const DAILY_REWARDS = [
		[
			{
				"reward_type": GameEnum.RewardType.Coin,
				"quantity": 10
			}
		],
		[
			{
				"reward_type": GameEnum.RewardType.Coin,
				"quantity": 20
			}
		],
		[
			{
				"reward_type": GameEnum.RewardType.Hint,
				"quantity": 1
			}
		],
		[
			{
				"reward_type": GameEnum.RewardType.Coin,
				"quantity": 30
			}
		],
		[
			{
				"reward_type": GameEnum.RewardType.Ruler,
				"quantity": 1
			}
		],
		[
			{
				"reward_type": GameEnum.RewardType.MagicGlasses,
				"quantity": 1
			}
		],
		[
			{
				"reward_type": GameEnum.RewardType.Coin,
				"quantity": 50
			},
			{
				"reward_type": GameEnum.RewardType.Hint,
				"quantity": 1
			},
			{
				"reward_type": GameEnum.RewardType.Eraser,
				"quantity": 1
			},
			{
				"reward_type": GameEnum.RewardType.MagicGlasses,
				"quantity": 1
			}
		]
	]
