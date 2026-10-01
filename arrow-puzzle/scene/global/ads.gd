extends Node2D
class_name Ads
var _rewarded_ad: RewardedAd
var _reward_listener := OnUserEarnedRewardListener.new()
var _load_callback := RewardedAdLoadCallback.new()
var _content_callback := FullScreenContentCallback.new()
