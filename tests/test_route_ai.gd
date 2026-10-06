extends SceneTree

## Integration checks for the route-driven characters, controls and shocker.
## Run with Godot 4.4.1: --headless --path <project> --script res://tests/test_route_ai.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_disabled_routes_stay_at_origins()
	await _test_dog_requires_and_resets_door_hold()
	await _test_berry_wakes_and_uses_door()
	await _test_blacky_vent_branches_and_fan_side()
	await _test_old_creeper_stages_shock_and_timeout()
	await _test_berry_and_blacky_attack_presentations()
	await _test_remote_fan_and_camera_shocker_controls()
	await _test_terminal_phase_stops_all_route_ai()
	print("ROUTE_AI_TESTS checks=%d failures=%d" % [_checks, _failures])
	call_deferred("quit", 1 if _failures > 0 else 0)


func _test_disabled_routes_stay_at_origins() -> void:
	var config := _new_config()
	var night := await _spawn_night(config)
	var manager: Node = root.get_node("AnimatronicMgnt")
	_check(night.route_ai == night.get_node("Animatronics/RouteAI"), "Night uses its scene-owned RouteAI node")
	_check(manager.get_dog_pos() == manager.Rooms.WORKSHOP, "Dog starts at route origin")
	_check(manager.get_berry_pos() == manager.Rooms.STAGE, "Berry starts at route origin")
	_check(manager.get_blacky_pos() == manager.Rooms.STAGE, "Blacky starts at route origin")
	_check(manager.get_old_creeper_pos() == manager.Rooms.EXTRA_WORKSHOP, "Old Creeper starts at route origin")
	var warnings := [0]
	night.route_ai.warning_started.connect(func(_character: int, _room: int) -> void: warnings[0] += 1)
	night.begin_night()
	# Exercise far beyond each configured movement interval without relying on frame timing.
	night.route_ai.advance(100.0)
	_check(manager.get_dog_pos() == manager.Rooms.WORKSHOP, "level-zero Dog never moves")
	_check(manager.get_berry_pos() == manager.Rooms.STAGE and not manager.is_berry_on(), "level-zero Berry stays asleep at its origin")
	_check(manager.get_blacky_pos() == manager.Rooms.STAGE and not manager.is_blacky_on(), "level-zero Blacky stays asleep at its origin")
	_check(manager.get_old_creeper_pos() == manager.Rooms.EXTRA_WORKSHOP and manager.old_creeper_state == manager.Old_creeper_states.STATE1, "level-zero Old Creeper stays at its first state")
	_check(warnings[0] == 0, "inactive route characters emit no warnings")
	await _release_night(night)


func _test_dog_requires_and_resets_door_hold() -> void:
	var config := _new_config()
	config.dog_level = 20
	var night := await _spawn_night(config)
	var manager: Node = root.get_node("AnimatronicMgnt")
	var warnings: Array[int] = []
	var defended: Array[int] = []
	var attacks: Array[int] = []
	night.route_ai.warning_started.connect(func(character: int, room: int) -> void:
		if character == manager.Animatronics.DOG: warnings.append(room)
	)
	night.route_ai.defended.connect(func(character: int, _room: int) -> void:
		if character == manager.Animatronics.DOG: defended.append(character)
	)
	night.route_ai.attack_requested.connect(func(character: int) -> void:
		if character == manager.Animatronics.DOG: attacks.append(character)
	)
	night.begin_night()
	_force_next_warning(night, manager.Animatronics.DOG)
	_check(warnings == [manager.Rooms.HALLWAY], "Dog follows workshop to main hall to hallway before warning")
	_check(night.route_ai.get_warning_room(manager.Animatronics.DOG) == manager.Rooms.HALLWAY, "Dog warning identifies the hallway")
	night.request_fan_toggle(0)
	night.advance(1.1)
	_check(defended.is_empty() and night.route_ai.get_warning_remaining(manager.Animatronics.DOG) > 0.0, "a fan does not defend Dog")
	night.request_door_toggle()
	night.advance(0.5)
	night.request_door_toggle()
	night.advance(0.05)
	night.request_door_toggle()
	night.advance(0.5)
	_check(defended.is_empty(), "opening the door resets Dog's partial defense hold")
	night.advance(0.5)
	_check(defended.size() == 1 and manager.get_dog_pos() == manager.Rooms.WORKSHOP, "one continuous second behind the door defends and resets Dog")
	_check(attacks.is_empty() and night.phase == night.Phase.RUNNING, "successful Dog defense prevents attack and keeps the night running")
	await _release_night(night)

	var miss_config := _new_config()
	miss_config.dog_level = 20
	var miss := await _spawn_night(miss_config)
	miss.begin_night()
	_force_next_warning(miss, manager.Animatronics.DOG)
	miss.request_fan_toggle(1)
	miss.advance(miss.config.dog_warning_seconds + 0.2)
	_check(miss.phase == miss.Phase.LOST and _last_outcome_reason(miss) == "dog", "missing Dog's door warning causes its own defeat")
	await _release_night(miss)


func _test_berry_wakes_and_uses_door() -> void:
	var config := _new_config()
	config.berry_level = 20
	var night := await _spawn_night(config)
	var manager: Node = root.get_node("AnimatronicMgnt")
	var rooms: Array[int] = []
	night.route_ai.warning_started.connect(func(character: int, room: int) -> void:
		if character == manager.Animatronics.BERRY: rooms.append(room)
	)
	night.begin_night()
	_force_next_warning(night, manager.Animatronics.BERRY)
	_check(manager.is_berry_on(), "Berry raises from the stage before starting its route")
	_check(manager.get_berry_pos() == manager.Rooms.HALLWAY and rooms == [manager.Rooms.HALLWAY], "Berry follows its route through main hall, kitchen and workshop to hallway")
	_check(night.request_door_toggle(), "door can close during Berry's warning")
	night.advance(1.01)
	_check(night.phase == night.Phase.RUNNING and manager.get_berry_pos() == manager.Rooms.STAGE and not manager.is_berry_on(), "door hold repels Berry to its stage origin and lowers its posture")
	await _release_night(night)


func _test_blacky_vent_branches_and_fan_side() -> void:
	var config := _new_config()
	config.blacky_level = 20
	var night := await _spawn_night(config)
	var manager: Node = root.get_node("AnimatronicMgnt")
	var branches: Dictionary = {}
	# The branch is genuinely randomized. Fixed test seeds make both authored branches reproducible.
	for seed in range(1, 129):
		manager.reset_for_night()
		night.route_ai.reset(config, night)
		night.route_ai._rng.seed = seed
		night.begin_night()
		_force_next_warning(night, manager.Animatronics.BLACKY)
		var branch_room: int = manager.get_blacky_pos()
		if branch_room in [manager.Rooms.LEFT_VENT, manager.Rooms.RIGHT_VENT]:
			branches[branch_room] = true
		if branches.size() == 2:
			break
		# Return to INTRO between deterministic branch samples.
		night.phase = night.Phase.INTRO
		manager.reset_for_night()
	_check(branches.has(manager.Rooms.LEFT_VENT) and branches.has(manager.Rooms.RIGHT_VENT), "Blacky route exposes both left- and right-vent branches")
	await _release_night(night)

	for branch in [manager.Rooms.LEFT_VENT, manager.Rooms.RIGHT_VENT]:
		var branch_config := _new_config()
		branch_config.blacky_level = 20
		var branch_night := await _spawn_night(branch_config)
		var original_path: Array = manager.routes.blacky_path.duplicate(true)
		manager.routes.blacky_path = [manager.Rooms.STAGE, manager.Rooms.MAIN_HALL, manager.Rooms.ENTRANCE, manager.Rooms.KITCHEN, manager.Rooms.HALLWAY_PASSAGE, [branch], manager.Rooms.OFFICE]
		manager.reset_for_night()
		branch_night.route_ai.reset(branch_config, branch_night)
		branch_night.begin_night()
		_force_next_warning(branch_night, manager.Animatronics.BLACKY)
		_check(manager.get_blacky_pos() == branch and branch_night.route_ai.get_warning_room(manager.Animatronics.BLACKY) == branch, "Blacky warns from selected vent %d" % branch)
		var correct_side := 0 if branch == manager.Rooms.LEFT_VENT else 1
		var wrong_side := 1 - correct_side
		branch_night.request_fan_toggle(wrong_side)
		branch_night.advance(1.1)
		_check(manager.get_blacky_pos() == branch and branch_night.phase == branch_night.Phase.RUNNING, "opposite fan does not defend Blacky in vent %d" % branch)
		branch_night.request_fan_toggle(correct_side)
		branch_night.advance(1.01)
		_check(manager.get_blacky_pos() == manager.Rooms.STAGE and not manager.is_blacky_on(), "matching fan repels Blacky from vent %d and lowers posture" % branch)
		manager.routes.blacky_path = original_path
		manager.reset_for_night()
		await _release_night(branch_night)


func _test_old_creeper_stages_shock_and_timeout() -> void:
	var config := _new_config()
	config.old_creeper_level = 20
	var night := await _spawn_night(config)
	var manager: Node = root.get_node("AnimatronicMgnt")
	var stages: Array[int] = []
	manager.old_creeper_state_changed.connect(func(state: int) -> void: stages.append(state))
	night.begin_night()
	for expected in [manager.Old_creeper_states.STATE2, manager.Old_creeper_states.STATE3, manager.Old_creeper_states.STATE4_FINAL, manager.Old_creeper_states.OUT]:
		_force_route_checks(night, manager.Animatronics.OLD_CREEPER, 1)
		_check(manager.old_creeper_state == expected, "Old Creeper advances to authored stage %d" % expected)
	_check(stages.size() >= 3, "old-creeper stage changes emit camera refresh signals")
	_force_route_checks(night, manager.Animatronics.OLD_CREEPER, 3)
	_check(manager.get_old_creeper_pos() == manager.Rooms.HALLWAY and night.route_ai.get_warning_room(manager.Animatronics.OLD_CREEPER) == manager.Rooms.HALLWAY, "Old Creeper exits the workshop and warns from hallway")
	_check(not night.request_shock(), "shocker rejects while monitor is closed")
	_check(is_equal_approx(night.power_left, night.config.power_capacity), "rejected shock does not spend energy")
	_check(night.select_surveillance_camera(2), "camera two can be selected")
	night.set_surveillance_open(true)
	_check(night.request_shock(), "camera-two shock repels active Old Creeper")
	_check(manager.get_old_creeper_pos() == manager.Rooms.EXTRA_WORKSHOP and manager.old_creeper_state == manager.Old_creeper_states.STATE1, "successful shock resets position and stage")
	_check(is_equal_approx(night.power_left, night.config.power_capacity - night.config.shock_cost), "successful shock spends configured energy once")
	_check(is_equal_approx(night.shock_cooldown_remaining, night.config.shock_cooldown_seconds), "successful shock starts configured cooldown")
	_check(not night.request_shock(), "cooldown rejects repeated shock")
	_check(is_equal_approx(night.power_left, night.config.power_capacity - night.config.shock_cost), "cooldown rejection does not spend more energy")
	await _release_night(night)

	var wrong_camera_config := _new_config()
	wrong_camera_config.old_creeper_level = 20
	var wrong_camera := await _spawn_night(wrong_camera_config)
	wrong_camera.begin_night()
	wrong_camera.set_surveillance_open(true)
	wrong_camera.select_surveillance_camera(1)
	_check(not wrong_camera.request_shock(), "shocker rejects a different selected camera")
	wrong_camera.select_surveillance_camera(2)
	wrong_camera.set_surveillance_open(false)
	_check(not wrong_camera.request_shock(), "shocker rejects when surveillance is closed")
	wrong_camera.set_surveillance_open(true)
	wrong_camera.power_left = wrong_camera.config.shock_cost - 0.01
	_check(not wrong_camera.request_shock(), "shocker rejects insufficient power")
	_check(is_equal_approx(wrong_camera.power_left, wrong_camera.config.shock_cost - 0.01), "insufficient-power rejection leaves energy unchanged")
	await _release_night(wrong_camera)

	var exact_config := _new_config()
	exact_config.old_creeper_level = 20
	exact_config.power_capacity = exact_config.shock_cost
	var exact := await _spawn_night(exact_config)
	exact.begin_night()
	exact.select_surveillance_camera(2)
	exact.set_surveillance_open(true)
	_check(exact.request_shock(), "shock is accepted when energy exactly equals its price")
	_check(exact.power_left == 0.0 and exact.phase == exact.Phase.POWER_OUT, "exact-price shock spends final energy and starts blackout")
	_check(not exact.route_ai._running and not exact.request_shock(), "blackout stops route AI and rejects another shock")
	await _release_night(exact)

	var miss_config := _new_config()
	miss_config.old_creeper_level = 20
	var miss := await _spawn_night(miss_config)
	miss.begin_night()
	_force_route_checks(miss, manager.Animatronics.OLD_CREEPER, 7)
	_check(miss.route_ai.get_warning_room(manager.Animatronics.OLD_CREEPER) == manager.Rooms.HALLWAY, "uninterrupted Old Creeper route reaches its attack warning")
	miss.advance(miss.config.old_creeper_warning_seconds + 0.2)
	_check(miss.phase == miss.Phase.LOST and _last_outcome_reason(miss) == "old_creeper", "missing Old Creeper warning causes its own defeat")
	await _release_night(miss)


func _test_berry_and_blacky_attack_presentations() -> void:
	var manager: Node = root.get_node("AnimatronicMgnt")
	for character in [manager.Animatronics.BERRY, manager.Animatronics.BLACKY]:
		var config := _new_config()
		config.berry_level = 20 if character == manager.Animatronics.BERRY else 0
		config.blacky_level = 20 if character == manager.Animatronics.BLACKY else 0
		var night := await _spawn_night(config)
		night.begin_night()
		_force_next_warning(night, character)
		night.advance(_warning_duration(night.config, character) + 0.2)
		var expected_reason := "berry" if character == manager.Animatronics.BERRY else "blacky"
		_check(night.phase == night.Phase.LOST and _last_outcome_reason(night) == expected_reason, "%s missed warning produces its own loss reason" % expected_reason)
		var presentation: Node = night.get_node("NightPresentation")
		_check(not presentation._jumpscare_frames.is_empty(), "%s loads its character jumpscare frames" % expected_reason)
		_check(presentation._jumpscare_death_path.ends_with("/" + presentation.DEATH_IMAGES[expected_reason]), "%s selects its matching death illustration" % expected_reason)
		await _release_night(night)


func _test_remote_fan_and_camera_shocker_controls() -> void:
	var fan_config := _new_config()
	fan_config.blacky_level = 20
	var fan_night := await _spawn_night(fan_config)
	var cameras: Node = fan_night.get_node("CameraSystem")
	fan_night.begin_night()
	cameras._on_remote_controller_button_mouse_entered()
	_check(fan_night.monitor_open and not fan_night.surveillance_open, "remote opening applies the shared office input guard")
	_check(cameras.fan_left_button.disabled and cameras.fan_right_button.disabled, "fan buttons wait for remote animation to finish")
	cameras._on_remote_controller_animation_finished()
	_check(not cameras.fan_left_button.disabled and not cameras.fan_right_button.disabled, "remote animation enables both fan controls")
	cameras._on_fan_left_pressed()
	_check(fan_night.is_left_fan_enabled and cameras.fan_left_lit.visible, "left remote button toggles the left fan and its indicator")
	cameras._on_fan_right_pressed()
	_check(fan_night.is_right_fan_enabled and cameras.fan_right_lit.visible, "right remote button toggles the right fan and its indicator")
	fan_night.request_door_toggle()
	_check(not cameras.camera_pad.get_node("consumption_count").visible, "four-unit consumption stays hidden while tablet is closed")
	cameras._on_remote_controller_button_mouse_entered()
	cameras._on_remote_controller_animation_finished()
	cameras._on_fan_left_pressed()
	_check(fan_night.is_left_fan_enabled, "hidden remote rejects fan input after close")
	cameras._on_open_button_mouse_entered()
	cameras._on_camera_pad_animation_finished()
	_check(cameras.camera_pad.get_node("consumption_count").visible, "four-unit consumption appears on the open tablet")
	cameras._on_open_button_mouse_entered()
	cameras._on_camera_pad_animation_finished()
	fan_night.request_fan_toggle(0)
	fan_night.request_fan_toggle(0)
	_check(not cameras.camera_pad.get_node("consumption_count").visible, "power updates cannot reveal consumption after tablet closes")
	await _release_night(fan_night)

	var shock_config := _new_config()
	shock_config.old_creeper_level = 20
	var shock_night := await _spawn_night(shock_config)
	var shock_cameras: Node = shock_night.get_node("CameraSystem")
	shock_night.begin_night()
	shock_cameras._on_open_button_mouse_entered()
	_check(shock_cameras.shock_button.disabled, "camera open waits for tablet animation before enabling the shocker")
	shock_cameras._on_camera_pad_animation_finished()
	shock_cameras.select_camera_2()
	_check(shock_night.surveillance_open and shock_cameras.shock_button.visible and not shock_cameras.shock_button.disabled, "active Old Creeper enables shocker on open camera two")
	shock_cameras._on_shock_pressed()
	_check(is_equal_approx(shock_night.power_left, shock_config.power_capacity - shock_config.shock_cost) and shock_night.shock_cooldown_remaining > 0.0, "accepted UI shock spends power and begins model cooldown")
	_check(shock_cameras.shock_button.disabled, "shocker button disables during cooldown")
	shock_night.advance(shock_config.shock_cooldown_seconds + 0.05)
	_check(shock_night.shock_cooldown_remaining == 0.0 and not shock_cameras.shock_button.disabled, "cooldown expiry refreshes the enabled shocker control")
	await _release_night(shock_night)


func _test_terminal_phase_stops_all_route_ai() -> void:
	var config := _new_config()
	config.dog_level = 20
	config.berry_level = 20
	config.blacky_level = 20
	config.old_creeper_level = 20
	var night := await _spawn_night(config)
	var manager: Node = root.get_node("AnimatronicMgnt")
	night.begin_night()
	_force_next_warning(night, manager.Animatronics.DOG)
	_check(night.request_door_toggle(), "terminal test closes door against Dog")
	night.advance(1.01)
	_check(night.phase == night.Phase.RUNNING, "Dog defense creates room for remaining characters")
	_force_route_checks(night, manager.Animatronics.OLD_CREEPER, 7)
	_check(night.route_ai.get_warning_room(manager.Animatronics.OLD_CREEPER) == manager.Rooms.HALLWAY, "Old Creeper is poised for a second independent attack")
	# Make time win on the same simulation step as Old Creeper's deadline.
	night.hours = night.config.end_hour - 1
	night.minutes = 59
	night._clock_elapsed = night.config.seconds_per_minute - 0.001
	night.advance(night.config.old_creeper_warning_seconds + 0.2)
	_check(night.phase == night.Phase.WON and _last_outcome_reason(night) == "time", "07:00 wins over a route attack due on the same step")
	_check(not night.route_ai._running and night.route_ai.get_warning_room(manager.Animatronics.OLD_CREEPER) == manager.Rooms.NONE, "victory cancels active route warning and stops every route AI")
	var positions := [manager.get_dog_pos(), manager.get_berry_pos(), manager.get_blacky_pos(), manager.get_old_creeper_pos()]
	night.route_ai.advance(100.0)
	_check(positions == [manager.get_dog_pos(), manager.get_berry_pos(), manager.get_blacky_pos(), manager.get_old_creeper_pos()], "stopped route AI cannot move after the night ends")
	await _release_night(night)


func _new_config() -> Resource:
	var config: Resource = load("res://resources/night_1.tres").duplicate(true)
	config.sann_level = 0
	config.seconds_per_minute = 1000.0
	config.power_capacity = 10000.0
	config.route_initial_grace_seconds = 0.0
	config.route_check_interval_seconds = 0.1
	config.route_defense_hold_seconds = 1.0
	config.dog_min_check_interval_seconds = 0.1
	config.dog_move_acceleration_seconds = 0.0
	return config


func _spawn_night(config: Resource) -> Node:
	var packed := load("res://scenes/Night.tscn") as PackedScene
	if packed == null:
		_check(false, "Night.tscn loads as PackedScene")
		return null
	var night := packed.instantiate()
	night.config = config
	night.set_process(false)
	night.outcome_reached.connect(func(_won: bool, reason: String) -> void: night.set_meta("_test_outcome_reason", reason))
	root.add_child(night)
	await process_frame
	night.set_process(false)
	return night


func _force_route_checks(night: Node, character: int, count: int) -> void:
	var state: Dictionary = night.route_ai._states[character]
	state.grace = 0.0
	state.elapsed = 0.0
	for _index in range(count):
		if not night.is_player_input_allowed() or night.route_ai.get_warning_room(character) != root.get_node("AnimatronicMgnt").Rooms.NONE:
			return
		night.route_ai.advance(0.1)


func _force_next_warning(night: Node, character: int) -> void:
	_force_route_checks(night, character, 32)


func _last_outcome_reason(night: Node) -> String:
	if night.has_meta("_test_outcome_reason"):
		return str(night.get_meta("_test_outcome_reason"))
	return ""


func _warning_duration(config: Resource, character: int) -> float:
	var manager: Node = root.get_node("AnimatronicMgnt")
	if character == manager.Animatronics.DOG: return config.dog_warning_seconds
	if character == manager.Animatronics.BERRY: return config.berry_warning_seconds
	if character == manager.Animatronics.BLACKY: return config.blacky_warning_seconds
	if character == manager.Animatronics.OLD_CREEPER: return config.old_creeper_warning_seconds
	return 0.0


func _release_night(night: Node) -> void:
	if is_instance_valid(night):
		night.queue_free()
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("TEST_PASS: ", description)
	else:
		_failures += 1
		push_error("TEST_FAIL: " + description)
