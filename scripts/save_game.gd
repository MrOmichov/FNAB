extends Node
## Persistent campaign/profile data. Runtime night requests are deliberately not saved.

signal save_changed()
signal save_error(message: String)

const SCHEMA_VERSION := 1
const MAX_CAMPAIGN_ID := 2147483647
const MAX_SAVE_BYTES := 262144
const MAX_COLLECTION_ITEMS := 512
const NIGHT_CONFIG_PATHS := {
	1: "res://resources/night_1.tres",
	2: "res://resources/night_2.tres",
	3: "res://resources/night_3.tres",
	4: "res://resources/night_4.tres",
	5: "res://resources/night_5.tres",
	6: "res://resources/night_6.tres",
}
const CUSTOM_LEVEL_KEYS := ["berry", "blacky", "dog", "sann", "old_creeper"]
const ENDING_IDS := ["bad_ending", "neutral_ending", "middle_ending", "canonical_ending"]
const MINIGAME_IDS := ["computer", "dog", "assemble", "walk"]

## Set before adding this Node to the tree when a caller needs isolated storage.
var save_path: String = "user://progress.json"
var last_error: String = ""

var _data: Dictionary = {}
var _loaded := false
var _writes_locked := false
var _recovered_from_backup := false
var _pending_night_request: Dictionary = {}


func _ready() -> void:
	load_save()


func load_save() -> bool:
	_pending_night_request.clear()
	_writes_locked = false
	_recovered_from_backup = false
	var primary_path := save_path
	var backup_path := _backup_path()
	var primary_exists := FileAccess.file_exists(primary_path)
	var backup_exists := FileAccess.file_exists(backup_path)

	if not primary_exists and not backup_exists:
		_data = _fresh_profile()
		_loaded = true
		last_error = ""
		save_changed.emit()
		return true

	var primary_result: Dictionary = {}
	var backup_result: Dictionary = {}
	if primary_exists:
		primary_result = _read_document(primary_path)
	if backup_exists:
		backup_result = _read_document(backup_path)

	# A future format must never be replaced or hidden behind an older backup.
	if bool(primary_result.get("future", false)) or bool(backup_result.get("future", false)):
		_writes_locked = true
		if bool(primary_result.get("future", false)):
			_data = _fresh_profile()
		elif bool(primary_result.get("ok", false)):
			_data = primary_result["data"]
		elif bool(backup_result.get("ok", false)):
			_data = backup_result["data"]
			_recovered_from_backup = true
		else:
			_data = _fresh_profile()
		_loaded = true
		_set_error("Сохранение создано более новой версией игры. Данные доступны только для чтения.")
		save_changed.emit()
		return false

	if bool(primary_result.get("ok", false)):
		_data = primary_result["data"]
		_loaded = true
		last_error = ""
		save_changed.emit()
		return true

	if bool(backup_result.get("ok", false)):
		_data = backup_result["data"]
		_loaded = true
		_recovered_from_backup = true
		_set_error("Основное сохранение повреждено. Загружена резервная копия; она останется нетронутой до успешной записи нового файла.")
		save_changed.emit()
		return true

	# Existing but unreadable/corrupt files are not equivalent to a new profile.
	# Lock writes so starting a campaign cannot silently erase collections.
	_data = _fresh_profile()
	_loaded = true
	_writes_locked = true
	_set_error("Основное и резервное сохранения повреждены. Запись отключена, чтобы не стереть существующие данные.")
	save_changed.emit()
	return false


func can_continue() -> bool:
	return _data.get("campaign", {}).get("started", false) == true


func get_checkpoint_night() -> int:
	if not can_continue():
		return 1
	return int(_data["campaign"].get("next_night", 1))


func get_campaign_id() -> int:
	return int(_data.get("campaign", {}).get("id", 0))


func get_snapshot() -> Dictionary:
	return _data.duplicate(true)


func start_new_campaign() -> bool:
	if not _ensure_loaded() or _writes_locked:
		return _fail("Новая кампания недоступна: сохранение повреждено или доступно только для чтения.")
	var next_id := get_campaign_id() + 1
	if next_id > MAX_CAMPAIGN_ID:
		return _fail("Достигнут предел номера кампании.")
	var candidate := _data.duplicate(true)
	candidate["campaign"] = {
		"started": true,
		"next_night": 1,
		"highest_completed": 0,
		"id": next_id,
		"flags": {},
		"completed_minigames": [],
	}
	if not _commit_candidate(candidate):
		return false
	_pending_night_request.clear()
	return true


func prepare_night(number: int) -> bool:
	_pending_night_request.clear()
	if not can_continue() or number < 1 or number > 6:
		return _fail("Для запуска ночи от 1 до 6 сначала начните кампанию.")
	if not _data["unlocks"]["nights"].has(number):
		return _fail("Эта ночь ещё не открыта.")
	var path: String = NIGHT_CONFIG_PATHS[number]
	var config := ResourceLoader.load(path) as NightConfig
	if config == null:
		return _fail("Не удалось загрузить настройки ночи: %s" % path)
	_pending_night_request = {
		"config": config.duplicate(true),
		"campaign_id": get_campaign_id(),
		"night_number": number,
	}
	last_error = ""
	return true


func consume_night_request() -> Dictionary:
	var request := _pending_night_request
	_pending_night_request = {}
	if request.is_empty():
		return {}
	var config := request.get("config") as NightConfig
	if config == null:
		return {}
	request["config"] = config.duplicate(true)
	return request


func record_night_win(number: int, campaign_id: int) -> bool:
	if not _ensure_loaded() or _writes_locked:
		return _fail("Не удалось сохранить победу: данные недоступны для записи.")
	if not can_continue() or campaign_id != get_campaign_id() or number < 1 or number > 6:
		return _fail("Победа относится к другой кампании или некорректной ночи.")
	if not _data["unlocks"]["nights"].has(number):
		return _fail("Нельзя завершить закрытую ночь.")
	var candidate := _data.duplicate(true)
	var campaign: Dictionary = candidate["campaign"]
	campaign["highest_completed"] = maxi(int(campaign["highest_completed"]), number)
	campaign["next_night"] = maxi(int(campaign["next_night"]), mini(number + 1, 6))
	var nights: Array = candidate["unlocks"]["nights"]
	if number < 6 and not nights.has(number + 1):
		nights.append(number + 1)
		nights.sort()
	return _commit_candidate(candidate)


func unlock_achievement(stable_id: String) -> bool:
	if not _valid_identifier(stable_id):
		return _fail("Некорректный идентификатор достижения.")
	return _append_unlock("achievement_ids", stable_id)


func unlock_ending(ending_id: String) -> bool:
	if not ENDING_IDS.has(ending_id):
		return _fail("Неизвестный идентификатор концовки.")
	return _append_unlock("ending_ids", ending_id)


func unlock_star(star: int) -> bool:
	if star < 1 or star > 3:
		return _fail("Номер звезды должен быть от 1 до 3.")
	return _append_unlock("stars", star)


func discover_secret(night: int, stable_id: String) -> bool:
	if night < 1 or night > 6 or not _valid_identifier(stable_id):
		return _fail("Некорректный номер ночи или идентификатор секрета.")
	if not _ensure_writable():
		return false
	var candidate := _data.duplicate(true)
	var key := str(night)
	var secrets: Dictionary = candidate["unlocks"]["secrets"]
	if not secrets.has(key):
		secrets[key] = []
	var ids: Array = secrets[key]
	if not ids.has(stable_id):
		ids.append(stable_id)
	return _commit_candidate(candidate)


func complete_minigame(stable_id: String) -> bool:
	if not MINIGAME_IDS.has(stable_id):
		return _fail("Неизвестный идентификатор мини-игры.")
	if not _ensure_writable():
		return false
	var candidate := _data.duplicate(true)
	var lifetime: Array = candidate["unlocks"]["completed_minigames"]
	if not lifetime.has(stable_id):
		lifetime.append(stable_id)
	var campaign: Dictionary = candidate["campaign"]
	if bool(campaign["started"]):
		var current: Array = campaign["completed_minigames"]
		if not current.has(stable_id):
			current.append(stable_id)
	if candidate == _data:
		last_error = ""
		return true
	return _commit_candidate(candidate)


func set_campaign_flag(stable_id: String, value: bool) -> bool:
	if not _valid_identifier(stable_id):
		return _fail("Некорректный идентификатор флага кампании.")
	if not _ensure_writable():
		return false
	var candidate := _data.duplicate(true)
	candidate["campaign"]["flags"][stable_id] = value
	return _commit_candidate(candidate)


func set_custom_levels(levels: Dictionary) -> bool:
	if not _has_exact_keys(levels, CUSTOM_LEVEL_KEYS):
		return _fail("Для пользовательской сложности укажите уровни всех пяти персонажей.")
	var normalized: Dictionary = {}
	for key in CUSTOM_LEVEL_KEYS:
		var value: Variant = levels[key]
		if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > 20:
			return _fail("Уровень сложности должен быть целым числом от 0 до 20.")
		normalized[key] = int(value)
	if not _ensure_writable():
		return false
	var candidate := _data.duplicate(true)
	candidate["custom_levels"] = normalized
	return _commit_candidate(candidate)


func set_settings(settings: Dictionary) -> bool:
	for key in settings:
		if key != "language" and key != "fullscreen":
			return _fail("Неизвестная настройка: %s" % str(key))
	if settings.has("language") and (typeof(settings["language"]) != TYPE_STRING or not ["ru", "en"].has(settings["language"])):
		return _fail("Язык должен быть ru или en.")
	if settings.has("fullscreen") and typeof(settings["fullscreen"]) != TYPE_BOOL:
		return _fail("Настройка полного экрана должна быть логической.")
	if settings.is_empty():
		return true
	if not _ensure_writable():
		return false
	var candidate := _data.duplicate(true)
	for key in settings:
		candidate["settings"][key] = settings[key]
	return _commit_candidate(candidate)


func _append_unlock(collection: String, value: Variant) -> bool:
	if not _ensure_writable():
		return false
	var candidate := _data.duplicate(true)
	var values: Array = candidate["unlocks"][collection]
	if values.has(value):
		last_error = ""
		return true
	values.append(value)
	if collection == "stars":
		values.sort()
	return _commit_candidate(candidate)


func _ensure_loaded() -> bool:
	if _loaded:
		return true
	return load_save()


func _ensure_writable() -> bool:
	if not _ensure_loaded():
		return false
	if _writes_locked:
		return _fail("Запись отключена для защиты повреждённых данных или сохранения новой версии.")
	return true


func _commit_candidate(candidate: Dictionary) -> bool:
	if not _ensure_writable():
		return false
	var validation := _validate_document(candidate)
	if not bool(validation.get("ok", false)):
		return _fail("Некорректные данные сохранения: %s" % str(validation.get("error", "ошибка проверки")))
	if not _write_candidate(candidate):
		return false
	_data = candidate.duplicate(true)
	_recovered_from_backup = false
	last_error = ""
	save_changed.emit()
	return true


func _write_candidate(candidate: Dictionary) -> bool:
	var primary := save_path
	var backup := _backup_path()
	var temp := _temp_path(primary)
	var primary_exists := FileAccess.file_exists(primary)
	var primary_needs_backup := primary_exists and not _recovered_from_backup

	if primary_needs_backup:
		var current_result := _read_document(primary)
		if not bool(current_result.get("ok", false)):
			return _fail("Основное сохранение повреждено. Запись отменена.")
		var backup_temp := _temp_path(backup)
		if not _write_raw(backup_temp, JSON.stringify(current_result["data"], "\t")):
			return _fail("Не удалось создать временную резервную копию.")
		var verified_backup := _read_document(backup_temp)
		if not bool(verified_backup.get("ok", false)):
			return _fail("Не удалось проверить резервную копию.")
		if not _replace_from_temp(backup_temp, backup):
			return _fail("Не удалось безопасно обновить резервную копию.")

	if not _write_raw(temp, JSON.stringify(candidate, "\t")):
		return _fail("Не удалось создать временный файл сохранения.")
	var verified_temp := _read_document(temp)
	if not bool(verified_temp.get("ok", false)):
		return _fail("Не удалось проверить временное сохранение.")
	if not _replace_from_temp(temp, primary):
		return _fail("Не удалось безопасно обновить основное сохранение.")
	return true


func _replace_from_temp(temp_path: String, destination_path: String) -> bool:
	var temp_absolute := _absolute_path(temp_path)
	var destination_absolute := _absolute_path(destination_path)
	if not FileAccess.file_exists(temp_path):
		return false
	if not FileAccess.file_exists(destination_path):
		return DirAccess.rename_absolute(temp_absolute, destination_absolute) == OK
	var previous_path := destination_path + ".previous." + str(Time.get_ticks_usec())
	var suffix := 0
	while FileAccess.file_exists(previous_path):
		suffix += 1
		previous_path = destination_path + ".previous." + str(Time.get_ticks_usec()) + "." + str(suffix)
	var previous_absolute := _absolute_path(previous_path)
	if DirAccess.rename_absolute(destination_absolute, previous_absolute) != OK:
		return false
	if DirAccess.rename_absolute(temp_absolute, destination_absolute) != OK:
		# Restore old destination if installing the validated temp fails.
		DirAccess.rename_absolute(previous_absolute, destination_absolute)
		return false
	DirAccess.remove_absolute(previous_absolute)
	return true


func _write_raw(path: String, contents: String) -> bool:
	var absolute := _absolute_path(path)
	var parent := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent) != OK and not DirAccess.dir_exists_absolute(parent):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "future": false, "error": "open failed"}
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {"ok": false, "future": false, "error": "file exceeds size limit"}
	var contents := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return {"ok": false, "future": false, "error": "read failed"}
	var parser := JSON.new()
	if parser.parse(contents) != OK:
		return {"ok": false, "future": false, "error": parser.get_error_message()}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "future": false, "error": "root must be an object"}
	# Future payloads may contain values unsupported by this version's schema.
	var version: Variant = parser.data.get("schema_version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return {"ok": false, "future": false, "error": "schema_version must be an integer"}
	var version_number := float(version)
	if not is_finite(version_number) or floor(version_number) != version_number:
		return {"ok": false, "future": false, "error": "schema_version must be an integer"}
	if version_number > SCHEMA_VERSION:
		return {"ok": false, "future": true, "error": "newer schema version"}
	var normalized := _normalize_json_value(parser.data)
	if not bool(normalized.get("ok", false)) or typeof(normalized.get("value")) != TYPE_DICTIONARY:
		return {"ok": false, "future": false, "error": "JSON contains unsupported numeric values"}
	var raw: Dictionary = normalized["value"]
	if not raw.has("schema_version") or typeof(raw["schema_version"]) != TYPE_INT:
		return {"ok": false, "future": false, "error": "schema_version must be an integer"}
	if int(raw["schema_version"]) > SCHEMA_VERSION:
		return {"ok": false, "future": true, "error": "newer schema version"}
	var validation := _validate_document(raw)
	return {
		"ok": bool(validation.get("ok", false)),
		"future": false,
		"data": raw,
		"error": str(validation.get("error", "")),
	}


func _validate_document(data: Dictionary) -> Dictionary:
	if not _has_exact_keys(data, ["schema_version", "campaign", "unlocks", "custom_levels", "settings"]):
		return _invalid("top-level keys do not match schema")
	if typeof(data["schema_version"]) != TYPE_INT or int(data["schema_version"]) != SCHEMA_VERSION:
		return _invalid("unsupported schema version")
	if typeof(data["campaign"]) != TYPE_DICTIONARY or typeof(data["unlocks"]) != TYPE_DICTIONARY:
		return _invalid("campaign and unlocks must be objects")
	if typeof(data["custom_levels"]) != TYPE_DICTIONARY or typeof(data["settings"]) != TYPE_DICTIONARY:
		return _invalid("custom_levels and settings must be objects")
	var campaign: Dictionary = data["campaign"]
	if not _has_exact_keys(campaign, ["started", "next_night", "highest_completed", "id", "flags", "completed_minigames"]):
		return _invalid("campaign keys do not match schema")
	if typeof(campaign["started"]) != TYPE_BOOL or typeof(campaign["next_night"]) != TYPE_INT:
		return _invalid("campaign started/next_night types are invalid")
	if typeof(campaign["highest_completed"]) != TYPE_INT or typeof(campaign["id"]) != TYPE_INT:
		return _invalid("campaign completion/id types are invalid")
	var next_night := int(campaign["next_night"])
	var highest_completed := int(campaign["highest_completed"])
	var campaign_id := int(campaign["id"])
	if next_night < 1 or next_night > 6 or highest_completed < 0 or highest_completed > 6:
		return _invalid("campaign night is out of range")
	if campaign_id < 0 or campaign_id > MAX_CAMPAIGN_ID:
		return _invalid("campaign id is out of range")
	if next_night > mini(highest_completed + 1, 6):
		return _invalid("campaign checkpoint skips unfinished nights")
	if not bool(campaign["started"]) and (next_night != 1 or highest_completed != 0):
		return _invalid("unstarted campaign contains progress")
	if typeof(campaign["flags"]) != TYPE_DICTIONARY or not _valid_bool_map(campaign["flags"]):
		return _invalid("campaign flags must map valid IDs to booleans")
	if not _valid_unique_string_array(campaign["completed_minigames"], MINIGAME_IDS):
		return _invalid("campaign minigame IDs are invalid")

	var unlocks: Dictionary = data["unlocks"]
	if not _has_exact_keys(unlocks, ["nights", "stars", "achievement_ids", "ending_ids", "secrets", "completed_minigames"]):
		return _invalid("unlock keys do not match schema")
	if not _valid_unique_int_array(unlocks["nights"], 1, 6) or not unlocks["nights"].has(1):
		return _invalid("unlocked nights must be unique integers containing night 1")
	if not unlocks["nights"].has(next_night):
		return _invalid("campaign checkpoint night is locked")
	if not _valid_unique_int_array(unlocks["stars"], 1, 3):
		return _invalid("stars must be unique integers from 1 to 3")
	if not _valid_unique_id_array(unlocks["achievement_ids"]):
		return _invalid("achievement IDs are invalid")
	if not _valid_unique_string_array(unlocks["ending_ids"], ENDING_IDS):
		return _invalid("ending IDs are invalid")
	if not _valid_unique_string_array(unlocks["completed_minigames"], MINIGAME_IDS):
		return _invalid("minigame IDs are invalid")
	if typeof(unlocks["secrets"]) != TYPE_DICTIONARY:
		return _invalid("secrets must be an object")
	for night_key in unlocks["secrets"]:
		if typeof(night_key) != TYPE_STRING or not ["1", "2", "3", "4", "5", "6"].has(night_key):
			return _invalid("secret night key is invalid")
		if not _valid_unique_id_array(unlocks["secrets"][night_key]):
			return _invalid("secret IDs are invalid")

	var custom_levels: Dictionary = data["custom_levels"]
	if not _has_exact_keys(custom_levels, CUSTOM_LEVEL_KEYS):
		return _invalid("custom level keys do not match schema")
	for key in CUSTOM_LEVEL_KEYS:
		if typeof(custom_levels[key]) != TYPE_INT or int(custom_levels[key]) < 0 or int(custom_levels[key]) > 20:
			return _invalid("custom level out of range")

	var settings: Dictionary = data["settings"]
	if not _has_exact_keys(settings, ["language", "fullscreen"]):
		return _invalid("settings keys do not match schema")
	if typeof(settings["language"]) != TYPE_STRING or not ["ru", "en"].has(settings["language"]):
		return _invalid("language is unsupported")
	if typeof(settings["fullscreen"]) != TYPE_BOOL:
		return _invalid("fullscreen must be boolean")
	return {"ok": true, "error": ""}


func _fresh_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"campaign": {
			"started": false,
			"next_night": 1,
			"highest_completed": 0,
			"id": 0,
			"flags": {},
			"completed_minigames": [],
		},
		"unlocks": {
			"nights": [1],
			"stars": [],
			"achievement_ids": [],
			"ending_ids": [],
			"secrets": {},
			"completed_minigames": [],
		},
		"custom_levels": {
			"berry": 0,
			"blacky": 0,
			"dog": 0,
			"sann": 0,
			"old_creeper": 0,
		},
		"settings": {
			"language": "ru",
			"fullscreen": true,
		},
	}


func _valid_bool_map(value: Dictionary) -> bool:
	if value.size() > MAX_COLLECTION_ITEMS:
		return false
	for key in value:
		if typeof(key) != TYPE_STRING or not _valid_identifier(key) or typeof(value[key]) != TYPE_BOOL:
			return false
	return true


func _valid_unique_int_array(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	if value.size() > MAX_COLLECTION_ITEMS:
		return false
	var seen: Array = []
	for item in value:
		if typeof(item) != TYPE_INT or int(item) < minimum or int(item) > maximum or seen.has(item):
			return false
		seen.append(item)
	return true


func _valid_unique_id_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	if value.size() > MAX_COLLECTION_ITEMS:
		return false
	var seen: Array = []
	for item in value:
		if typeof(item) != TYPE_STRING or not _valid_identifier(item) or seen.has(item):
			return false
		seen.append(item)
	return true


func _valid_unique_string_array(value: Variant, allowed: Array) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	if value.size() > MAX_COLLECTION_ITEMS:
		return false
	var seen: Array = []
	for item in value:
		if typeof(item) != TYPE_STRING or not allowed.has(item) or seen.has(item):
			return false
		seen.append(item)
	return true


func _valid_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var first := value.unicode_at(0)
	if first < 97 or first > 122:
		return false
	for index in range(1, value.length()):
		var codepoint := value.unicode_at(index)
		if not ((codepoint >= 97 and codepoint <= 122) or (codepoint >= 48 and codepoint <= 57) or codepoint == 95):
			return false
	return true


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _normalize_json_value(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		if int(value) < -MAX_CAMPAIGN_ID or int(value) > MAX_CAMPAIGN_ID:
			return {"ok": false}
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if not is_finite(number) or number < -MAX_CAMPAIGN_ID or number > MAX_CAMPAIGN_ID or floor(number) != number:
			return {"ok": false}
		return {"ok": true, "value": int(number)}
	if typeof(value) == TYPE_ARRAY:
		var normalized_array: Array = []
		for item in value:
			var array_child := _normalize_json_value(item)
			if not bool(array_child.get("ok", false)):
				return {"ok": false}
			normalized_array.append(array_child["value"])
		return {"ok": true, "value": normalized_array}
	if typeof(value) == TYPE_DICTIONARY:
		var normalized_dictionary: Dictionary = {}
		for key in value:
			var dictionary_child := _normalize_json_value(value[key])
			if not bool(dictionary_child.get("ok", false)):
				return {"ok": false}
			normalized_dictionary[key] = dictionary_child["value"]
		return {"ok": true, "value": normalized_dictionary}
	return {"ok": true, "value": value}


func _backup_path() -> String:
	return save_path + ".bak"


func _temp_path(path: String) -> String:
	return path + ".tmp"


func _absolute_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _set_error(message: String) -> void:
	last_error = message
	save_error.emit(message)


func _fail(message: String) -> bool:
	_set_error(message)
	return false
