extends SceneTree

## Deterministic headless smoke and lifecycle suite for Night.gd and SannAI.
## Run with Godot 4.4.1: --headless --path <project> --script res://tests/test_night.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_intro_and_start_state()
	await _test_clock_win_and_terminal_idempotence()
	await _test_sann_warning_defense_and_timeout()
	await _test_power_out_grace_and_terminal_state()
	await _test_terminal_priority()
	await _test_night_reentry_resets_shared_positions()
	await _test_scene_input_and_monitor_lifecycle()
	await _test_audio_event_routing()
	await _test_outcome_audio_and_presentation()
	print("NIGHT_TESTS checks=%d failures=%d" % [_checks, _failures])
	call_deferred("quit", 1 if _failures > 0 else 0)


func _test_intro_and_start_state() -> void:
	var config := _new_config()
	config.sann_level = 0
	config.seconds_per_minute = 1.0
	var night := await _spawn_night(config)
	_check(night.phase == 0, "new night starts in INTRO")
	_check(night.hours == 0 and night.minutes == 0, "intro begins at 00:00")
	_check(night.power_left == config.power_capacity, "intro retains full configured power")
	_check(night.get_node("Timer").is_stopped(), "legacy night timer remains stopped")
	_check(night.get_node("Animatronics/DogAI/DogTimer").is_stopped(), "unused dog timer remains stopped")
	var manager: Node = root.get_node("AnimatronicMgnt")
	_check(manager.get_dog_pos() == manager.Rooms.WORKSHOP, "dog starts at route origin")
	_check(manager.get_berry_pos() == manager.Rooms.STAGE, "berry starts at route origin")
	_check(manager.get_blacky_pos() == manager.Rooms.STAGE, "blacky starts at route origin")
	_check(manager.get_old_creeper_pos() == manager.Rooms.EXTRA_WORKSHOP, "old creeper starts at route origin")
	var start_count := [0]
	night.night_started.connect(func() -> void: start_count[0] += 1)
	night.advance(2.0)
	_check(night.hours == 0 and night.minutes == 0, "advance is frozen during intro")
	_check(night.power_left == config.power_capacity, "power is frozen during intro")
	_check(not night.sann_ai.active, "Sann AI is inactive during intro")
	_check(night.begin_night(), "first begin_night request starts the shift")
	_check(not night.begin_night(), "repeated begin_night request is rejected")
	_check(night.phase == 1 and start_count[0] == 1, "start transition and signal happen once")
	_check(night.sann_ai.active == false, "configured inactive Sann stays inactive")
	await _release_night(night)


func _test_clock_win_and_terminal_idempotence() -> void:
	var config := _new_config()
	config.sann_level = 0
	config.seconds_per_minute = 0.01
	config.power_capacity = 1000.0
	var night := await _spawn_night(config)
	var outcomes: Array = []
	night.outcome_reached.connect(func(won: bool, reason: String) -> void: outcomes.append([won, reason]))
	night.begin_night()
	night.advance(4.21)
	_check(night.phase == 3, "clock reaches the configured 07:00 win")
	_check(night.hours >= config.end_hour, "victory clock is at or after end hour")
	_check(outcomes.size() == 1 and outcomes[0] == [true, "time"], "victory outcome emits once with time reason")
	_check(not night.request_door_toggle(), "terminal night rejects door input")
	night.advance(5.0)
	_check(outcomes.size() == 1, "terminal night does not emit a second outcome")
	_check(not night.sann_ai.active, "terminal win stops Sann AI")
	await _release_night(night)


func _test_sann_warning_defense_and_timeout() -> void:
	var defend_config := _new_config()
	defend_config.seconds_per_minute = 10.0
	defend_config.sann_level = 20
	defend_config.sann_initial_grace_seconds = 0.0
	defend_config.sann_check_interval_seconds = 0.1
	defend_config.sann_warning_seconds = 2.0
	defend_config.sann_warning_urgent_seconds = 1.0
	var night := await _spawn_night(defend_config)
	var warnings := [0]
	var urgent := [0]
	var nose_clicks := [0]
	var outcomes: Array = []
	night.sann_ai.warning_started.connect(func() -> void: warnings[0] += 1)
	night.sann_ai.warning_urgent.connect(func() -> void: urgent[0] += 1)
	night.sann_nose_clicked.connect(func() -> void: nose_clicks[0] += 1)
	night.outcome_reached.connect(func(won: bool, reason: String) -> void: outcomes.append([won, reason]))
	night.begin_night()
	_check(not night.request_sann_nose_click(), "nose outside warning window is rejected")
	night.advance(0.11)
	_check(warnings[0] == 1 and night.sann_ai.is_warning_active(), "level 20 deterministically starts a warning")
	night.set_monitor_open(true)
	_check(not night.request_sann_nose_click(), "nose defense is rejected while monitor is open")
	night.set_monitor_open(false)
	_check(night.request_sann_nose_click(), "nose defense succeeds during a warning")
	_check(nose_clicks[0] == 1 and not night.sann_ai.is_warning_active(), "successful defense clears warning and emits once")
	_check(not night.request_sann_nose_click(), "repeated nose request after defense is a no-op")
	_check(outcomes.is_empty(), "successful defense avoids an attack outcome")
	await _release_night(night)

	var urgent_config := _new_config()
	urgent_config.seconds_per_minute = 10.0
	urgent_config.sann_level = 20
	urgent_config.sann_initial_grace_seconds = 0.0
	urgent_config.sann_check_interval_seconds = 0.1
	urgent_config.sann_warning_seconds = 1.0
	urgent_config.sann_warning_urgent_seconds = 0.3
	var urgent_night := await _spawn_night(urgent_config)
	var urgent_count := [0]
	urgent_night.sann_ai.warning_urgent.connect(func() -> void: urgent_count[0] += 1)
	urgent_night.begin_night()
	urgent_night.advance(0.11)
	urgent_night.advance(0.71)
	_check(urgent_count[0] == 1, "urgent warning signal fires once as its deadline approaches")
	_check(urgent_night.phase == 1, "urgent warning has not attacked before its deadline")
	await _release_night(urgent_night)

	var timeout_config := _new_config()
	timeout_config.seconds_per_minute = 10.0
	timeout_config.sann_level = 20
	timeout_config.sann_initial_grace_seconds = 0.0
	timeout_config.sann_check_interval_seconds = 0.1
	timeout_config.sann_warning_seconds = 0.2
	timeout_config.sann_warning_urgent_seconds = 0.0
	var timeout_night := await _spawn_night(timeout_config)
	var timeout_outcomes: Array = []
	timeout_night.outcome_reached.connect(func(won: bool, reason: String) -> void: timeout_outcomes.append([won, reason]))
	timeout_night.begin_night()
	timeout_night.advance(0.31)
	_check(timeout_night.phase == 4, "missed Sann warning loses the night")
	_check(timeout_outcomes.size() == 1 and timeout_outcomes[0] == [false, "sann"], "Sann defeat emits one identified outcome")
	_check(not timeout_night.sann_ai.active, "Sann AI stops after attack")
	await _release_night(timeout_night)


func _test_power_out_grace_and_terminal_state() -> void:
	var config := _new_config()
	config.seconds_per_minute = 100.0
	config.sann_level = 1
	config.sann_initial_grace_seconds = 60.0
	config.power_capacity = 2.0
	config.power_out_grace_seconds = 10.0
	var night := await _spawn_night(config)
	var outcomes: Array = []
	var door_states: Array = []
	night.outcome_reached.connect(func(won: bool, reason: String) -> void: outcomes.append([won, reason]))
	night.door_changed.connect(func(closed: bool) -> void: door_states.append(closed))
	night.begin_night()
	_check(night.request_door_toggle(), "door toggles during a running night")
	_check(night.get_total_energy_consumption() == 2, "closed door increases power consumption")
	night.advance(1.0)
	_check(night.phase == 2 and night.power_left == 0.0, "power reaches zero and enters POWER_OUT")
	_check(not night.is_door_closed and door_states.back() == false, "power outage opens the door")
	_check(not night.sann_ai.active, "power outage stops Sann AI")
	_check(not night.is_player_input_allowed(), "power outage disables player input")
	_check(night.get_total_energy_consumption() == 0, "power outage stops consumption")
	night.advance(9.99)
	_check(night.phase == 2, "power-out grace delays defeat")
	night.advance(0.02)
	_check(night.phase == 4, "power-out grace expiry loses the night")
	_check(outcomes.size() == 1 and outcomes[0] == [false, "power"], "power defeat emits once with power reason")
	await _release_night(night)


func _test_terminal_priority() -> void:
	var config := _new_config()
	config.seconds_per_minute = 0.05
	config.power_capacity = 1.0
	config.power_out_grace_seconds = 10.0
	config.sann_level = 20
	config.sann_initial_grace_seconds = 60.0
	var night := await _spawn_night(config)
	var outcomes: Array = []
	night.outcome_reached.connect(func(won: bool, reason: String) -> void: outcomes.append([won, reason]))
	night.begin_night()
	# Place both independent failure clocks immediately before their deadline.
	# advance() must resolve the 07:00 clock before consuming power or advancing AI.
	night.hours = 6
	night.minutes = 59
	night._clock_elapsed = 0.049
	night._power_elapsed = 0.999
	night.power_left = 1.0
	night.sann_ai.active = true
	night.sann_ai.warning_active = true
	night.sann_ai.warning_remaining = 0.001
	night.advance(0.002)
	_check(night.phase == 3, "07:00 takes priority over simultaneous power and Sann deadlines")
	_check(outcomes.size() == 1 and outcomes[0] == [true, "time"], "simultaneous deadline produces victory exactly once")
	await _release_night(night)


func _test_night_reentry_resets_shared_positions() -> void:
	var manager: Node = root.get_node("AnimatronicMgnt")
	var first := await _spawn_night(_new_config())
	manager.set_dog_pos(manager.Rooms.OFFICE)
	manager.set_blacky_pos(manager.Rooms.LEFT_VENT)
	await _release_night(first)
	var second := await _spawn_night(_new_config())
	_check(manager.get_dog_pos() == manager.Rooms.WORKSHOP, "re-entering Night resets Dog position")
	_check(manager.get_blacky_pos() == manager.Rooms.STAGE, "re-entering Night resets Blacky position")
	_check(second.hours == 0 and second.minutes == 0 and second.phase == 0, "re-entering Night resets clock and phase")
	await _release_night(second)


func _test_scene_input_and_monitor_lifecycle() -> void:
	var config := _new_config()
	config.sann_level = 20
	config.sann_initial_grace_seconds = 0.0
	config.sann_check_interval_seconds = 0.1
	config.sann_warning_seconds = 2.0
	config.seconds_per_minute = 10.0
	var night := await _spawn_night(config)
	var camera: Node = night.get_node("CameraSystem")
	var view: Node = night.get_node("Office/SannView")
	var presentation: Node = night.get_node("NightPresentation")
	_check(night.get_meta("_test_sann_export_matches_child"), "serialized Night SannAI reference points to the scene child")
	_check(night.sann_ai == night.get_node("Animatronics/SannAI"), "Night uses the scene SannAI instance")
	_check(view.sann_ai == night.sann_ai and view.night == night, "office Sann view references authoritative Night and AI")
	_check(presentation.night == night, "Night presentation observes Night root")
	_check(presentation._visible_state == "intro" and presentation._root.visible, "intro overlay blocks play until shift start")
	_check(not view._nose_area.input_pickable, "Sann nose hit area is disabled during intro")
	_check(camera.get_node("camera_pad/camera_buttons/cam1").disabled, "camera buttons remain disabled in intro")
	_check(camera.get_node("camera_pad/battery").texture != null, "camera battery starts with a valid texture")
	_check(camera.get_node("camera_pad/time").text == "00:00", "camera HUD starts at 00:00")
	for percentage in range(0, 101, 10):
		camera.update_battery(float(config.power_capacity) * float(percentage) / 100.0)
		_check(camera.get_node("camera_pad/battery").texture != null, "battery percentage %d has an imported image" % percentage)
	camera.update_energy_consumption(0)
	_check(not camera.get_node("camera_pad/energy_consumption").visible, "zero consumption hides meter without loading a nonexistent frame")
	for consumption in range(1, 6):
		camera.update_energy_consumption(consumption)
		_check(camera.get_node("camera_pad/energy_consumption").texture != null, "consumption level %d maps to an existing meter image" % consumption)
	var mouse_left := InputEventMouseButton.new()
	mouse_left.button_index = MOUSE_BUTTON_LEFT
	mouse_left.pressed = true
	view._on_nose_input_event(null, mouse_left, 0)
	_check(not night.sann_ai.is_warning_active(), "nose input outside warning does not alter Sann")
	_check(not night.request_door_toggle(), "intro phase rejects direct office door action")
	_check(camera.get_node("camera_pad/camera_buttons/cam1").disabled, "camera buttons remain disabled before monitor opens")
	_check(night.begin_night(), "scene start enters RUNNING")
	_check(not presentation._root.visible and view._nose_area.input_pickable, "start hides intro and enables office hit area")
	_check(camera.get_node("camera_pad/camera_buttons/cam1").disabled, "camera buttons stay disabled while monitor is closed")
	night.advance(0.11)
	_check(night.sann_ai.is_warning_active() and view._warning, "real Sann warning reaches office view")
	var warning_pose: Texture2D = view.texture
	view._advance_warning_pose()
	_check(view.texture != warning_pose, "warning pose animation switches to its alternate image")
	_check(presentation._warning_hint.visible, "Sann warning enables defensive instructions")
	camera._on_open_button_mouse_entered()
	_check(camera.isPadUp and night.monitor_open, "first monitor request opens logical monitor immediately")
	_check(camera.get_node("picture/camera_noise").is_playing(), "opening monitor starts camera noise")
	_check(camera.get_node("camera_pad/camera_buttons/cam1").disabled, "opening monitor blocks camera selection during animation")
	camera._on_camera_pad_animation_finished()
	_check(not camera.get_node("camera_pad/camera_buttons/cam1").disabled, "completed monitor opening enables camera selection")
	camera._on_open_button_mouse_entered()
	_check(not camera.isPadUp and night.monitor_open, "rapid close keeps nose-input guard until close animation ends")
	camera._on_camera_pad_animation_finished()
	_check(not night.monitor_open, "monitor close completion releases input guard")
	camera._on_open_button_mouse_entered()
	_check(camera.isPadUp and night.monitor_open, "monitor can reopen immediately after close")
	camera._on_camera_pad_animation_finished()
	var selected: Array = []
	camera.camera_selected.connect(func(index: int) -> void: selected.append(index))
	for index in range(1, 8):
		camera.call("select_camera_%d" % index)
		_check(camera.picture.texture != null, "camera %d selection produces a room texture" % index)
	_check(selected == [1, 2, 3, 4, 5, 6, 7], "seven camera methods emit matching camera number once")
	camera.select_camera_1()
	var layer2: Sprite2D = camera.picture.get_node("layer2")
	_check(layer2.texture != null, "camera overlay exists before extra workshop selection")
	camera.select_camera_2()
	_check(layer2.texture == null, "extra workshop clears overlays from previous room")
	camera._on_remote_controller_button_mouse_entered()
	_check(camera.isRemoteControllerUp and not camera.isPadUp, "remote switch closes monitor and opens remote")
	_check(night.monitor_open, "remote remains covered by shared monitor input guard")
	camera._on_remote_controller_button_mouse_entered()
	_check(not camera.isRemoteControllerUp and night.monitor_open, "rapid remote close retains guard through animation")
	camera._on_remote_controller_animation_finished()
	camera._on_camera_pad_animation_finished()
	_check(not night.monitor_open, "remote close completion releases input guard")
	var door_area: Area2D = night.get_node("Office/DoorButton/Area2D")
	var door_connections := door_area.get_signal_connection_list("input_event")
	_check(door_connections.size() == 1 and door_connections[0].callable.get_method() == "_on_area_2d_input_event", "door hit area has exactly one gameplay input handler")
	var door_button: Node = night.get_node("Office/DoorButton")
	var door_changes: Array = []
	night.door_changed.connect(func(closed: bool) -> void: door_changes.append(closed))
	door_button._on_area_2d_input_event(null, mouse_left, 0)
	_check(night.is_door_closed and door_changes == [true], "one door input emits exactly one accepted toggle")
	_check(not door_button.open_button.visible, "door button art reflects accepted closed state")
	door_button._on_area_2d_input_event(null, mouse_left, 0)
	_check(not night.is_door_closed and door_changes == [true, false], "rapid second door input toggles once back open")
	var mouse_right := InputEventMouseButton.new()
	mouse_right.button_index = MOUSE_BUTTON_RIGHT
	mouse_right.pressed = true
	view._on_nose_input_event(null, mouse_right, 0)
	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.pressed = false
	view._on_nose_input_event(null, mouse_release, 0)
	view._on_nose_input_event(null, mouse_right, 0)
	view._on_nose_input_event(null, mouse_release, 0)
	_check(night.sann_ai.is_warning_active(), "right click and left-button release do not defend Sann")
	night.set_monitor_open(true)
	view._on_nose_input_event(null, mouse_left, 0)
	_check(night.sann_ai.is_warning_active(), "nose remains protected while monitor is open")
	night.set_monitor_open(false)
	var nose_hits := [0]
	view.nose_pressed.connect(func() -> void: nose_hits[0] += 1)
	view._on_nose_input_event(null, mouse_left, 0)
	_check(not night.sann_ai.is_warning_active() and nose_hits[0] == 1, "left press during warning defends and sends one view event")
	night.advance(0.2)
	_check(night.phase == night.Phase.RUNNING, "defended warning does not attack on next simulation step")
	await _release_night(night)


func _test_audio_event_routing() -> void:
	var config := _new_config()
	config.seconds_per_minute = 10.0
	config.sann_level = 20
	config.sann_initial_grace_seconds = 0.0
	config.sann_check_interval_seconds = 0.1
	config.sann_warning_seconds = 2.0
	config.sann_warning_urgent_seconds = 1.0
	var night := await _spawn_night(config)
	var audio: Node = night.get_node("NightAudio")
	var stream_fields := [audio.ambience_stream, audio.start_stream, audio.door_button_stream, audio.door_motion_stream, audio.tablet_up_stream, audio.tablet_down_stream, audio.camera_switch_stream, audio.sann_warning_stream, audio.sann_urgent_stream, audio.sann_nose_stream, audio.sann_jumpscare_stream, audio.power_out_stream, audio.won_stream, audio.lost_stream]
	for stream_index in range(stream_fields.size()):
		_check(stream_fields[stream_index] != null, "night audio stream %d is loaded" % (stream_index + 1))
	_check(audio.ambience_stream != audio._looping_ambience, "ambience looping uses a private stream copy")
	if audio.ambience_stream is AudioStreamWAV:
		_check(audio._looping_ambience.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience copy is configured to loop")
		_check(audio.ambience_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "loop setting does not mutate imported ambience")
	for player_name in ["Ambience", "Control", "DoorMotion", "Warning", "Nose", "Outcome"]:
		_check(night.get_node("NightAudio/%s" % player_name) is AudioStreamPlayer, "audio player %s exists" % player_name)
	_check(night.begin_night(), "audio test starts the night")
	_check(audio.ambience_player.playing and audio.ambience_player.stream == audio._looping_ambience, "starting night begins ambience")
	_check(audio.control_player.playing and audio.control_player.stream == audio.start_stream, "starting night plays its start cue")
	_check(night.request_door_toggle(), "door action is accepted for audio routing")
	_check(audio.door_player.playing and audio.door_player.stream == audio.door_motion_stream, "accepted door transition plays movement cue")
	_check(audio.control_player.stream == audio.door_button_stream, "accepted door transition plays button cue")
	var camera: Node = night.get_node("CameraSystem")
	camera._on_open_button_mouse_entered()
	_check(audio.control_player.stream == audio.tablet_up_stream, "monitor opening routes tablet-up audio")
	camera._on_camera_pad_animation_finished()
	camera.select_camera_1()
	_check(audio.control_player.stream == audio.camera_switch_stream, "camera change routes switch audio")
	camera._on_open_button_mouse_entered()
	_check(audio.control_player.stream == audio.tablet_down_stream, "monitor closing routes tablet-down audio")
	camera._on_camera_pad_animation_finished()
	camera._on_remote_controller_button_mouse_entered()
	_check(audio.control_player.stream == audio.tablet_up_stream, "remote opening routes tablet control cue")
	camera._on_remote_controller_button_mouse_entered()
	camera._on_remote_controller_animation_finished()
	night.sann_ai.advance(0.11)
	_check(audio.warning_player.playing and audio.warning_player.stream == audio.sann_warning_stream, "Sann warning routes its warning cue")
	night.sann_ai.warning_urgent.emit()
	_check(audio.warning_player.stream == audio.sann_urgent_stream, "urgent warning replaces warning cue")
	_check(night.request_sann_nose_click(), "audio test defends the active Sann warning")
	_check(not audio.warning_player.playing and audio.nose_player.playing and audio.nose_player.stream == audio.sann_nose_stream, "successful nose defense stops warning audio and plays nose cue")
	await _release_night(night)


func _test_outcome_audio_and_presentation() -> void:
	var win_config := _new_config()
	win_config.sann_level = 0
	win_config.seconds_per_minute = 0.01
	win_config.power_capacity = 1000.0
	var winner := await _spawn_night(win_config)
	var win_audio: Node = winner.get_node("NightAudio")
	var win_presentation: Node = winner.get_node("NightPresentation")
	winner.begin_night()
	winner.advance(4.21)
	_check(winner.phase == winner.Phase.WON, "end-hour transition reaches WON")
	_check(win_audio.outcome_player.playing and win_audio.outcome_player.stream == win_audio.won_stream, "victory plays the dedicated win cue")
	_check(not win_audio.ambience_player.playing and not win_audio.warning_player.playing, "victory stops ambient and warning audio")
	var end_art: AnimatedSprite2D = winner.get_node("NightEnd/AnimatedSprite2D")
	_check(winner.get_node("NightEnd").visible, "victory presents the ending art")
	_check(not winner.get_node("NightEnd/AnimationPlayer").is_playing(), "old 05-to-06 sequence is stopped on 07:00 victory")
	_check(end_art.frame == end_art.sprite_frames.get_frame_count("default") - 1, "victory shows only the truthful final ending frame")
	_check(not win_presentation._death_timer.is_stopped(), "victory result screen is delayed after ending art")
	win_presentation._show_death_result()
	_check(win_presentation._visible_state == "won" and win_presentation._title.text.begins_with("07:00"), "victory result text reports 07:00")
	_check(win_presentation._primary.text == "В меню" and win_presentation._secondary.text == "Сыграть ещё раз", "victory actions provide menu and replay")
	await _release_night(winner)

	var power_config := _new_config()
	power_config.power_capacity = 1.0
	power_config.seconds_per_minute = 100.0
	power_config.sann_level = 0
	var power_night := await _spawn_night(power_config)
	var power_audio: Node = power_night.get_node("NightAudio")
	var power_presentation: Node = power_night.get_node("NightPresentation")
	power_night.begin_night()
	power_night.advance(1.0)
	_check(power_night.phase == power_night.Phase.POWER_OUT, "zero power enters blackout grace")
	_check(power_presentation._blackout.visible, "power-out phase displays the blackout")
	_check(power_audio.outcome_player.playing and power_audio.outcome_player.stream == power_audio.power_out_stream, "blackout plays its dedicated cue")
	_check(not power_audio.ambience_player.playing and not power_audio.warning_player.playing, "blackout stops ambient and warning audio")
	power_night.advance(power_config.power_out_grace_seconds)
	_check(power_night.phase == power_night.Phase.LOST, "power grace expires into a terminal loss")
	_check(power_audio.outcome_player.playing and power_audio.outcome_player.stream == power_audio.lost_stream, "power loss replaces blackout cue with defeat cue")
	_check(power_presentation._fullscreen_art.texture != null and power_presentation._fullscreen_art.visible, "power loss displays its death image")
	_check(power_presentation._death_timer.wait_time == 2.0, "power death result uses its configured presentation delay")
	power_presentation._show_death_result()
	_check(power_presentation._visible_state == "lost" and power_presentation._primary.text == "Повторить" and power_presentation._secondary.text == "В меню", "power loss offers retry and menu")
	await _release_night(power_night)

	var sann_config := _new_config()
	sann_config.sann_level = 20
	sann_config.sann_initial_grace_seconds = 0.0
	sann_config.sann_check_interval_seconds = 0.1
	sann_config.sann_warning_seconds = 0.2
	sann_config.sann_warning_urgent_seconds = 0.0
	sann_config.seconds_per_minute = 10.0
	var sann_night := await _spawn_night(sann_config)
	var sann_audio: Node = sann_night.get_node("NightAudio")
	var sann_presentation: Node = sann_night.get_node("NightPresentation")
	sann_night.begin_night()
	sann_night.advance(0.31)
	_check(sann_night.phase == sann_night.Phase.LOST, "missed warning completes the Sann attack path")
	_check(sann_audio.outcome_player.playing and sann_audio.outcome_player.stream == sann_audio.sann_jumpscare_stream, "Sann defeat starts the dedicated jumpscare sound")
	_check(not sann_audio.ambience_player.playing and not sann_audio.warning_player.playing, "Sann defeat stops ambient and warning sounds")
	_check(sann_presentation._jumpscare_frames.size() == 10 and sann_presentation._fullscreen_art.texture != null, "Sann jumpscare loads its ten-frame animation")
	_check(not sann_presentation._jumpscare_timer.is_stopped(), "Sann jumpscare timer begins on attack")
	for _frame in range(10):
		sann_presentation._advance_jumpscare()
	_check(sann_presentation._fullscreen_art.texture != null and sann_presentation._death_timer.wait_time == 2.0, "jumpscare transitions to final death image")
	sann_presentation._show_death_result()
	_check(sann_presentation._visible_state == "lost" and sann_presentation._primary.text == "Повторить", "Sann defeat result offers retry")
	await _release_night(sann_night)


func _new_config() -> Resource:
	return load("res://resources/night_1.tres").duplicate(true)


func _spawn_night(config: Resource) -> Node:
	var packed := load("res://scenes/Night.tscn") as PackedScene
	if packed == null:
		_check(false, "Night.tscn loads as PackedScene")
		return null
	var night := packed.instantiate()
	night.config = config
	night.set_process(false)
	var scene_sann := night.get_node_or_null("Animatronics/SannAI")
	night.set_meta("_test_sann_export_matches_child", night.sann_ai == scene_sann and scene_sann != null)
	if scene_sann != null and night.sann_ai != scene_sann:
		# Exercise gameplay with the scene-owned AI while preserving a failure
		# check for a broken serialized NodePath in the scene above.
		night.sann_ai = scene_sann
	root.add_child(night)
	await process_frame
	night.set_process(false)
	return night


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
