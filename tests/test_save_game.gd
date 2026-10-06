extends SceneTree

## Isolated persistence and campaign-checkpoint tests.
## Run with Godot 4.4.1: --headless --path <project> --script res://tests/test_save_game.gd

const SAVE_SCRIPT := preload("res://scripts/save_game.gd")
const TEST_ROOT := "user://save_game_tests"

var _checks := 0
var _failures := 0
var _sequence := 0
var _stores: Array[Node] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_fresh_profile_and_round_trip()
	await _test_campaign_reset_preserves_collections()
	await _test_night_checkpoint_and_resource_requests()
	await _test_stale_campaign_and_win_idempotence()
	await _test_recovery_and_corruption_protection()
	await _test_invalid_checkpoint_files_are_protected()
	await _test_future_schema_is_read_only()
	await _test_failed_write_does_not_change_memory()
	await _test_menu_night_checkpoint_flow()
	for store in _stores:
		if is_instance_valid(store):
			store.free()
	print("SAVE_GAME_TESTS checks=%d failures=%d" % [_checks, _failures])
	call_deferred("quit", 1 if _failures > 0 else 0)


func _test_fresh_profile_and_round_trip() -> void:
	var path := _new_path("round_trip")
	var store := _new_store(path)
	_check(not store.can_continue(), "fresh profile cannot continue a campaign")
	_check(store.get_checkpoint_night() == 1, "fresh profile reports night one as default checkpoint")
	_check(store.consume_night_request().is_empty(), "fresh profile has no pending night request")
	_check(not FileAccess.file_exists(path), "loading a fresh profile does not write user data")
	_check(store.start_new_campaign(), "fresh profile starts a campaign")
	_check(store.can_continue() and store.get_campaign_id() == 1, "campaign start persists its generation")
	_check(FileAccess.file_exists(path), "campaign start writes a save file")
	var reloaded := _load_store(path)
	_check(reloaded.can_continue() and reloaded.get_campaign_id() == 1, "campaign survives a new save-node instance")
	_check(reloaded.get_checkpoint_night() == 1, "reloaded campaign resumes at night one")
	_check(reloaded.get_snapshot() == store.get_snapshot(), "save snapshot round-trips without data loss")
	_cleanup_store(path)


func _test_campaign_reset_preserves_collections() -> void:
	var path := _new_path("new_campaign")
	var store := _new_store(path)
	store.start_new_campaign()
	store.set_campaign_flag("saw_intro", true)
	store.record_night_win(1, store.get_campaign_id())
	store.unlock_star(2)
	store.unlock_achievement("first_shift")
	store.unlock_ending("neutral_ending")
	store.discover_secret(1, "hidden_desk")
	store.complete_minigame("computer")
	store.set_custom_levels({"berry": 4, "blacky": 3, "dog": 2, "sann": 1, "old_creeper": 5})
	store.set_settings({"language": "en", "fullscreen": false})
	var before: Dictionary = store.get_snapshot()
	var old_id: int = store.get_campaign_id()
	_check(store.start_new_campaign(), "New Game starts a clean campaign")
	var after: Dictionary = store.get_snapshot()
	_check(store.get_campaign_id() == old_id + 1, "new campaign receives a fresh generation ID")
	_check(after["campaign"] == {"started": true, "next_night": 1, "highest_completed": 0, "id": old_id + 1, "flags": {}, "completed_minigames": []}, "new campaign clears checkpoint, campaign flags and campaign-local minigames")
	_check(after["unlocks"] == before["unlocks"], "new campaign preserves stars, achievements, endings, secrets, lifetime minigames and unlocked nights")
	_check(after["custom_levels"] == before["custom_levels"], "new campaign preserves custom difficulty settings")
	_check(after["settings"] == before["settings"], "new campaign preserves player settings")
	_check(store.get_checkpoint_night() == 1, "new campaign resets Continue checkpoint even while lifetime night unlocks remain")
	_cleanup_store(path)


func _test_night_checkpoint_and_resource_requests() -> void:
	var path := _new_path("night_progress")
	var store := _new_store(path)
	store.start_new_campaign()
	var campaign_id: int = store.get_campaign_id()
	_check(store.prepare_night(1), "unlocked night one can be prepared")
	var first_request: Dictionary = store.consume_night_request()
	_check(first_request.get("night_number", 0) == 1 and first_request.get("campaign_id", 0) == campaign_id, "night request carries night and campaign identity")
	var night_1 = first_request.get("config")
	_check(night_1 != null and night_1.night_number == 1 and night_1.sann_level == 1, "night one request uses configured night-one Resource")
	_check(store.consume_night_request().is_empty(), "night request can only be consumed once")
	var before_manual_night: Dictionary = store.get_snapshot()
	var manual_config = load("res://resources/night_3.tres")
	_check(manual_config != null and manual_config.night_number == 3, "manual night config remains available to scene without progression request")
	_check(store.get_snapshot() == before_manual_night, "loading a manual scene config does not change campaign checkpoint")
	_check(store.record_night_win(1, campaign_id), "winning night one stores a between-night checkpoint")
	_check(store.can_continue() and store.get_checkpoint_night() == 2, "night-one win opens night two")
	_check(store.prepare_night(2), "checkpoint night can be prepared for Continue")
	var second_request: Dictionary = store.consume_night_request()
	var night_2 = second_request.get("config")
	_check(second_request.get("night_number", 0) == 2 and night_2 != null, "Continue request chooses checkpoint night two")
	_check(night_2.night_number == 2 and night_2.berry_level == 3 and night_2.blacky_level == 2 and night_2.sann_level == 4 and night_2.old_creeper_level == 3, "night-two request loads memo profile levels")
	_check(store.can_continue() and store.get_checkpoint_night() == 2, "preparing or consuming a night does not save mid-night state")
	var expected_levels := {
		2: [3, 2, 0, 4, 3],
		3: [5, 7, 0, 6, 5],
		4: [11, 9, 5, 10, 9],
		5: [13, 11, 12, 14, 15],
		6: [17, 15, 16, 17, 18],
	}
	for number in range(2, 7):
		_check(store.record_night_win(number, campaign_id), "night %d win is accepted after unlock" % number)
		_check(store.prepare_night(number), "night %d profile is loadable" % number)
		var request: Dictionary = store.consume_night_request()
		var config = request.get("config")
		_check(config != null and config.night_number == number, "night %d uses matching Resource profile" % number)
		var levels: Array = expected_levels[number]
		_check(config.berry_level == levels[0] and config.blacky_level == levels[1] and config.dog_level == levels[2] and config.sann_level == levels[3] and config.old_creeper_level == levels[4], "night %d profile matches memo difficulty row" % number)
		_check(store.get_checkpoint_night() == (number if number == 6 else number + 1), "night %d checkpoint advances only on win" % number)
	_check(store.get_snapshot()["unlocks"]["nights"] == [1, 2, 3, 4, 5, 6], "progression unlocks at most configured nights one through six")
	_check(not store.prepare_night(7), "night seven is rejected; campaign has no automatic extra night")
	_cleanup_store(path)


func _test_stale_campaign_and_win_idempotence() -> void:
	var path := _new_path("generation")
	var store := _new_store(path)
	store.start_new_campaign()
	var stale_id: int = store.get_campaign_id()
	store.record_night_win(1, stale_id)
	var before_replay: Dictionary = store.get_snapshot()
	_check(store.record_night_win(1, stale_id), "replaying a completed night win remains accepted")
	_check(store.get_snapshot() == before_replay, "replaying same-night win is idempotent and cannot advance checkpoint")
	store.start_new_campaign()
	var before_stale: Dictionary = store.get_snapshot()
	_check(not store.record_night_win(1, stale_id), "win from a stale campaign generation is rejected")
	_check(store.get_snapshot() == before_stale, "stale win cannot modify a newer campaign")
	_check(not store.record_night_win(3, store.get_campaign_id()), "locked night cannot be recorded as won")
	_check(not store.record_night_win(0, store.get_campaign_id()), "out-of-range night cannot be recorded as won")
	_cleanup_store(path)


func _test_recovery_and_corruption_protection() -> void:
	var recovery_path := _new_path("recovery")
	var initial := _new_store(recovery_path)
	initial.start_new_campaign()
	initial.unlock_achievement("preserve_me")
	var valid_document := JSON.stringify(initial.get_snapshot())
	_write_text(recovery_path + ".bak", valid_document)
	_write_text(recovery_path, "{ broken json")
	var recovered := _load_store(recovery_path)
	_check(recovered.can_continue() and recovered.get_snapshot()["unlocks"]["achievement_ids"] == ["preserve_me"], "valid backup recovers corrupt primary")
	_check(not recovered.last_error.is_empty() and FileAccess.file_exists(recovery_path + ".bak"), "recovery reports warning and preserves backup")
	_write_text(recovery_path + ".bak", "{ invalid backup")
	_write_text(recovery_path, "{ invalid primary")
	var protected := _load_store(recovery_path)
	var protected_snapshot: Dictionary = protected.get_snapshot()
	_check(not protected.can_continue() and not protected.last_error.is_empty(), "two corrupt files disable continuation and report the error")
	_check(not protected.start_new_campaign(), "two corrupt files block overwrite through New Game")
	_check(protected.get_snapshot() == protected_snapshot, "blocked overwrite leaves in-memory fallback unchanged")
	_check(FileAccess.get_file_as_string(recovery_path) == "{ invalid primary" and FileAccess.get_file_as_string(recovery_path + ".bak") == "{ invalid backup", "two corrupt files remain byte-for-byte untouched")
	_cleanup_store(recovery_path)


func _test_future_schema_is_read_only() -> void:
	var path := _new_path("future_schema")
	var seed_path := _new_path("future_seed")
	var source := _new_store(seed_path)
	source.start_new_campaign()
	var future: Dictionary = source.get_snapshot()
	var backup_text := JSON.stringify(future)
	future["schema_version"] = 2
	future["settings"]["volume"] = 0.5
	var future_text := JSON.stringify(future)
	_write_text(path, future_text)
	_write_text(path + ".bak", backup_text)
	var store := _load_store(path)
	_check(not store.last_error.is_empty(), "newer schema reports a read-only warning")
	_check(not store.start_new_campaign(), "newer schema blocks writes")
	_check(not store.record_night_win(1, source.get_campaign_id()), "future payload blocks victory writes despite valid old backup")
	_check(not store.unlock_star(1), "future payload blocks unlock writes")
	_check(not store.set_settings({"language": "en"}), "future payload blocks settings writes")
	_check(FileAccess.get_file_as_string(path) == future_text, "newer schema file stays unchanged")
	_check(FileAccess.get_file_as_string(path + ".bak") == backup_text, "valid older backup stays unchanged beside future fractional payload")
	_cleanup_store(path)
	_cleanup_store(seed_path)


func _test_invalid_checkpoint_files_are_protected() -> void:
	var seed_path := _new_path("checkpoint_seed")
	var seed := _new_store(seed_path)
	seed.start_new_campaign()
	var malformed_checkpoint_path := _new_path("invalid_checkpoint")
	var malformed_checkpoint: Dictionary = seed.get_snapshot()
	malformed_checkpoint["campaign"]["next_night"] = 6
	var malformed_checkpoint_text := JSON.stringify(malformed_checkpoint)
	_write_text(malformed_checkpoint_path, malformed_checkpoint_text)
	var invalid_checkpoint := _load_store(malformed_checkpoint_path)
	_check(not invalid_checkpoint.can_continue() and not invalid_checkpoint.last_error.is_empty(), "checkpoint cannot skip to night six before completing night one")
	_check(not invalid_checkpoint.start_new_campaign(), "malformed checkpoint blocks campaign overwrite")
	_check(FileAccess.get_file_as_string(malformed_checkpoint_path) == malformed_checkpoint_text, "malformed checkpoint file remains unchanged")

	var unlocked_path := _new_path("locked_checkpoint")
	var completed_path := _new_path("completed_n1")
	var completed_n1 := _new_store(completed_path)
	completed_n1.start_new_campaign()
	completed_n1.record_night_win(1, completed_n1.get_campaign_id())
	var locked_checkpoint: Dictionary = completed_n1.get_snapshot()
	locked_checkpoint["unlocks"]["nights"] = [1]
	var locked_checkpoint_text := JSON.stringify(locked_checkpoint)
	_write_text(unlocked_path, locked_checkpoint_text)
	var locked := _load_store(unlocked_path)
	_check(not locked.can_continue() and not locked.last_error.is_empty(), "checkpoint night must also appear in unlocked nights")
	_check(not locked.start_new_campaign(), "locked checkpoint blocks campaign overwrite")
	_check(FileAccess.get_file_as_string(unlocked_path) == locked_checkpoint_text, "locked checkpoint file remains unchanged")
	_cleanup_store(seed_path)
	_cleanup_store(completed_path)
	_cleanup_store(malformed_checkpoint_path)
	_cleanup_store(unlocked_path)


func _test_failed_write_does_not_change_memory() -> void:
	var blocker := TEST_ROOT + "/write_failure"
	_cleanup_path(blocker)
	_check(_write_text(blocker, "not a directory"), "write-failure fixture creates parent-path blocker")
	var store = SAVE_SCRIPT.new()
	store.save_path = blocker + "/slot.json"
	store.load_save()
	_stores.append(store)
	var before: Dictionary = store.get_snapshot()
	_check(not store.start_new_campaign(), "failed disk write is returned to caller")
	_check(store.get_snapshot() == before and not store.can_continue(), "failed disk write leaves RAM state unchanged")
	_check(not store.last_error.is_empty(), "failed disk write reports an error")
	store.free()
	_cleanup_path(blocker)


func _test_menu_night_checkpoint_flow() -> void:
	var save_service: Node = root.get_node("SaveGame")
	var previous_path: String = save_service.save_path
	var path := _new_path("menu_flow")
	_cleanup_store(path)
	save_service.save_path = path
	save_service.load_save()
	await _show_menu()
	var menu: Node = current_scene
	menu._on_new_game_button_pressed()
	await _wait_for_current_scene("Night")
	var first_night: Node = current_scene
	_check(first_night.is_campaign_run() and first_night.config.night_number == 1, "New Game handler launches night one as campaign run")
	_check(first_night.config.berry_level == 0 and first_night.config.blacky_level == 0 and first_night.config.dog_level == 0 and first_night.config.sann_level == 1 and first_night.config.old_creeper_level == 0, "campaign night one uses memo's active-character profile")
	first_night.hours = 6
	first_night.minutes = 59
	first_night.begin_night()
	first_night.advance(1.0)
	_check(first_night.phase == first_night.Phase.WON and save_service.get_checkpoint_night() == 2, "07:00 win records night-one checkpoint before another AI check")
	await _show_menu()
	menu = current_scene
	menu._on_continue_button_pressed()
	await _wait_for_current_scene("Night")
	var second_night: Node = current_scene
	_check(second_night.is_campaign_run() and second_night.config.night_number == 2, "Continue handler opens saved night-two profile")
	_check(second_night.config.berry_level == 3 and second_night.config.blacky_level == 2 and second_night.config.sann_level == 4 and second_night.config.old_creeper_level == 3, "Continue applies night-two character levels")
	second_night._finish(false, "test_loss")
	_check(save_service.get_checkpoint_night() == 2, "loss leaves between-night checkpoint unchanged")
	await _show_menu()
	menu = current_scene
	menu._on_continue_button_pressed()
	await _wait_for_current_scene("Night")
	var replay: Node = current_scene
	_check(replay.config.night_number == 2 and replay.is_campaign_run(), "Continue after loss replays the same checkpoint night")
	replay._finish(false, "test_replay_loss")
	var before_direct: Dictionary = save_service.get_snapshot()
	var direct_packed: PackedScene = load("res://scenes/Night.tscn")
	var direct_night: Node = direct_packed.instantiate()
	direct_night.config = load("res://resources/night_3.tres")
	root.add_child(direct_night)
	current_scene = direct_night
	await process_frame
	_check(not direct_night.is_campaign_run() and direct_night.config.night_number == 3, "manual Night scene config is not mistaken for a campaign request")
	direct_night._finish(true, "manual_test")
	_check(save_service.get_snapshot() == before_direct and save_service.get_checkpoint_night() == 2, "manual scene win cannot write campaign progress")
	await _show_menu()
	menu = current_scene
	menu._on_new_game_button_pressed()
	await _wait_for_current_scene("Night")
	var restarted: Node = current_scene
	_check(restarted.config.night_number == 1 and restarted.is_campaign_run(), "New Game restarts campaign from night one")
	_check(save_service.get_checkpoint_night() == 1, "New Game resets current campaign checkpoint")
	await _show_menu()
	current_scene.queue_free()
	await process_frame
	_cleanup_store(path)
	save_service.save_path = previous_path


func _show_menu() -> void:
	var current := current_scene
	if current != null:
		current.queue_free()
		await process_frame
	var packed: PackedScene = load("res://scenes/MainMenu.tscn")
	var menu := packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame


func _wait_for_current_scene(expected_name: String) -> void:
	for _attempt in range(30):
		await process_frame
		var current := current_scene
		if current != null and ((expected_name == "Night" and current.has_method("is_campaign_run")) or (expected_name == "MainMenu" and current.get_script() == load("res://scripts/Main_menu.gd"))):
			return
	_check(false, "scene transition reaches %s" % expected_name)


func _new_store(path: String) -> Node:
	_cleanup_store(path)
	return _load_store(path)


func _load_store(path: String) -> Node:
	var store = SAVE_SCRIPT.new()
	store.save_path = path
	store.load_save()
	_stores.append(store)
	return store


func _new_path(label: String) -> String:
	_sequence += 1
	return "%s/%s_%d.json" % [TEST_ROOT, label, _sequence]


func _write_text(path: String, text: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var parent := absolute.get_base_dir()
	var make_error := DirAccess.make_dir_recursive_absolute(parent)
	if make_error != OK and not DirAccess.dir_exists_absolute(parent):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok


func _cleanup_store(path: String) -> void:
	for candidate in [path, path + ".bak", path + ".tmp", path + ".bak.tmp", path + ".previous"]:
		_cleanup_path(candidate)


func _cleanup_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	elif DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
