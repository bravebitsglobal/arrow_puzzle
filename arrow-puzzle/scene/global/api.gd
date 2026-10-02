extends Control
class_name Api
## Gọi API GameHub (https://gamehub.bravebits.ai/api/docs).
## - Base URL lấy từ Global.api_endpoint (vd: "https://gamehub.bravebits.ai").
## - Header x-api-key lấy từ Global.game_token.
## - JWT người chơi tự lưu sau khi đăng nhập (device/password/oauth) và gửi kèm "Authorization: Bearer".
##
## Mọi hàm đều là coroutine, gọi bằng await qua Global.api:
##   var res := await Global.api.device_register(OS.get_unique_id(), "VN")
##   if res.ok: print(res.data)
## Kết quả: {"ok": bool, "code": int (HTTP status), "data": Variant (JSON đã parse), "error": String}
@export var api_endpoint: String
@export var game_token: String
const TIMEOUT_SEC: float = 15.0
const LEADERBOARD_TYPES: PackedStringArray = ["monthly", "alltime", "country", "team", "monthly-plays"]

var access_token: String = ""


func set_access_token(token: String) -> void:
	access_token = token


func clear_access_token() -> void:
	access_token = ""


func is_logged_in() -> bool:
	return not access_token.is_empty()


# ----------------------------------------------------------------
# Auth & User
# ----------------------------------------------------------------

func device_register(device_id: String, country: String, display_name: String = "") -> Dictionary:
	var body := {"deviceId": device_id, "country": country}
	if not display_name.is_empty():
		body["displayName"] = display_name
	return _store_token(await request(HTTPClient.METHOD_POST, "/auth/device/register", body))


func password_login(username: String, password: String) -> Dictionary:
	return _store_token(await request(HTTPClient.METHOD_POST, "/auth/password/login", {"username": username, "password": password}))


## provider: "facebook" | "google"
func oauth_login(provider: String, token: String) -> Dictionary:
	return _store_token(await request(HTTPClient.METHOD_POST, "/auth/oauth/login", {"provider": provider, "token": token}))


func link_password(username: String, password: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/auth/link/password", {"username": username, "password": password})


func link_oauth(provider: String, token: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/auth/link/oauth", {"provider": provider, "token": token})


func get_me() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/auth/me")


func update_me(display_name: String) -> Dictionary:
	return await request(HTTPClient.METHOD_PATCH, "/auth/me", {"displayName": display_name})


# ----------------------------------------------------------------
# Team
# ----------------------------------------------------------------

func get_teams() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/teams")


## avatar_id / level_require < 0 và description rỗng = không gửi.
func create_team(team_name: String, avatar_id: int = -1, description: String = "", level_require: int = -1) -> Dictionary:
	var body := {"name": team_name}
	if avatar_id >= 0:
		body["avatarId"] = avatar_id
	if not description.is_empty():
		body["description"] = description
	if level_require >= 1:
		body["levelRequire"] = level_require
	return await request(HTTPClient.METHOD_POST, "/teams", body)


func get_my_team() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/teams/mine")


## Tin nhắn theo thời gian tăng dần; kind = system/member/help_request.
func get_team_messages(limit: int = 50) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/teams/messages", null, {"limit": limit})


func send_team_message(text: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/teams/messages", {"text": text})


## Team của một user, data = null nếu user chưa vào team.
func get_team_of_user(user_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/teams/user/%s" % user_id.uri_encode())


func get_team(team_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/teams/%s" % team_id.uri_encode())


## Mỗi user 1 request đang đợi, cách nhau 6h.
func create_help_request(text: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/teams/help-requests", {"text": text})


func help_team_request(message_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/teams/messages/%s/help" % message_id.uri_encode())


func leave_team() -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/teams/leave")


## data = {teamId, ownerId, members: [{id, displayName, country, level, status, isOwner}]}
func get_team_members(team_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/teams/%s/members" % team_id.uri_encode())


func join_team(team_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/teams/%s/join" % team_id.uri_encode())


# ----------------------------------------------------------------
# Profile
# ----------------------------------------------------------------

func get_profile() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/profile")


func save_profile(data: Dictionary) -> Dictionary:
	return await request(HTTPClient.METHOD_PUT, "/profile", {"data": data})


func get_user_profile(user_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/profile/%s" % user_id.uri_encode())


# ----------------------------------------------------------------
# Leaderboard
# ----------------------------------------------------------------

func submit_score(points: float) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/leaderboards/submit", {"points": points})


## type: một trong LEADERBOARD_TYPES.
## period "YYYY-MM" chỉ dùng cho monthly/monthly-plays; country (ISO alpha-2) bắt buộc khi type=country;
## team_id bắt buộc khi type=team. limit 1-500.
## data = {entries, aroundMe, myRank (khi có JWT)}
func get_leaderboard(type: String, limit: int = 100, period: String = "", country: String = "", team_id: String = "") -> Dictionary:
	var query := {"limit": clampi(limit, 1, 500)}
	if not period.is_empty():
		query["period"] = period
	if not country.is_empty():
		query["country"] = country.to_upper()
	if not team_id.is_empty():
		query["teamId"] = team_id
	return await request(HTTPClient.METHOD_GET, "/leaderboards/%s" % type, null, query)


func get_leaderboards() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/leaderboards")


# ----------------------------------------------------------------
# Mail
# ----------------------------------------------------------------

func get_mails() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/mails")


func get_unclaimed_mail_count() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/mails/unclaimed-count")


## Server chỉ đánh dấu đã nhận; client tự cộng thưởng.
func claim_mail(mail_id: String) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, "/mails/%s/claim" % mail_id.uri_encode())


# ----------------------------------------------------------------
# Level
# ----------------------------------------------------------------

func get_level(level_id: int) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/levels/%d" % level_id)


# ----------------------------------------------------------------
# Core
# ----------------------------------------------------------------

## Gửi request tới `<api_endpoint>/api<path>`. body = null -> không gửi body.
func request(method: HTTPClient.Method, path: String, body: Variant = null, query: Dictionary = {}) -> Dictionary:
	var url := _base_url() + path
	if not query.is_empty():
		var parts: PackedStringArray = []
		for k in query:
			parts.append("%s=%s" % [str(k).uri_encode(), str(query[k]).uri_encode()])
		url += "?" + "&".join(parts)

	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"x-api-key: %s" % game_token,
	])
	if not access_token.is_empty():
		headers.append("Authorization: Bearer %s" % access_token)

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	# Deferred: node cha có thể đang bận add children (khi gọi từ _ready).
	add_child.call_deferred(http)
	await http.ready
	var payload: String = "" if body == null else JSON.stringify(body)
	var err := http.request(url, headers, method, payload)
	if err != OK:
		http.queue_free()
		return _result(false, 0, null, "HTTPRequest error %d" % err)

	var resp: Array = await http.request_completed
	http.queue_free()

	var net_result: int = resp[0]
	var code: int = resp[1]
	var raw: PackedByteArray = resp[3]
	if net_result != HTTPRequest.RESULT_SUCCESS:
		return _result(false, code, null, "Network error %d" % net_result)

	var text := raw.get_string_from_utf8()
	var data: Variant = null
	if not text.is_empty():
		data = JSON.parse_string(text)
		if data == null:
			data = text

	var ok := code >= 200 and code < 300
	var error_msg := ""
	if not ok:
		error_msg = str(data.get("message", "HTTP %d" % code)) if data is Dictionary else "HTTP %d" % code
	return _result(ok, code, data, error_msg)


func _base_url() -> String:
	var base: String = api_endpoint.strip_edges().trim_suffix("/")
	if not base.ends_with("/api"):
		base += "/api"
	return base


func _result(ok: bool, code: int, data: Variant, error: String) -> Dictionary:
	return {"ok": ok, "code": code, "data": data, "error": error}


## Lưu JWT từ response đăng nhập (tên field chưa ghi trong docs nên thử các tên phổ biến).
func _store_token(res: Dictionary) -> Dictionary:
	if res.ok and res.data is Dictionary:
		for key in ["accessToken", "access_token", "token", "jwt"]:
			if res.data.has(key) and res.data[key] is String:
				access_token = res.data[key]
				break
	return res
