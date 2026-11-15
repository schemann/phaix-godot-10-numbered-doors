extends SceneTree
## Headless tests for tutorial 10. From the repository root:
##   godot --headless --path godot/10-numbered-doors -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed.
## `-- --only=text` runs the tests whose name contains the text (for example `-- --only=label`).
## `-- --previous=/abs/dir` points the comparison with tutorial 09 at a copy of its project (default: the folder
## `../09-sound-and-camera-feel` next to this project); without either of them those tests are skipped and say so.
##
## Saves: every level the tests load gets its own temporary save file and its own settings file (OS temp dir), so a test run
## never reads or writes the real best_times.json or settings.json.
## What the tests prove is what the narration and the README claim; the video shows the game (series rule 33), the figures
## are measured here and printed (the lines that start with spaces under a PASS).

const Autopilot := preload("res://tools/autopilot.gd")
const Chain := preload("res://steps/step_03_number_plate/room_chain.gd") ## The finished chain (every step plans the run of step 0).

const STEPS: Array[String] = [
	"step_00_start",
	"step_01_label_on_the_leaf",
	"step_02_numbers_from_the_chain",
	"step_03_number_plate",
]
const FINAL_STEP := "step_03_number_plate"
const NUMBER_STEPS: Array[String] = ["step_01_label_on_the_leaf", "step_02_numbers_from_the_chain", "step_03_number_plate"] ## The steps with a number on the door.
const CHAIN_STEP := "step_02_numbers_from_the_chain" ## The first step whose numbers come from the plans.
const PLATE_STEP := "step_03_number_plate" ## The step with the number plate: CSG shapes, shaded beige digits, four of them.
const THIS_FOLDER := "10-numbered-doors"
const PREVIOUS_FOLDER := "09-sound-and-camera-feel" ## Tutorial 09, which sits next to this project in the repository.
const PREVIOUS_FINAL_STEP := "step_05_comfort_settings" ## Its last step is this tutorial's step 0.
const ROOM_TYPES: Array[String] = ["straight", "long", "turn_left", "turn_right", "wide", "vault"] ## Every room type that has a door.

## What each step changes against the one before (file names under the step folder; .uid files do not count).
const CHANGES: Dictionary[String, Dictionary] = {
	"step_01_label_on_the_leaf": {changed = ["door.tscn"], added = []},
	"step_02_numbers_from_the_chain": {changed = ["door.gd", "door.tscn", "level.gd"], added = []},
	"step_03_number_plate": {changed = ["door.gd", "door.tscn"], added = []},
}

## The actions of tutorial 09 (this tutorial adds none).
const ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "jump", "walk", "look_left", "look_right", "look_up", "look_down",
	"toggle_debug", "regenerate", "next_seed", "edit_seed", "copy_seed", "capture_mouse",
	"toggle_view", "toggle_gizmos", "toggle_watch", "step_generation", "open_settings",
]

const STATE_FINISHED := 2 ## Level.State
const SPEED_UP := 4 ## The walking tests run this many times faster than real time.
const PLAN_SEEDS := 200 ## Seeds 1..200 for the comparisons between steps.
const SWEEP_SEEDS := 200 ## Seeds 1..200 of the finished game for the autopilot sweep.
const SWEEP_WORKERS := 5 ## Processes the sweep is split over (tools/sweep_seeds.gd, 8 times real time each).
const SHORT_GOAL := 3 ## Goal room of the quick runs.
const GOAL_ROOM := 20 ## The goal room of the game, and of the numbers tests.
const REST_FOV := 75.0 ## Degrees, vertical: the camera's default.

const LABEL_PATH := "Hinge/Number"
const LEAF_FACE := 0.05 ## Metres: half the leaf's thickness, where its front face is in the hinge's space.
const LEAF_WIDTH := 1.6
const LEAF_HEIGHT := 2.4
const LOCK_TOP := 1.43 ## The top of the lock plate (its middle at 1.15, 0.56 high).
const DIGIT_MARGIN := 0.1 ## Metres of bare door between the digits' ink and the lock and the top.
const NUMBER_HEIGHT := 1.7 ## Metres up the leaf: the middle of the number, and of the plate, in every step.
const DIGIT_METRES := 0.07 ## The narration: "a digit is about seven centimeters tall" (half a centimetre either way).
const PLATE_WIDTH := 0.5 ## The narration: "half a meter wide, nineteen centimeters tall, and two and a half centimeters deep".
const PLATE_HEIGHT := 0.19
const PLATE_DEPTH := 0.025
const FIELD_DEPTH := 0.01 ## The narration: the field "cuts one centimeter into the plate".
const ABOVE_FIELD := 0.003 ## The narration: the label sits "three millimeters in front of" the field.
const FIELD_DEPTH_STEPS := 6 ## The narration: "still six steps of the depth buffer at twenty meters".
const SCREEN_HEIGHT := 1080.0 ## The reference picture: 1080p.
const DEPTH_BITS := 24 ## The smallest depth buffer a renderer of the engine uses.
const FAR_VIEW := 20.0 ## Metres: further than any sight line of a room.
const NUMBER_SEEDS := 60 ## Seeds 1..60 for the numbers of every door of a run.
const WALKED_SEEDS: Array[int] = [42, 7, 141] ## The seeds the real player walks to the goal room.
const MOVEMENT_SEEDS: Array[int] = [42, 1000] ## The seeds whose runs are compared tick for tick.

## Counts the errors the engine logs. A test that hits a script error stops at that line and the engine hands back an
## empty array, which reads as a pass: `_report` charges the count to the test that ran.
class ScriptErrorCounter extends Logger:
	var count := 0
	var script_only := true ## false: warnings and errors of the engine count, too.
	var _lock := Mutex.new() ## The engine calls a logger from any thread.

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if script_only and error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		_lock.unlock()

## Calls its callback once per physics tick, before the player's own tick.
class Driver extends Node:
	signal finished
	var tick: Callable

	func _physics_process(_delta: float) -> void:
		if tick.is_valid() and tick.call():
			tick = Callable()
			finished.emit()

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrorCounter.new() ## Registered with the engine's logger for the whole run.
var _script_errors_reported := 0 ## How many script errors the tests reported so far have been charged with.
var _notes: Array[String] = [] ## The figures the running test measured: printed under its PASS or FAIL line.
var _skipped_whole := false ## The running test skipped itself completely: no PASS line for it.
var _save_dir := ""
var _save_counter := 0

func _initialize() -> void:
	OS.add_logger(_script_errors)
	await process_frame
	var started := Time.get_ticks_msec()
	_save_dir = OS.get_temp_dir().path_join("phaix-godot-10-tests-%d" % OS.get_process_id()) # one folder per run: two runs at the same time must not wipe each other's save files
	_wipe_save_dir()

	await _run("code rules: no class_name, no global random, no wall clock, input only through named actions", test_code_rules)
	await _run("steps: each step changes only what its concept needs, everything else is copied forward", test_copy_forward)
	await _run("step_00_start: the final state of tutorial 09, file for file (only the folder names differ)", test_step_zero_is_tutorial_09)
	await _run("steps: the usage comments in every step name this project, not tutorial 09", test_steps_name_this_project)
	await _run("step_00_start: the project file, the figure, the sounds, the materials and the buses are tutorial 09's, byte for byte", test_root_is_tutorial_09)
	await _run("project: Jolt, the actions of tutorial 09, the main scene is the final step", test_project_settings)
	await _run("hud: every step says what step 0 says (a number on a door adds no label); the Input Map is tutorial 09's", test_hud_and_input_map)
	await _run("plans: all four steps plan the run of step 0 (type, place, lock, key, props and lamp tint of seeds 1-%d): a number on a door moves nothing" % PLAN_SEEDS, test_steps_plan_the_same)
	await _run("readme: the credits name the folders that stand in the project, every path the README names exists, no Blender kit", test_readme_matches_folders)

	# Tutorial 10: a number on every door, from the plan, on a plate, facing the player.
	await _run("label: the door's number is one Label3D on the hinge, inside the leaf and clear of the lock; none in step 0; the values of each step", test_label_scene_all)
	await _run("plate: step 3's number plate is a stadium of CSG shapes on the leaf, a rim 1 cm proud of a sunken field in the door's material, the label 3 mm in front of the field", test_number_plate)
	await _run("plate: the rim is a darker orange than the door, the digits are a light beige of the door's hue, the font is the built in one, bolder, slanted and spaced", test_plate_colours)
	for step in NUMBER_STEPS:
		await _run("label %s: the number turns, moves and comes back with the leaf (it is part of the swinging body)" % step, test_label_swings.bind(step))
		await _run("label %s: a digit is about %.0f cm tall; how tall it looks on 1080p up close, where the door opens and from across the room" % [step, DIGIT_METRES * 100.0], test_label_size.bind(step))
		await _run("label %s: the number floats in front of what is behind it by more than the depth buffer's step at %.0f m, and not so far that it floats" % [step, FAR_VIEW], test_label_depth.bind(step))
		await _run("label %s: the number faces into the room in every room type, closed and open, is never mirrored, faces no wall, and the leaf hides it from behind" % step, test_label_facing.bind(step))
	for step: String in NUMBER_STEPS.slice(1):
		await _run("numbers %s: every door of %d runs says the number of the room behind it (1 to the goal), the goal room has no door, the door into it says the goal" % [step, NUMBER_SEEDS], test_numbers_of_every_door.bind(step))
		await _run("numbers %s: walking seeds %s to the goal, the door the player goes through says the number the HUD shows after it, with the rooms behind freed" % [step, WALKED_SEEDS], test_numbers_walked.bind(step))
		await _run("numbers %s: R, N and a typed seed number the doors from 1 again, after rooms were freed" % step, test_numbers_restart_and_new_seed.bind(step))
	await _run("numbers: the check finds a numbering by the rooms alive, by a counter that a restart does not reset, by the room the door is in, the plain number without its zeros, and no number", test_numbers_check_finds_faults)
	await _run("code rules: the door shows the number it is told, the level tells it from the plan, nothing else of step 0 changes", test_numbers_code_rules)

	await _run("movement: the same inputs give the same run in step 0 and in every later step, with the camera effects on and off: a number on a door moves nothing (seeds %s, 900 ticks)" % [MOVEMENT_SEEDS], test_effects_change_no_movement)
	for step in STEPS:
		await _run("%s: a room stays until the door behind it has closed, nothing goes while it stands open" % step, test_rooms_wait_for_the_door.bind(step))
	await _run("full run: seed 42, goal room 20: the autopilot fetches every key and finishes", test_full_run)
	await _run("restart: R while running leaves the body standing in room 0, in Move, at blend position 0", test_restart)
	for step in STEPS:
		await _run("%s: main scene runs 30 frames" % step, test_scene_runs.bind(step))
	await _run("sweep: the autopilot walks seeds 1-%d of the finished game to the goal room, never held in place, every door said the number the HUD showed after it" % SWEEP_SEEDS, test_autopilot_seed_sweep)

	_wipe_save_dir()
	OS.remove_logger(_script_errors)
	await create_timer(0.3).timeout # the audio server lets go of the stopped sounds in its own thread
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [_passed, _failed, _skipped, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if _failed > 0 else 0)

#region Source rules

func test_code_rules() -> Array[String]:
	var failures: Array[String] = []
	var global_random := RegEx.create_from_string("(^|[^.\\w])(randi|randf|randi_range|randf_range|randomize|pick_random)\\(")
	var wall_clock := RegEx.create_from_string("(Time\\.get_|OS\\.get_ticks|OS\\.get_unix|OS\\.delay)")
	var scripts := _files_in("res://steps", ".gd")
	_expect(failures, scripts.size() >= 100, "found only %d scripts under steps" % scripts.size())
	for path in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			var where := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			_expect(failures, not line.begins_with("class_name"), "%s: class_name" % where)
			_expect(failures, global_random.search(line) == null, "%s: global random call" % where)
			_expect(failures, wall_clock.search(line) == null, "%s: reads the wall clock" % where)
			_expect(failures, not line.contains("Input.is_key_pressed") and not line.contains("Input.is_physical_key_pressed"), "%s: reads a key directly" % where)
			_expect(failures, not line.contains("event is InputEventKey") and not line.contains("event is InputEventJoypad"), "%s: reads a key or button event directly" % where)
	_note("%d scripts under steps/ read" % scripts.size())
	return failures

## Every file of a folder and its sub folders that ends with the suffix.
func _files_in(dir_path: String, suffix: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		found.append_array(_files_in(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if file.ends_with(suffix):
			found.append(dir_path.path_join(file))
	return found

func test_copy_forward() -> Array[String]:
	var failures: Array[String] = []
	for i in range(1, STEPS.size()):
		var before := STEPS[i - 1]
		var after := STEPS[i]
		var before_files := _step_files(before)
		var after_files := _step_files(after)
		var changed: Array[String] = []
		var added: Array[String] = []
		for file in before_files:
			if not after_files.has(file):
				failures.append("%s lost %s" % [after, file])
			elif _step_text(before, file) != _step_text(after, file):
				changed.append(file)
		for file in after_files:
			if not before_files.has(file):
				added.append(file)
		changed.sort()
		added.sort()
		var expected: Dictionary = CHANGES[after]
		var expected_changed: Array = expected.changed.duplicate()
		var expected_added: Array = expected.added.duplicate()
		expected_changed.sort()
		expected_added.sort()
		_expect(failures, changed == expected_changed, "%s changes %s, expected %s" % [after, changed, expected_changed])
		_expect(failures, added == expected_added, "%s adds %s, expected %s" % [after, added, expected_added])
		_note("%s changes %s and adds %s" % [after, changed, added])
	return failures

func _step_files(step: String) -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://steps/" + step):
		if not file.ends_with(".uid"):
			files.append(file)
	if DirAccess.dir_exists_absolute("res://steps/%s/props" % step):
		for file in DirAccess.get_files_at("res://steps/%s/props" % step):
			if not file.ends_with(".uid"):
				files.append("props/" + file)
	return files

## The file's text with the step folder name blanked out, so copies compare equal.
func _step_text(step: String, file: String) -> String:
	return FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file]).replace(step, "STEP")

## The project folder of tutorial 09: the folder `--previous=` names, else the one next to this project. Empty if there is none.
func _tutorial_09() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--previous="):
			var given := argument.trim_prefix("--previous=")
			return given if DirAccess.dir_exists_absolute(given) else ""
	var folder := ProjectSettings.globalize_path("res://").path_join("../" + PREVIOUS_FOLDER).simplify_path()
	return folder if DirAccess.dir_exists_absolute(folder) else ""

## Step 0 is the last step of tutorial 09, copied. When that tutorial is not next to this project the test skips.
func test_step_zero_is_tutorial_09() -> Array[String]:
	var failures: Array[String] = []
	var tutorial := _tutorial_09()
	var original := tutorial.path_join("steps/" + PREVIOUS_FINAL_STEP)
	if tutorial.is_empty() or not DirAccess.dir_exists_absolute(original):
		_skip("step_00_start equals the last step of tutorial 09", "tutorial 09 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER)
		return failures
	var original_files: Array[String] = []
	for file in DirAccess.get_files_at(original):
		if not file.ends_with(".uid"):
			original_files.append(file)
	for file in DirAccess.get_files_at(original.path_join("props")):
		if not file.ends_with(".uid"):
			original_files.append("props/" + file)
	_expect(failures, original_files.size() > 40, "found only %d files in the last step of tutorial 09" % original_files.size())
	for file in original_files:
		if not FileAccess.file_exists("res://steps/step_00_start/" + file):
			failures.append("step_00_start has no %s" % file)
			continue
		var theirs := _without_project_names(FileAccess.get_file_as_string(original.path_join(file)))
		var ours := _without_project_names(FileAccess.get_file_as_string("res://steps/step_00_start/" + file))
		_expect(failures, theirs == ours, "%s differs from the last step of tutorial 09" % file)
	_expect(failures, original_files.size() == _step_files("step_00_start").size(), "step_00_start has %d files, the last step of tutorial 09 has %d" % [_step_files("step_00_start").size(), original_files.size()])
	_note("%d files of %s/steps/%s compared with step_00_start (compared at %s)" % [original_files.size(), PREVIOUS_FOLDER, PREVIOUS_FINAL_STEP, tutorial])
	return failures

## The files of tutorial 09 point at one of its step folders, the copies here at the start folder; the usage comments name a
## project folder (test_steps_name_this_project checks that it is this one).
func _without_step_names(text: String) -> String:
	return RegEx.create_from_string("step_\\d\\d_[a-z_]+").sub(text, "STEP", true)

func _without_project_names(text: String) -> String:
	return _without_step_names(text).replace("godot/" + PREVIOUS_FOLDER, "godot/PROJECT").replace("godot/" + THIS_FOLDER, "godot/PROJECT")

## The usage comments of the scripts (`godot --headless --path godot/<project> -s res://steps/<step>/check_echo.gd`) name this
## project: a step copied from tutorial 09 that still says `godot/09-sound-and-camera-feel` sends the viewer to a folder
## where the step does not exist.
func test_steps_name_this_project() -> Array[String]:
	var failures: Array[String] = []
	var stale: Array[String] = []
	var named := 0
	for path in _files_in("res://steps", ".gd") + _files_in("res://steps", ".tscn") + _files_in("res://steps", ".tres"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("godot/" + THIS_FOLDER):
			named += 1
		if text.contains(PREVIOUS_FOLDER):
			stale.append(path.trim_prefix("res://steps/"))
	_expect(failures, stale.is_empty(), "%d files under steps/ name %s, this project is %s: %s" % [stale.size(), PREVIOUS_FOLDER, THIS_FOLDER, stale.slice(0, 5)])
	_note("%d files under steps/ name godot/%s in a usage comment, %d name %s" % [named, THIS_FOLDER, stale.size(), PREVIOUS_FOLDER])
	return failures

## Everything that is not a step is tutorial 09's too: project.godot (but its name, main scene and user dir), the buses, the figure, the sounds, the materials.
func test_root_is_tutorial_09() -> Array[String]:
	var failures: Array[String] = []
	var tutorial := _tutorial_09()
	if tutorial.is_empty():
		_skip("the root of the project equals the root of tutorial 09", "tutorial 09 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER)
		return failures
	var skipped_lines := ["config/name=", "run/main_scene=", "config/custom_user_dir_name="]
	var theirs := _without_lines(FileAccess.get_file_as_string(tutorial.path_join("project.godot")), skipped_lines)
	var ours := _without_lines(FileAccess.get_file_as_string("res://project.godot"), skipped_lines)
	_expect(failures, theirs.length() > 1000 and theirs == ours, "project.godot differs from tutorial 09's besides its name, its main scene and its user dir")
	var compared := 1
	for file: String in ["default_bus_layout.tres"]:
		_expect(failures, FileAccess.file_exists(tutorial.path_join(file)) and FileAccess.get_sha256(tutorial.path_join(file)) == FileAccess.get_sha256("res://" + file), "%s differs from tutorial 09's" % file)
		compared += 1
	for folder: String in ["character", "sounds", "materials"]:
		var theirs_files := _files_below(tutorial.path_join(folder), folder)
		var ours_files := _files_below(ProjectSettings.globalize_path("res://" + folder), folder)
		_expect(failures, theirs_files.size() > 5 and theirs_files == ours_files, "%s/ holds %d files, tutorial 09's holds %d (or other names)" % [folder, ours_files.size(), theirs_files.size()])
		for file in theirs_files:
			if FileAccess.file_exists("res://" + file):
				_expect(failures, FileAccess.get_sha256(tutorial.path_join(file)) == FileAccess.get_sha256("res://" + file), "%s differs from tutorial 09's" % file)
				compared += 1
	_note("project.godot, the bus layout and %d more files compared byte for byte" % (compared - 2))
	return failures

func _without_lines(text: String, prefixes: Array) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var skip := false
		for prefix: String in prefixes:
			skip = skip or line.begins_with(prefix)
		if not skip:
			kept.append(line)
	return "\n".join(kept)

## The files below a folder as "folder/sub/file" paths, sorted; .import and .uid files (the editor writes them) do not count.
func _files_below(absolute: String, relative: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(absolute)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_files_below(absolute.path_join(sub), relative.path_join(sub)))
	for file in dir.get_files():
		if not file.ends_with(".import") and not file.ends_with(".uid"):
			found.append(relative.path_join(file))
	found.sort()
	return found

func test_project_settings() -> Array[String]:
	var failures: Array[String] = []
	for action in ACTIONS:
		_expect(failures, ProjectSettings.has_setting("input/" + action), "no %s action" % action)
	_expect(failures, ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "the physics engine is not Jolt")
	_expect(failures, _physical_keys("toggle_gizmos") == ["F3"], "toggle_gizmos is %s, expected F3" % [_physical_keys("toggle_gizmos")])
	_expect(failures, _physical_keys("toggle_watch") == ["F4"], "toggle_watch is %s, expected F4" % [_physical_keys("toggle_watch")])
	_expect(failures, _physical_keys("open_settings") == ["O"], "open_settings has the keys %s, expected O" % [_physical_keys("open_settings")])
	_expect(failures, ProjectSettings.get_setting("layer_names/3d_render/layer_3") == "Body", "render layer 3 is not named Body")
	_expect(failures, ProjectSettings.get_setting("application/run/main_scene") == "res://steps/%s/main.tscn" % FINAL_STEP, "the main scene is not the final step")
	_expect(failures, ProjectSettings.get_setting("application/config/name") == "Phaix Godot 10 - Numbered Doors", "the project is named '%s'" % ProjectSettings.get_setting("application/config/name"))
	return failures

## The text on the screen: every step is step 0's HUD, because a number on a door is a node of the door, not a label of the screen.
## The Input Map is tutorial 09's.
func test_hud_and_input_map() -> Array[String]:
	var failures: Array[String] = []
	var reference := _hud_texts(STEPS[0])
	var hint := reference.get("Stats/DebugHint", "") as String
	_expect(failures, hint == "F3  gizmos      F4  watch it plan", "step 0 says '%s' as its debug hint" % hint)
	_expect(failures, reference.get("Stats/SettingsHint") == "O  settings", "step 0 says '%s' as its settings hint" % reference.get("Stats/SettingsHint"))
	_expect(failures, reference.size() >= 10, "found only %d labels in the HUD of step 0" % reference.size())
	for step in STEPS:
		var texts := _hud_texts(step)
		for label_path: String in reference:
			_expect(failures, texts.get(label_path) == reference[label_path], "%s: %s says '%s' in the HUD scene, step 0 says '%s'" % [step, label_path, texts.get(label_path), reference[label_path]])
		var extra: Array[String] = []
		for label_path: String in texts:
			if not reference.has(label_path):
				extra.append(label_path)
		_expect(failures, extra.is_empty(), "%s: the HUD scene has the labels %s that step 0 does not have" % [step, extra])
		var main := await _load_step(step, false)
		await _wait_physics(5)
		var label := main.get_node_or_null("HUD/Stats/DebugHint") as Label
		_expect(failures, label != null and label.text == hint, "%s: the hint on the screen says '%s', step 0 says '%s'" % [step, label.text if label != null else "no label", hint])
		await _unload(main)
	_note("%d labels in the HUD, the same text in all %d steps" % [reference.size(), STEPS.size()])
	var tutorial := _tutorial_09()
	if tutorial.is_empty():
		_skip("hud: the Input Map is the one of tutorial 09", "tutorial 09 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER, false)
		return failures
	var theirs := _input_section(tutorial.path_join("project.godot"))
	var ours := _input_section(ProjectSettings.globalize_path("res://project.godot"))
	_expect(failures, theirs.length() > 1000, "found no [input] section in the project.godot of tutorial 09")
	_expect(failures, theirs == ours, "the [input] section of project.godot is not the one of tutorial 09")
	return failures

## The text of every label of a step's HUD scene, by its path below the HUD.
func _hud_texts(step: String) -> Dictionary:
	var texts := {}
	var main := (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
	var hud := main.get_node("HUD")
	for label: Node in hud.find_children("*", "Label", true, false):
		texts[str(hud.get_path_to(label))] = (label as Label).text
	main.free()
	return texts

## Everything from the line "[input]" to the end of a project.godot.
func _input_section(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("\n[input]")
	return text.substr(start) if start >= 0 else ""

## The README is the public text of the episode: its credits name the folders that stand in the project (the figure, the
## sounds, with the files that carry the licences), and every project path it names in backticks exists. In the public repo the README is the short one
## for viewers ("Project files for tutorial NN ...": the steps, the tests command, the credits of the licences), so it is checked for what it says; the
## project's own long README has the full list.
func test_readme_matches_folders() -> Array[String]:
	var failures: Array[String] = []
	var readme := FileAccess.get_file_as_string("res://README.md")
	var viewers := readme.contains("Project files for tutorial")
	_expect(failures, readme.length() > (1000 if viewers else 2000), "README.md is missing or has only %d characters" % readme.length())
	var musts: Array[String] = ["Animated Characters Protagonists", "character/License.txt", "RPG Audio", "sounds/CREDITS.md", "Kenney", "CC0", "run_tests.gd"]
	if not viewers:
		musts.append_array(["`character/`", "`sounds/`", "--only="])
	for must: String in musts:
		_expect(failures, readme.contains(must), "README.md does not say \"%s\"" % must)
	for forbidden: String in ["Blender", "kit_", "capture.gd", "capture.tscn", "check_coverage", "make_materials", "17.9", "9.6:1", "0.04", "0.95, 0.85", "tools/variants"]:
		_expect(failures, not readme.contains(forbidden), "README.md still says \"%s\"" % forbidden)
	_expect(failures, FileAccess.get_file_as_string("res://character/License.txt").contains("CC0") and FileAccess.get_file_as_string("res://sounds/CREDITS.md").contains("CC0"), "character/License.txt or sounds/CREDITS.md does not say CC0")
	var named := RegEx.create_from_string("`((?:tools|tests|steps|materials|sounds|character)/[A-Za-z0-9_./-]*)`")
	var checked := 0
	var seen: Array[String] = []
	for found in named.search_all(readme):
		var path := found.get_string(1)
		if seen.has(path) or path.contains("NN_") or path.contains("<"):
			continue
		seen.append(path)
		checked += 1
		_expect(failures, FileAccess.file_exists("res://" + path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + path)), "README.md names `%s`, which does not exist" % path)
	_expect(failures, checked >= (4 if viewers else 8), "README.md names only %d project paths" % checked)
	_note("%d paths named in the README exist" % checked)
	return failures

#endregion

#region Chains (pure data, no scene)

## A chain of any step's script.
func _new_chain(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.0) -> RefCounted:
	return chain_script.new(chain_seed, goal_room, chance)

## The room_chain.gd of a step.
func _chain_script(step: String) -> GDScript:
	return load("res://steps/%s/room_chain.gd" % step) as GDScript

## What the chain's Type enum calls the goal room.
func _goal_type(chain_script: GDScript) -> int:
	return (chain_script.get_script_constant_map()["Type"] as Dictionary)["GOAL"]

func _same_plans(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _same_plan(a[i], b[i]):
			return false
	return true

## One plan against another: the room, its lock, its props and its lamp.
func _same_plan(a: Object, b: Object) -> bool:
	if a.index != b.index or a.type != b.type or a.transform != b.transform or a.bounds != b.bounds:
		return false
	return a.locked == b.locked and a.key_spot == b.key_spot and a.props == b.props and a.lamp == b.lamp

## All plans of a chain up to and including its goal room (at most `limit` plans).
func _plans_to_goal(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.4, limit := 400) -> RefCounted:
	var chain := _new_chain(chain_script, chain_seed, goal_room, chance)
	while chain.plans.size() < limit:
		var plan: Object = chain.next_plan()
		if plan.type == _goal_type(chain_script):
			break
	return chain

## Every step plans the run of step 0 for every seed: a number on a door never touches the generator.
func test_steps_plan_the_same() -> Array[String]:
	var failures: Array[String] = []
	var scripts: Array[GDScript] = []
	for step in STEPS:
		scripts.append(_chain_script(step))
	var rooms := 0
	for chain_seed in range(1, PLAN_SEEDS + 1):
		if chain_seed % 20 == 0:
			await process_frame
		var base: Array = _plans_to_goal(scripts[0], chain_seed, GOAL_ROOM).plans
		rooms += base.size()
		for i in range(1, scripts.size()):
			var other: Array = _plans_to_goal(scripts[i], chain_seed, GOAL_ROOM).plans
			_expect(failures, _same_plans(base, other), "seed %d: %s plans another run than %s" % [chain_seed, STEPS[i], STEPS[0]])
		if failures.size() > 8:
			return failures
	_note("%d seeds, %d plans each step, all %d steps plan the same rooms, locks, keys, props and lamps" % [PLAN_SEEDS, rooms, STEPS.size()])
	return failures

#endregion

#region Walking the real player

## Runs tick once per physics tick until it returns true. (With Engine.time_scale above 1
## several ticks happen per frame, and `await physics_frame` would only see one of them.)
func _drive(tick: Callable) -> void:
	var driver := Driver.new()
	driver.process_priority = -100
	driver.tick = tick
	root.add_child(driver)
	await driver.finished
	root.remove_child(driver)
	driver.queue_free()

## Walks until the player is in room `goal`. dawdle: ticks of standing still at the start and at every new door.
func _walk(level: Node3D, pilot: RefCounted, goal: int, dawdle: int, on_tick: Callable) -> bool:
	var state := {"budget": 1500 * goal, "wait": dawdle, "target": pilot.door_index}
	await _drive(func() -> bool:
		if state["wait"] > 0:
			state["wait"] -= 1
		else:
			pilot.physics_step()
			if pilot.door_index != state["target"]:
				state["target"] = pilot.door_index
				state["wait"] = dawdle
				pilot.release()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.current >= goal or state["budget"] <= 0)
	pilot.release()
	return level.current >= goal

## Walks until the run is finished (the player stands on the goal pad) or the budget of ticks is gone.
func _walk_to_finish(level: Node3D, pilot: RefCounted, budget: int, on_tick: Callable) -> bool:
	var state := {"budget": budget}
	await _drive(func() -> bool:
		pilot.physics_step()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.state == STATE_FINISHED or state["budget"] <= 0)
	pilot.release()
	return level.state == STATE_FINISHED

#endregion

#region Tutorial 10: a number on every door

func _label_of(door: Node) -> Label3D:
	return door.get_node_or_null(LABEL_PATH) as Label3D

func _door_scene(step: String) -> Node3D:
	return (load("res://steps/%s/door.tscn" % step) as PackedScene).instantiate() as Node3D

## The room type's scene in the tree (its door is made in _ready), at the origin. The CSG shell builds its collision a few
## physics frames later: tests that cast rays wait for it.
func _room_with_door(step: String, room_type: String) -> Node3D:
	var room := (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	return room

## The height of the ink of the digits 0 to 9 in pixels of the font size: the smallest and the largest.
func _digit_ink_range(font: Font, font_size: int) -> Vector2:
	var server := TextServerManager.get_primary_interface()
	var font_rid := font.get_rids()[0]
	var smallest := INF
	var largest := 0.0
	for digit in 10:
		var glyph := server.font_get_glyph_index(font_rid, font_size, "0".unicode_at(0) + digit, 0)
		var points: PackedVector3Array = server.font_get_glyph_contours(font_rid, font_size, glyph)["points"]
		var low := INF
		var high := -INF
		for point in points:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		smallest = minf(smallest, high - low)
		largest = maxf(largest, high - low)
	return Vector2(smallest, largest)

## The smallest of the digits' ink heights: what the legibility floor is measured with.
func _digit_ink_px(font: Font, font_size: int) -> float:
	return _digit_ink_range(font, font_size).x

func _label_font(label: Label3D) -> Font:
	return label.font if label.font != null else ThemeDB.fallback_font

## The widest a number of this many digits gets, in metres: the widest digit that many times (with the font's spacing), the
## slant of a slanted font at the top of the ink, and a rim on both sides.
func _number_width(label: Label3D, digits: int) -> float:
	var font := _label_font(label)
	var widest := 0.0
	for digit in 10:
		widest = maxf(widest, font.get_string_size(str(digit).repeat(digits), HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
	var slant := absf((font as FontVariation).variation_transform.y.x) * _digit_ink_px(font, label.font_size) if font is FontVariation else 0.0
	return (widest + slant + 2.0 * label.outline_size) * label.pixel_size

## Where the digits' ink lies in the label's own space (metres): the bottom and the top, from the line box and the font's
## ascent; with the rim, the rim's edge.
func _ink_range(label: Label3D, with_rim: bool) -> Vector2:
	var font := _label_font(label)
	var baseline := (font.get_height(label.font_size) / 2.0 - font.get_ascent(label.font_size)) * label.pixel_size
	var rim := label.outline_size * label.pixel_size if with_rim else 0.0
	return Vector2(baseline - rim, baseline + _digit_ink_px(font, label.font_size) * label.pixel_size + rim)

## How tall a digit of this label looks on a screen of `height` pixels from `distance` metres, with a vertical field of view.
func _digit_screen_px(label: Label3D, distance: float, height := SCREEN_HEIGHT, fov := REST_FOV) -> float:
	var world := _digit_ink_px(_label_font(label), label.font_size) * label.pixel_size
	return world * height * 0.5 / (distance * tan(deg_to_rad(fov) / 2.0))

static func _relative_luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

## The size of one step of a depth buffer of `bits` bits at `distance` metres, for a camera with this near plane.
static func _depth_step(distance: float, near: float, bits := DEPTH_BITS) -> float:
	return distance * distance / (near * pow(2.0, bits))

## What the scene says about the number's place: it floats a little in front of what is behind it, enough for the depth buffer.
func _depth_problems(offset: float, near: float) -> Array[String]:
	var problems: Array[String] = []
	var step := _depth_step(FAR_VIEW, near)
	if offset < 4.0 * step:
		problems.append("the number is %.4f m in front of the face behind it, the depth buffer steps %.5f m at %.0f m: it z-fights" % [offset, step, FAR_VIEW])
	if offset > 0.03:
		problems.append("the number is %.3f m in front of the face behind it: it floats" % offset)
	return problems

## What the number on a door says, in this step: the plain number up to step 2, four digits with zeros in front on the plate.
func _number_text(step: String, number: int) -> String:
	return "%04d" % number if step == PLATE_STEP else str(number)

## The step a level was loaded from (its scene file's folder).
func _step_of(level: Node3D) -> String:
	return level.get_script().resource_path.get_base_dir().get_file()

func _camera_near(step: String) -> float:
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate()
	var near: float = (player.get_node("Head/Camera3D") as Camera3D).near
	player.free()
	return near

func test_label_scene_all() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		failures.append_array(test_label_scene(step))
	return failures

func test_label_scene(step: String) -> Array[String]:
	var failures: Array[String] = []
	var door := _door_scene(step)
	var labels := door.find_children("*", "Label3D", true, false)
	_expect(failures, door.find_children("*", "CSGShape3D", true, false).is_empty() == (step != PLATE_STEP), "%s: the door has CSG shapes: %s, expected them in step 3 only" % [step, door.find_children("*", "CSGShape3D", true, false).size()])
	if step == STEPS[0]:
		_expect(failures, labels.is_empty(), "%s: the door has a Label3D before step 1" % step)
		door.free()
		return failures
	_expect(failures, labels.size() == 1, "%s: the door has %d Label3D nodes, expected one" % [step, labels.size()])
	var label := _label_of(door)
	if label == null:
		door.free()
		return failures + ["%s: no Number at Hinge/Number" % step]
	var hinge := door.get_node("Hinge") as AnimatableBody3D
	var plated := step == PLATE_STEP
	_expect(failures, label.get_parent() == hinge, "%s: the number is a child of %s, not of the hinge: it would not swing with the leaf" % [step, label.get_parent().name])
	_expect(failures, is_equal_approx(label.position.x, -LEAF_WIDTH / 2.0) and is_equal_approx(label.position.y, NUMBER_HEIGHT), "%s: the number is at x %.2f, y %.2f; the middle of the leaf is %.2f, the number's height %.2f" % [step, label.position.x, label.position.y, -LEAF_WIDTH / 2.0, NUMBER_HEIGHT])
	_expect(failures, is_equal_approx(label.position.z, 0.068 if plated else 0.06) and label.basis.is_equal_approx(Basis.IDENTITY), "%s: the number is at z %.3f (the face at %.3f), or turned" % [step, label.position.z, LEAF_FACE])
	_expect(failures, label.billboard == BaseMaterial3D.BILLBOARD_DISABLED and not label.fixed_size and not label.no_depth_test, "%s: the number is a billboard, a fixed size or ignores depth: it must be part of the leaf" % step)
	_expect(failures, is_equal_approx(label.pixel_size, 0.001) and label.font_size == 96, "%s: pixel_size %.4f, font_size %d, expected 0.001 and 96" % [step, label.pixel_size, label.font_size])
	_expect(failures, label.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and label.layers == 1, "%s: the number throws a shadow (cast_shadow %d) or is not on layer 1 (layers %d)" % [step, label.cast_shadow, label.layers])
	_expect(failures, label.text == ("7" if step == STEPS[1] else ""), "%s: the scene's text is \"%s\"" % [step, label.text])
	_expect(failures, label.double_sided and label.alpha_cut == Label3D.ALPHA_CUT_DISABLED, "%s: double_sided %s, alpha_cut %d: expected the defaults" % [step, label.double_sided, label.alpha_cut])
	if plated:
		# Step 3 changes four of the label's values against step 2: the place on the field, shaded, no rim, the beige, the font.
		_expect(failures, label.shaded and label.outline_size == 0 and label.modulate == Color(1, 0.82, 0.6, 1) and label.font is FontVariation, "%s: shaded %s, outline_size %d, modulate %s, font %s: expected shaded, no rim, the beige (1, 0.82, 0.6) and a Font Variation" % [step, label.shaded, label.outline_size, label.modulate, label.font])
	else:
		# Steps 1 and 2 keep the defaults: white, a black rim of 12 px, unshaded, the built in font.
		_expect(failures, not label.shaded and label.outline_size == 12 and label.modulate == Color(1, 1, 1, 1) and label.outline_modulate == Color(0, 0, 0, 1) and label.font == null, "%s: shaded %s, outline_size %d, fill %s, rim %s, font %s: expected the defaults" % [step, label.shaded, label.outline_size, label.modulate, label.outline_modulate, label.font])
	# On the leaf, clear of the lock: the number's ink lies inside the leaf, above the lock plate.
	var plain := _ink_range(label, false)
	_expect(failures, label.position.y + plain.x >= LOCK_TOP + DIGIT_MARGIN, "%s: the digits' bottom is at %.3f m, the lock reaches %.2f" % [step, label.position.y + plain.x, LOCK_TOP])
	_expect(failures, label.position.y + plain.y <= LEAF_HEIGHT - DIGIT_MARGIN, "%s: the digits' top is at %.3f m, the leaf ends at %.2f" % [step, label.position.y + plain.y, LEAF_HEIGHT])
	var digits := 4 if plated else 3
	_expect(failures, _number_width(label, digits) <= LEAF_WIDTH / 2.0, "%s: a number of %d digits is %.3f m wide, more than half the leaf (%.2f)" % [step, digits, _number_width(label, digits), LEAF_WIDTH])
	_note("%s: the ink spans %.3f to %.3f m up the leaf, the lock plate ends at %.2f m, the leaf at %.2f m; %d digits are %.3f m wide at most%s" % [step, label.position.y + plain.x, label.position.y + plain.y, LOCK_TOP, LEAF_HEIGHT, digits, _number_width(label, digits), " with the rim of %d px" % label.outline_size if label.outline_size > 0 else ""])
	door.free()
	return failures

## The faces of a baked mesh that look along +z, by their height: area in square metres and the materials they are drawn with.
func _faces_by_z(mesh: ArrayMesh) -> Dictionary:
	var faces := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count, 3):
			var a := vertices[indices[i] if not indices.is_empty() else i]
			var b := vertices[indices[i + 1] if not indices.is_empty() else i + 1]
			var c := vertices[indices[i + 2] if not indices.is_empty() else i + 2]
			# Godot draws a triangle's front where its corners turn clockwise: the normal is (c - a) x (b - a).
			var normal := (c - a).cross(b - a)
			var area := normal.length() / 2.0
			if area < 1e-9 or absf(normal.normalized().z) < 0.999:
				continue
			var key := "%+.4f %s" % [snappedf(a.z, 0.0001) + 0.0, "front" if normal.z > 0.0 else "back"]
			if not faces.has(key):
				faces[key] = {area = 0.0, materials = []}
			faces[key].area += area
			var material := mesh.surface_get_material(surface)
			if not (faces[key].materials as Array).has(material):
				(faces[key].materials as Array).append(material)
	return faces

## A stadium of this many sides per end: the box between the ends and the two half polygons of the cylinders.
static func _stadium_area(straight: float, radius: float, sides: int) -> float:
	return straight * 2.0 * radius + 0.5 * sides * radius * radius * sin(TAU / sides)

## Step 3's number plate: CSG shapes on the hinge, a stadium with a rim around a sunken field, the label on the field.
func test_number_plate() -> Array[String]:
	var failures: Array[String] = []
	var door := _door_scene(PLATE_STEP)
	root.add_child(door)
	await process_frame # CSG builds its mesh on the next frame
	await process_frame
	var plate := door.get_node_or_null("Hinge/NumberPlate") as CSGCombiner3D
	var label := _label_of(door)
	if plate == null:
		door.queue_free()
		return ["no CSGCombiner3D at Hinge/NumberPlate"]
	_expect(failures, plate.position.is_equal_approx(Vector3(-LEAF_WIDTH / 2.0, NUMBER_HEIGHT, LEAF_FACE)) and plate.basis.is_equal_approx(Basis.IDENTITY), "the plate is at %s, expected on the leaf's face at the number (%.2f, %.2f, %.2f)" % [plate.position, -LEAF_WIDTH / 2.0, NUMBER_HEIGHT, LEAF_FACE])
	_expect(failures, plate.gi_mode == GeometryInstance3D.GI_MODE_DISABLED and (door.get_node("Hinge/MeshInstance3D") as GeometryInstance3D).gi_mode == GeometryInstance3D.GI_MODE_DISABLED, "the plate's GI mode is %d, the leaf's %d: SDFGI cannot follow a moving mesh" % [plate.gi_mode, (door.get_node("Hinge/MeshInstance3D") as GeometryInstance3D).gi_mode])
	_expect(failures, not plate.use_collision, "the plate collides: the leaf's box already does")
	# Plate: a box with a cylinder at each end, added up. Field: the same, a little smaller, subtracted.
	var shapes := {}
	for part: String in ["Plate", "Field"]:
		var combiner := plate.get_node_or_null(part) as CSGCombiner3D
		_expect(failures, combiner != null, "the plate has no %s combiner" % part)
		if combiner == null:
			continue
		_expect(failures, combiner.operation == (CSGShape3D.OPERATION_SUBTRACTION if part == "Field" else CSGShape3D.OPERATION_UNION), "%s's operation is %d" % [part, combiner.operation])
		var middle := combiner.get_node_or_null("Middle") as CSGBox3D
		var ends: Array[CSGCylinder3D] = [combiner.get_node_or_null("LeftEnd") as CSGCylinder3D, combiner.get_node_or_null("RightEnd") as CSGCylinder3D]
		_expect(failures, middle != null and ends[0] != null and ends[1] != null and combiner.get_child_count() == 3, "%s is not a box with a cylinder at each end" % part)
		if middle == null or ends.has(null):
			continue
		for end in ends:
			_expect(failures, is_equal_approx(end.radius * 2.0, middle.size.y) and is_equal_approx(end.height, middle.size.z) and is_equal_approx(absf(end.position.x), middle.size.x / 2.0) and absf(end.basis.y.z) > 0.999 and end.material == middle.material, "%s/%s does not round off the box: radius %.3f, height %.3f, at x %.3f, axis %s" % [part, end.name, end.radius, end.height, end.position.x, end.basis.y])
		shapes[part] = {middle = middle, radius = ends[0].radius, sides = ends[0].sides, z = combiner.position.z + middle.position.z - middle.size.z / 2.0}
	if shapes.size() < 2:
		door.queue_free()
		return failures
	var outer: CSGBox3D = shapes["Plate"].middle
	var inner: CSGBox3D = shapes["Field"].middle
	var width := outer.size.x + 2.0 * float(shapes["Plate"].radius)
	_expect(failures, is_equal_approx(width, PLATE_WIDTH) and is_equal_approx(outer.size.y, PLATE_HEIGHT) and is_equal_approx(outer.size.z, PLATE_DEPTH), "the plate is %.3f x %.3f x %.3f m, the narration says %.2f x %.2f x %.3f" % [width, outer.size.y, outer.size.z, PLATE_WIDTH, PLATE_HEIGHT, PLATE_DEPTH])
	_expect(failures, is_equal_approx(inner.size.x, outer.size.x) and inner.size.y < outer.size.y, "the field is not the plate a little smaller: %s against %s" % [inner.size, outer.size])
	var floor_z: float = shapes["Field"].z
	_expect(failures, is_equal_approx(PLATE_DEPTH - floor_z, FIELD_DEPTH) and is_equal_approx(float(shapes["Plate"].z), 0.0), "the field cuts %.4f m into the plate, the narration says %.2f; the plate's back is at %.4f" % [PLATE_DEPTH - floor_z, FIELD_DEPTH, shapes["Plate"].z])
	var door_material := load("res://materials/door.tres") as StandardMaterial3D
	_expect(failures, inner.material == door_material and outer.material != door_material and outer.material is StandardMaterial3D, "the field's shapes are in %s, the plate's in %s: expected the door's material for the field and an own one for the plate" % [inner.material, outer.material])
	# What CSG makes of it: the baked mesh has the rim in front, the floor of the field 1 cm behind it, in the door's material.
	var mesh := plate.bake_static_mesh()
	_expect(failures, mesh != null and mesh.get_surface_count() > 0, "the plate bakes no mesh")
	if mesh == null:
		door.queue_free()
		return failures
	var box := mesh.get_aabb()
	_expect(failures, box.size.is_equal_approx(Vector3(PLATE_WIDTH, PLATE_HEIGHT, PLATE_DEPTH)) and box.position.is_equal_approx(Vector3(-PLATE_WIDTH / 2.0, -PLATE_HEIGHT / 2.0, 0.0)), "the plate's mesh spans %s" % box)
	var faces := _faces_by_z(mesh)
	var rim_key := "%+.4f front" % PLATE_DEPTH
	var floor_key := "%+.4f front" % floor_z
	var back_key := "%+.4f back" % 0.0
	var plate_area := _stadium_area(outer.size.x, shapes["Plate"].radius, shapes["Plate"].sides)
	var field_area := _stadium_area(inner.size.x, shapes["Field"].radius, shapes["Field"].sides)
	var rim_area: float = faces[rim_key].area if faces.has(rim_key) else 0.0
	var floor_area: float = faces[floor_key].area if faces.has(floor_key) else 0.0
	var back_area: float = faces[back_key].area if faces.has(back_key) else 0.0
	_expect(failures, faces.size() == 3, "the plate's mesh has faces along z at %s, expected the back, the floor of the field and the rim" % [faces.keys()])
	_expect(failures, absf(rim_area - (plate_area - field_area)) < 0.0005 and absf(floor_area - field_area) < 0.0005 and absf(back_area - plate_area) < 0.0005, "rim %.5f m2 (expected %.5f), field %.5f (%.5f), back %.5f (%.5f); faces along z: %s" % [rim_area, plate_area - field_area, floor_area, field_area, back_area, plate_area, faces.keys()])
	_expect(failures, faces.has(floor_key) and faces[floor_key].materials == [door_material] and faces.has(rim_key) and faces[rim_key].materials == [outer.material], "the field's floor is drawn in %s, the rim in %s" % [faces.get(floor_key, {}).get("materials"), faces.get(rim_key, {}).get("materials")])
	# The label lies on the field, 3 mm in front of its floor and behind the rim's front; four digits stay in its straight part.
	var above := label.position.z - (plate.position.z + floor_z)
	var steps := above / _depth_step(FAR_VIEW, _camera_near(PLATE_STEP))
	_expect(failures, is_equal_approx(above, ABOVE_FIELD) and label.position.z < plate.position.z + PLATE_DEPTH, "the label is %.4f m in front of the field (the narration: %.3f), the rim's front at %.3f, the label at %.3f" % [above, ABOVE_FIELD, plate.position.z + PLATE_DEPTH, label.position.z])
	_expect(failures, floori(steps) == FIELD_DEPTH_STEPS, "%.4f m are %.1f steps of the depth buffer at %.0f m, the narration says %d" % [above, steps, FAR_VIEW, FIELD_DEPTH_STEPS])
	_expect(failures, is_equal_approx(label.position.x, plate.position.x) and is_equal_approx(label.position.y, plate.position.y), "the label is not in the middle of the plate")
	var ink := _ink_range(label, false)
	_expect(failures, _number_width(label, 4) <= inner.size.x and ink.y - ink.x <= inner.size.y / 2.0 and absf(ink.x + ink.y) / 2.0 <= 0.01, "four digits are %.3f m wide (the field's straight part %.3f), %.3f m tall (the field %.3f), their middle %.3f m off the plate's" % [_number_width(label, 4), inner.size.x, ink.y - ink.x, inner.size.y, (ink.x + ink.y) / 2.0])
	_expect(failures, plate.position.y - PLATE_HEIGHT / 2.0 >= LOCK_TOP + DIGIT_MARGIN and plate.position.y + PLATE_HEIGHT / 2.0 <= LEAF_HEIGHT - DIGIT_MARGIN, "the plate spans %.3f to %.3f m up the leaf, the lock ends at %.2f, the leaf at %.2f" % [plate.position.y - PLATE_HEIGHT / 2.0, plate.position.y + PLATE_HEIGHT / 2.0, LOCK_TOP, LEAF_HEIGHT])
	_note("the plate: %.3f x %.3f x %.3f m, %.0f %% of the leaf's width, %.1f times as wide as tall, %.3f to %.3f m up the leaf (the lock ends at %.2f)" % [width, outer.size.y, outer.size.z, width / LEAF_WIDTH * 100.0, width / outer.size.y, plate.position.y - PLATE_HEIGHT / 2.0, plate.position.y + PLATE_HEIGHT / 2.0, LOCK_TOP])
	_note("baked: the rim %.5f m2 at z %.3f, the field's floor %.5f m2 at z %.3f (%.0f mm deep, in %s), the back %.5f m2; the rim is %.1f cm wide" % [rim_area, PLATE_DEPTH, floor_area, floor_z, (PLATE_DEPTH - floor_z) * 1000.0, door_material.resource_path, back_area, (outer.size.y - inner.size.y) * 50.0])
	_note("the label %.0f mm in front of the field (%.1f steps of a %d bit depth buffer at %.0f m, near %.2f m), %.0f mm behind the rim's front; four digits %.3f x %.3f m, the field's straight part %.3f m" % [above * 1000.0, steps, DEPTH_BITS, FAR_VIEW, _camera_near(PLATE_STEP), (plate.position.z + PLATE_DEPTH - label.position.z) * 1000.0, _number_width(label, 4), ink.y - ink.x, inner.size.x])
	door.queue_free()
	await process_frame
	return failures

## The plate's colours against the door's orange (albedo, nothing of the picture): the rim darker, the digits lighter and of
## the door's hue. The font: the built in one, through a Font Variation that thickens, slants and spaces it.
func test_plate_colours() -> Array[String]:
	var failures: Array[String] = []
	var door_color := (load("res://materials/door.tres") as StandardMaterial3D).albedo_color
	var door := _door_scene(PLATE_STEP)
	var label := _label_of(door)
	var rim := ((door.get_node("Hinge/NumberPlate/Plate/Middle") as CSGBox3D).material as StandardMaterial3D).albedo_color
	var digits := label.modulate
	_expect(failures, _relative_luminance(rim) < _relative_luminance(door_color) and absf(rim.h - door_color.h) * 360.0 < 10.0, "the rim %s is not a darker orange than the door %s" % [rim, door_color])
	_expect(failures, _relative_luminance(digits) > _relative_luminance(door_color) and absf(digits.h - door_color.h) * 360.0 < 10.0 and digits.s < door_color.s, "the digits %s are not a light beige of the door's hue %s" % [digits, door_color])
	var font := label.font as FontVariation
	_expect(failures, font != null and font.base_font == null and font.variation_embolden > 0.0 and font.variation_transform.y.x > 0.0 and font.spacing_glyph > 0, "the font is not the built in one made bolder, slanted and spaced: %s" % font)
	if font != null:
		_note("door %s (hue %.0f degrees, luminance %.3f); rim %s (hue %.0f, luminance %.3f); digits %s (hue %.0f, saturation %.2f against %.2f, luminance %.3f)" % [door_color, door_color.h * 360.0, _relative_luminance(door_color), rim, rim.h * 360.0, _relative_luminance(rim), digits, digits.h * 360.0, digits.s, door_color.s, _relative_luminance(digits)])
		_note("Font Variation of the built in font: embolden %.1f, slant %.2f (the top of a digit %.0f mm to the right), %d px between the digits" % [font.variation_embolden, font.variation_transform.y.x, font.variation_transform.y.x * _digit_ink_px(font, label.font_size) * label.pixel_size * 1000.0, font.spacing_glyph])
	door.free()
	return failures

## The number is part of the swinging body: it turns with the leaf, stays where it is on it and comes back; the plate with it.
func test_label_swings(step: String) -> Array[String]:
	var failures: Array[String] = []
	var door := _door_scene(step)
	root.add_child(door)
	await _wait_physics(3)
	var hinge := door.get_node("Hinge") as AnimatableBody3D
	var label := _label_of(door)
	var plate := door.get_node_or_null("Hinge/NumberPlate") as Node3D
	var closed := label.global_transform
	var local := label.transform
	var pivot := hinge.global_position
	var radius := Vector2(closed.origin.x - pivot.x, closed.origin.z - pivot.z).length()
	var expected_radius := Vector2(label.position.x, label.position.z).length() # the middle of the leaf and a hair in front of it
	_expect(failures, absf(radius - expected_radius) < 0.001 and absf(label.position.x + LEAF_WIDTH / 2.0) < 0.001, "%s: the number is %.3f m from the hinge's axis, expected %.3f" % [step, radius, expected_radius])
	_expect(failures, closed.basis.z.is_equal_approx(door.global_basis.z), "%s: closed, the number does not face the way the door faces" % step)
	_expect(failures, (plate != null) == (step == PLATE_STEP) and (plate == null or plate.get_parent() == hinge), "%s: the plate is %s" % [step, "missing" if plate == null else "on %s, not on the hinge" % plate.get_parent().name])
	var plate_offset := closed.affine_inverse() * plate.global_transform if plate != null else Transform3D()
	door.open()
	await _wait_physics(45)
	var open := label.global_transform
	_expect(failures, door.is_open and label.transform == local, "%s: the number moved on the hinge (its own transform changed) or the door is not open" % step)
	_expect(failures, open.basis.z.dot(-door.global_basis.x) > 0.999, "%s: open, the number faces %s, expected the doorway (the door's -x)" % [step, open.basis.z])
	_expect(failures, open.basis.determinant() > 0.0 and open.basis.is_conformal() and is_equal_approx(open.basis.get_scale().x, 1.0), "%s: the swing mirrored or scaled the number" % step)
	var open_radius := Vector2(open.origin.x - pivot.x, open.origin.z - pivot.z).length()
	_expect(failures, absf(open_radius - radius) < 0.001 and absf(open.origin.y - closed.origin.y) < 0.001, "%s: the number left the leaf's arc (%.4f m from the axis, was %.4f)" % [step, open_radius, radius])
	if plate != null:
		_expect(failures, (open.affine_inverse() * plate.global_transform).is_equal_approx(plate_offset), "%s: open, the plate is not where it was under the number" % step)
	var leaf_mesh := hinge.get_node("MeshInstance3D") as MeshInstance3D
	var leaf_box := leaf_mesh.global_transform * leaf_mesh.mesh.get_aabb()
	_expect(failures, leaf_box.grow(LEAF_FACE).has_point(open.origin), "%s: the number is not at the leaf: %s is outside %s" % [step, open.origin, leaf_box])
	var turned := rad_to_deg(closed.basis.z.angle_to(open.basis.z))
	door.close()
	await _wait_physics(45)
	_expect(failures, not door.is_open and label.global_position.distance_to(closed.origin) < 0.001 and label.global_basis.z.dot(closed.basis.z) > 0.9999, "%s: the number is not back where it was when the door shut" % step)
	_note("%s: the swing turned the number%s by %.1f degrees on a circle of %.3f m round the hinge, and it came back to %.5f m of where it was" % [step, " and its plate" if plate != null else "", turned, radius, label.global_position.distance_to(closed.origin)])
	root.remove_child(door)
	door.free()
	return failures

## How big a digit is: about seven centimetres on the door; on a 1080p picture from 1 m, from where the door starts to open (the
## far edge of its trigger) and from the farthest corner of each room. A number is read up close, as on a real door.
func test_label_size(step: String) -> Array[String]:
	var failures: Array[String] = []
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate()
	var fov: float = (player.get_node("Head/Camera3D") as Camera3D).fov
	player.free()
	_expect(failures, fov == REST_FOV, "%s: the camera rests at %.1f degrees vertical, the figures are for %.0f" % [step, fov, REST_FOV])
	var door := _door_scene(step)
	var label := _label_of(door)
	var ink := _digit_ink_range(_label_font(label), label.font_size)
	var metres := ink.x * label.pixel_size
	_expect(failures, absf(metres - DIGIT_METRES) <= 0.005, "%s: a digit is %.3f m tall (%.0f px of a %d px font at %.4f m a pixel), the narration says about %.2f" % [step, metres, ink.x, label.font_size, label.pixel_size, DIGIT_METRES])
	var trigger := door.get_node("Trigger/CollisionShape3D") as CollisionShape3D
	var opens_at := trigger.position.z + (trigger.shape as BoxShape3D).size.z / 2.0
	var font_size := label.font_size
	var pixel_size := label.pixel_size
	var px_near := _digit_screen_px(label, 1.0)
	var px_open := _digit_screen_px(label, opens_at)
	door.free()
	var corners: Array[String] = []
	var farthest_all := 0.0
	for room_type in ROOM_TYPES:
		var room := _room_with_door(step, room_type)
		var room_label := _label_of(room.get("door") as Node)
		var size := ((room.get_node("Inside/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size
		var farthest := 0.0
		for corner_x: float in [-0.5, 0.5]:
			for corner_z: float in [-0.5, 0.5]:
				farthest = maxf(farthest, Vector3(size.x * corner_x, 1.6, size.z * corner_z).distance_to(room_label.global_position))
		farthest_all = maxf(farthest_all, farthest)
		corners.append("%s %.1f m %.0f px" % [room_type, farthest, _digit_screen_px(room_label, farthest)])
		room.queue_free()
	await process_frame
	_note("%s: a digit is %.0f px of a %d px font (smallest of 0 to 9, largest %.0f) at %.3f m a pixel = %.1f cm on the door" % [step, ink.x, font_size, ink.y, pixel_size, metres * 100.0])
	_note("%s: on 1080p a digit is %.0f px from 1 m, %.0f px from %.2f m (where the door starts to open), from the farthest corner: %s" % [step, px_near, px_open, opens_at, "; ".join(corners)])
	return failures

func test_label_depth(step: String) -> Array[String]:
	var failures: Array[String] = []
	var door := _door_scene(step)
	var label := _label_of(door)
	var near := _camera_near(step)
	var plate := door.get_node_or_null("Hinge/NumberPlate") as Node3D
	# In front of the leaf's face, or in step 3 in front of the field's floor (the face right behind it).
	var behind := LEAF_FACE if plate == null else plate.position.z + PLATE_DEPTH - FIELD_DEPTH
	var offset := label.position.z - behind
	door.free()
	failures.append_array(_depth_problems(offset, near))
	# The check finds a number laid on the face (the mistake), a number that floats, and holds for the one we have.
	var on_the_face := _depth_problems(0.0, near)
	var half_millimetre := _depth_problems(0.0005, near)
	var far_out := _depth_problems(0.08, near)
	_expect(failures, not on_the_face.is_empty() and not half_millimetre.is_empty() and not far_out.is_empty() and _depth_problems(0.01, near).is_empty() and _depth_problems(ABOVE_FIELD, near).is_empty(), "the depth check does not tell a laid-on, a fine and a floating number apart")
	var steps := _depth_step(FAR_VIEW, near)
	_note("%s: the number floats %.0f mm in front of the %s; a %d bit depth buffer steps %.2f mm at %.0f m (near plane %.2f m): %.1f steps of margin" % [step, offset * 1000.0, "leaf" if plate == null else "field", DEPTH_BITS, steps * 1000.0, FAR_VIEW, near, offset / steps])
	if step == PLATE_STEP:
		_note("the check wants at least 4 steps (%.2f mm) and at most 3 cm; it finds a number on the face (0 mm: %d problem), one 0.5 mm in front (%d problem), one 8 cm out (%d problem) and passes 3 and 10 mm" % [4.0 * steps * 1000.0, on_the_face.size(), half_millimetre.size(), far_out.size()])
	return failures

## The number faces into the room, the way the door faces; it is never mirrored; from behind the leaf is in the way; and in the
## closed and the open state a ray along its face runs through the room, never into a wall.
func test_label_facing(step: String) -> Array[String]:
	var failures: Array[String] = []
	var first_hits: Array[String] = []
	for room_type in ROOM_TYPES:
		var room := _room_with_door(step, room_type)
		await _wait_physics(10) # the CSG shell builds its collision
		var door := room.get("door") as Node3D
		var label := _label_of(door)
		var exit := room.get_node("Exit") as Marker3D
		var normal := label.global_basis.z
		_expect(failures, normal.dot(exit.global_basis.z) > 0.999, "%s room_%s: the number faces %s, the room is on %s" % [step, room_type, normal, exit.global_basis.z])
		_expect(failures, label.global_basis.determinant() > 0.0 and label.global_basis.x.dot(exit.global_basis.x) > 0.999, "%s room_%s: the number is mirrored" % [step, room_type])
		var clear := _clear_distance(label, door.get_node("Hinge") as CollisionObject3D)
		_expect(failures, clear >= 3.0, "%s room_%s: the first thing in front of the number is %.2f m away: it faces a wall" % [step, room_type, clear])
		# From behind the door, 2 m past it, at eye height: the leaf is the first thing in the way, so the label's back is never seen.
		var behind := door.global_position - door.global_basis.z * 2.0 + Vector3(0.0, 1.6, 0.0)
		var blocker := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(behind, label.global_position, 1))
		_expect(failures, not blocker.is_empty() and blocker.collider == door.get_node("Hinge"), "%s room_%s: a ray from behind the door to its number meets %s first, not the leaf" % [step, room_type, blocker.get("collider")])
		_expect(failures, (door.global_position + door.global_basis.z * 2.0 + Vector3(0.0, 1.6, 0.0) - label.global_position).dot(normal) > 0.0, "%s room_%s: the room side does not see the number's front" % [step, room_type])
		first_hits.append("%s %s (%.1f m clear in front)" % [room_type, str(blocker.collider.name) if not blocker.is_empty() else "nothing", clear])
		room.queue_free()
		await process_frame
	# Open: next to a room, so that there is a wall to hit. The number faces the doorway and then the room behind it.
	var main := await _load_step(step, true, {"goal_room": 8, "chain_seed": 141})
	var level: Node3D = main.get_node("Level")
	var ahead_least := INF
	for index in 6:
		var door := (level.rooms[index] as Node3D).get("door") as Node3D
		var label := _label_of(door)
		_expect(failures, _clear_distance(label, door.get_node("Hinge") as CollisionObject3D) >= 3.0, "%s room %d: closed, the number faces a wall at %.2f m" % [step, index, _clear_distance(label, door.get_node("Hinge") as CollisionObject3D)])
		door.open()
		await _wait_physics(45)
		var ahead := _clear_distance(label, door.get_node("Hinge") as CollisionObject3D)
		ahead_least = minf(ahead_least, ahead)
		_expect(failures, label.global_basis.z.dot(-door.global_basis.x) > 0.999 and ahead >= 1.5, "%s room %d: open, the number faces %s with %.2f m of room in front of it" % [step, index, label.global_basis.z, ahead])
	await _unload(main)
	if step == PLATE_STEP:
		_note("from behind the door, a ray at the number meets the leaf first in all %d room types: %s" % [ROOM_TYPES.size(), "; ".join(first_hits)])
		_note("the number's front is the exit marker's +Z in all %d room types (dot product above 0.999, determinant above 0: not mirrored); open, the nearest thing in front of it over 6 doors of seed 141 is %.2f m away" % [ROOM_TYPES.size(), ahead_least])
	return failures

## How far a ray from the number's face runs before it hits the world (40 m if nothing).
func _clear_distance(label: Label3D, own_body: CollisionObject3D) -> float:
	var space := root.get_world_3d().direct_space_state
	var from := label.global_position + label.global_basis.z * 0.02
	var query := PhysicsRayQueryParameters3D.create(from, from + label.global_basis.z * 40.0, 1, [own_body.get_rid()])
	var hit := space.intersect_ray(query)
	return from.distance_to(hit.position as Vector3) if not hit.is_empty() else 40.0

## What a door's number should be, for the doors that are in the level now: the plan's index and one, on the door of that room.
func _door_number_problems(level: Node3D) -> Array[String]:
	var problems: Array[String] = []
	for index: int in level.rooms:
		var room: Node3D = level.rooms[index]
		var door := room.get("door") as Node3D
		if door == null:
			continue
		var label := _label_of(door)
		var plan_index: int = level.chain.plans[index].index
		if label == null or label.text != _number_text(_step_of(level), plan_index + 1):
			problems.append("room %d: the door says \"%s\", the plan says %s" % [index, label.text if label != null else "(no label)", _number_text(_step_of(level), plan_index + 1)])
		if door.get_parent() != room or label == null or not label.is_visible_in_tree():
			problems.append("room %d: its number is not on its own door, or is hidden" % index)
	return problems

## Opens the newest door of a level again and again until the goal room stands: every door a run makes, none walked through.
func _open_every_door(level: Node3D) -> void:
	while level.chain.plans.size() <= level.chain.goal_index:
		var newest: Node3D = level.rooms[level.chain.plans.size() - 1]
		(newest.get("door") as Node3D).call("open")

func test_numbers_of_every_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var goal_numbers := 0
	var doors := 0
	for chain_seed in range(1, NUMBER_SEEDS + 1):
		var main := await _load_step(step, false, {"goal_room": GOAL_ROOM, "chain_seed": chain_seed})
		var level: Node3D = main.get_node("Level")
		_open_every_door(level)
		var plans: Array = level.chain.plans
		_expect(failures, plans.size() == level.chain.goal_index + 1 and plans[-1].type == Chain.Type.GOAL, "seed %d: the run does not end in the goal room" % chain_seed)
		var problems := _door_number_problems(level)
		for problem in problems:
			failures.append("seed %d: %s" % [chain_seed, problem])
		var seen: Array[int] = []
		for index: int in level.rooms:
			var door := (level.rooms[index] as Node3D).get("door") as Node3D
			if index == plans.size() - 1:
				_expect(failures, door == null and (level.rooms[index] as Node3D).find_children("*", "Label3D", true, false).is_empty(), "seed %d: the goal room has a door or a number" % chain_seed)
			else:
				_expect(failures, door != null and (door.find_children("*", "Label3D", true, false)).size() == 1, "seed %d room %d: a door without exactly one number" % [chain_seed, index])
				seen.append(_label_of(door).text.to_int())
		doors += seen.size()
		seen.sort()
		_expect(failures, seen == range(1, plans.size()), "seed %d: the numbers on the doors are %s, expected 1 to %d" % [chain_seed, seen, plans.size() - 1])
		# The door into the goal says the goal's number, and every other door has a room behind it.
		var last := (level.rooms[plans.size() - 2] as Node3D).get("door") as Node3D
		_expect(failures, _label_of(last).text == _number_text(step, level.chain.goal_index), "seed %d: the door into the goal room says \"%s\", the goal is room %d" % [chain_seed, _label_of(last).text, level.chain.goal_index])
		goal_numbers += 1 if _label_of(last).text == _number_text(step, level.chain.goal_index) else 0
		await _unload(main)
		if failures.size() > 8:
			break
	_expect(failures, goal_numbers == NUMBER_SEEDS or failures.size() > 8, "the door into the goal room said the goal number in %d of %d seeds" % [goal_numbers, NUMBER_SEEDS])
	_note("%d runs of seeds 1-%d to goal room %d: %d doors, each said the plan's index plus one (as \"%s\" for room 5), the door into the goal said %s in %d runs" % [NUMBER_SEEDS, NUMBER_SEEDS, GOAL_ROOM, doors, _number_text(step, 5), _number_text(step, GOAL_ROOM), goal_numbers])
	return failures

## Walking: the number on the door the player goes through is the number the HUD shows on the other side, for a whole run,
## while the rooms behind are freed.
func test_numbers_walked(step: String) -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in WALKED_SEEDS:
		var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": chain_seed})
		var level: Node3D = main.get_node("Level")
		var room_label := main.get_node("HUD/Stats/RoomLabel") as Label
		var state := {"current": 0, "doors": 0, "freed": 0, "most_alive": 0, "ticks": 0, "ticks_at_most": 0, "first_most": "", "wrong": [] as Array[String]}
		var pilot := Autopilot.new(level)
		_fast_forward(true)
		var finished := await _walk_to_finish(level, pilot, 40000, func() -> void:
			var wrong: Array[String] = state["wrong"]
			if level.current != state["current"]:
				var passed := (level.rooms.get(level.current - 1) as Node3D).get("door") as Node3D
				var said := _label_of(passed).text
				if said != _number_text(step, level.current) or room_label.text != "Room %d / %d" % [level.current, level.chain.goal_index]:
					wrong.append("through the door that said \"%s\" the HUD says \"%s\" (room %d)" % [said, room_label.text, level.current])
				state["current"] = level.current
				state["doors"] += 1
			state["freed"] = maxi(state["freed"], level.chain.plans.size() - level.rooms.size())
			state["ticks"] += 1
			if level.rooms.size() > state["most_alive"]:
				state["most_alive"] = level.rooms.size()
				state["ticks_at_most"] = 0
				state["first_most"] = "rooms %s, the player in room %d, doors open %s" % [level.rooms.keys(), level.current, level.rooms.keys().filter(func(index: int) -> bool: return level.rooms[index].door != null and level.rooms[index].door.is_open)]
			if level.rooms.size() == state["most_alive"]:
				state["ticks_at_most"] += 1
			wrong.append_array(_door_number_problems(level).slice(0, 2)))
		_fast_forward(false)
		var wrong_here: Array[String] = state["wrong"]
		_expect(failures, finished, "seed %d: the run did not finish" % chain_seed)
		_expect(failures, wrong_here.is_empty(), "seed %d: %s" % [chain_seed, wrong_here.slice(0, 3)])
		_expect(failures, state["doors"] == level.chain.goal_index and state["freed"] >= level.chain.goal_index - 3 and state["most_alive"] <= 4, "seed %d: %d doors walked through, rooms freed up to %d, at most %d rooms alive" % [chain_seed, state["doors"], state["freed"], state["most_alive"]])
		_note("seed %d: %d doors walked through to goal room %d, each said the number the HUD showed after it; at most %d rooms alive at once (%d of %d ticks; first time: %s), %d freed" % [chain_seed, state["doors"], level.chain.goal_index, state["most_alive"], state["ticks_at_most"], state["ticks"], state["first_most"], state["freed"]])
		await _unload(main)
	return failures

## R, N and a typed seed: a new run numbers its doors from 1 again, whatever the run before had counted or freed.
func test_numbers_restart_and_new_seed(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
	var level: Node3D = main.get_node("Level")
	var room_label := main.get_node("HUD/Stats/RoomLabel") as Label
	var pilot := Autopilot.new(level)
	_fast_forward(true)
	var arrived := await _walk(level, pilot, 5, 0, Callable())
	_fast_forward(false)
	await _wait_physics(10)
	var alive_before: int = level.rooms.size()
	_expect(failures, arrived and level.rooms.size() <= 4 and not level.rooms.has(0), "the walk to room 5 did not free the rooms behind (%d alive)" % level.rooms.size())
	_expect(failures, _door_number_problems(level).is_empty(), "room 5, rooms freed behind: %s" % [_door_number_problems(level)])
	_expect(failures, _label_of((level.rooms[5] as Node3D).get("door") as Node3D).text == _number_text(step, 6), "room 5's door does not say %s" % _number_text(step, 6))
	for how: String in ["regenerate", "next_seed", "typed"]:
		var before_seed: int = level.chain_seed
		match how:
			"regenerate", "next_seed":
				await _action(how)
			"typed":
				level.use_seed("BLUE-FOX")
		await _wait_physics(10)
		_expect(failures, level.current == 0 and level.rooms.size() == 1 and level.rooms.has(0), "%s: the new run has rooms %s" % [how, level.rooms.keys()])
		_expect(failures, (how == "regenerate") == (level.chain_seed == before_seed), "%s: the seed is %d, it was %d" % [how, level.chain_seed, before_seed])
		_expect(failures, _label_of((level.rooms[0] as Node3D).get("door") as Node3D).text == _number_text(step, 1) and room_label.text == "Room 0 / %d" % GOAL_ROOM, "%s: room 0's door says \"%s\", the HUD \"%s\"" % [how, _label_of((level.rooms[0] as Node3D).get("door") as Node3D).text, room_label.text])
		_expect(failures, _door_number_problems(level).is_empty(), "%s: %s" % [how, _door_number_problems(level)])
		# Open two doors: the next rooms are numbered from the plans, 2 and 3.
		(level.rooms[0] as Node3D).get("door").call("open")
		(level.rooms[1] as Node3D).get("door").call("open")
		_expect(failures, _label_of((level.rooms[1] as Node3D).get("door") as Node3D).text == _number_text(step, 2) and _label_of((level.rooms[2] as Node3D).get("door") as Node3D).text == _number_text(step, 3) and _door_number_problems(level).is_empty(), "%s: the doors after room 0 say %s" % [how, [_label_of((level.rooms[1] as Node3D).get("door") as Node3D).text, _label_of((level.rooms[2] as Node3D).get("door") as Node3D).text]])
	_note("walked to room 5 (%d rooms alive, room 0 freed), then R, N and a typed seed: room 0's door said 1 again every time, the next two said 2 and 3" % alive_before)
	await _unload(main)
	return failures

## The check that the numbers are right finds the numbering a player would write first: by the rooms alive, by a counter of
## the doors made (which a restart does not reset), by the room the door is in, and a door with no number at all.
func test_numbers_check_finds_faults() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
	var level: Node3D = main.get_node("Level")
	for room_index in 4:
		(level.rooms[room_index] as Node3D).get("door").call("open")
	_expect(failures, _door_number_problems(level).is_empty(), "the untouched level has wrong numbers: %s" % [_door_number_problems(level)])
	var gone: Node3D = level.rooms[0] # room 0 is freed behind the player: the numbering by the rooms alive only shows then
	level.rooms.erase(0)
	var faults := {
		"counted by the rooms alive": func(index: int) -> String: return _number_text(FINAL_STEP, level.rooms.keys().find(index) + 1),
		"a counter of the doors made, not reset by a restart": func(index: int) -> String: return _number_text(FINAL_STEP, index + 1 + 20),
		"the number of the room the door is in": func(index: int) -> String: return _number_text(FINAL_STEP, index),
		"the plain number, without the zeros in front": func(index: int) -> String: return str(level.chain.plans[index].index + 1),
		"no number": func(_index: int) -> String: return "",
	}
	var found: Array[String] = []
	for fault: String in faults:
		var saved: Dictionary[int, String] = {}
		for index: int in level.rooms:
			var label := _label_of((level.rooms[index] as Node3D).get("door") as Node3D)
			if label != null:
				saved[index] = label.text
				label.text = (faults[fault] as Callable).call(index)
		var problems := _door_number_problems(level)
		_expect(failures, not problems.is_empty(), "the check does not find a numbering %s" % fault)
		found.append("%s: %d wrong doors" % [fault, problems.size()])
		for index: int in saved:
			var label := _label_of((level.rooms[index] as Node3D).get("door") as Node3D) if level.rooms.has(index) else null
			if label != null:
				label.text = saved[index]
	_expect(failures, _door_number_problems(level).is_empty(), "the numbers were not put back after the faults: %s" % [_door_number_problems(level)])
	level.rooms[0] = gone
	_note("the check finds all %d wrong numberings and passes the right one: %s" % [faults.size(), "; ".join(found)])
	await _unload(main)
	return failures

## The code of the number: the door shows what it is told, the level tells it from the plan, nothing else changes.
func test_numbers_code_rules() -> Array[String]:
	var failures: Array[String] = []
	var base_door := _code_lines("res://steps/%s/door.gd" % STEPS[0])
	var base_level := _code_lines("res://steps/%s/level.gd" % STEPS[0])
	for step in STEPS:
		var door_lines := _code_lines("res://steps/%s/door.gd" % step)
		var level_lines := _code_lines("res://steps/%s/level.gd" % step)
		for line in base_door:
			_expect(failures, door_lines.has(line), "%s/door.gd lost a line of step 0: %s" % [step, line])
		for line in base_level:
			_expect(failures, level_lines.has(line), "%s/level.gd lost a line of step 0: %s" % [step, line])
		var door_added: Array[String] = []
		for line in door_lines:
			if not base_door.has(line):
				door_added.append(line)
		var level_added: Array[String] = []
		for line in level_lines:
			if not base_level.has(line):
				level_added.append(line)
		if STEPS.find(step) < STEPS.find(CHAIN_STEP):
			_expect(failures, door_added.is_empty() and level_added.is_empty(), "%s: door.gd adds %s, level.gd adds %s before the numbers come from the plans" % [step, door_added, level_added])
			continue
		var writes := "number_label.text = \"%04d\" % room_number # four digits, zeros in front: 0005" if step == PLATE_STEP else "number_label.text = str(room_number)"
		_expect(failures, door_added == ["@onready var number_label: Label3D = $Hinge/Number", "func set_number(room_number: int) -> void:", writes], "%s/door.gd adds %s" % [step, door_added])
		_expect(failures, level_added == ["room.door.set_number(plan.index + 1) # the room behind it: what the HUD counts once the player is through"], "%s/level.gd adds %s" % [step, level_added])
		# The door never asks the chain or reads a plan; only the level writes a number.
		for line in door_added:
			_expect(failures, not line.contains("chain") and not line.contains("plan"), "%s/door.gd reads the chain: %s" % [step, line])
		for line in level_lines:
			_expect(failures, not (line.contains(".text =") and line.contains("door")), "%s/level.gd writes a door's text itself: %s" % [step, line])
		if step == FINAL_STEP:
			_note("door.gd adds %d lines (the label, set_number and its one line), level.gd adds 1 line: %s" % [door_added.size(), level_added[0]])
	return failures

func _code_lines(path: String) -> Array[String]:
	var lines: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := line.split("##")[0].strip_edges()
		if not code.is_empty() and not code.begins_with("#"):
			lines.append(code)
	return lines

#endregion

#region The game underneath (tutorial 09's final state, with a number on every door)

func _run_snapshot(level: Node3D) -> Array:
	return [level.state, level.current, level.keys, level.run_time, level.player.global_position, level.player.rotation, level.rooms.keys(), level.chain.plans.size(), level.seed_text]

## Everything the plans say, rejected rooms included.
func _plan_summary(plans: Array) -> Array:
	var summary: Array = []
	for plan: Object in plans:
		var rejected: Array = []
		var turned_down: Variant = plan.get("rejected")
		if turned_down != null:
			for r: Object in turned_down:
				rejected.append([r.type, r.reason, r.transform, r.bounds, r.hit])
		summary.append([plan.index, plan.type, plan.transform, plan.bounds, plan.locked, plan.key_spot, plan.props, plan.get("lamp"), rejected])
	return summary

## One run of a seed, `ticks` long, with the autopilot. effects: the camera's head bob and FOV kick.
func _feel_run(step: String, chain_seed: int, effects: bool, ticks: int) -> Dictionary:
	var main := await _load_step(step, true, {"goal_room": 8, "chain_seed": chain_seed})
	var level: Node3D = main.get_node("Level")
	var camera := level.player.get_node("Head/Camera3D") as Camera3D
	camera.set("head_bob", effects)
	camera.set("fov_kick", effects)
	await _wait_physics(30)
	var pilot := Autopilot.new(level)
	var snapshots: Array = []
	var state := {"ticks": 0, "dip": 0.0, "widest": camera.fov}
	_fast_forward(true)
	await _drive(func() -> bool:
		pilot.physics_step()
		state["ticks"] += 1
		state["dip"] = maxf(state["dip"], -camera.position.y)
		state["widest"] = maxf(state["widest"], camera.fov)
		if state["ticks"] % 30 == 0:
			snapshots.append(_run_snapshot(level) + [(level.player.get_node("Head") as Node3D).transform])
		return state["ticks"] >= ticks or level.state == STATE_FINISHED)
	pilot.release()
	_fast_forward(false)
	snapshots.append(_run_snapshot(level) + [(level.player.get_node("Head") as Node3D).transform])
	var feet: Node = level.player.get_node_or_null("Footsteps")
	var result := {snapshots = snapshots, plans = _plan_summary(level.chain.plans), dip = state["dip"], widest = state["widest"], steps = feet.get("steps") if feet != null else 0}
	await _unload(main)
	return result

## A number on a door is for the eye only: the same inputs give the same run, tick for tick, in step 0 (no numbers) and in every
## later step, with the camera effects on and off (positions, rotations, the head, rooms, keys, time, plans).
func test_effects_change_no_movement() -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in MOVEMENT_SEEDS:
		var start := await _feel_run(STEPS[0], chain_seed, true, 900)
		_expect(failures, start.dip > 0.01 and start.widest > REST_FOV + 1.0 and start.steps > 10, "seed %d: the effects did not run (dip %.3f m, widest %.2f degrees, %d steps): the comparison would prove nothing" % [chain_seed, start.dip, start.widest, start.steps])
		for step: String in STEPS.slice(1):
			var on := await _feel_run(step, chain_seed, true, 900)
			_expect(failures, on.snapshots == start.snapshots, "seed %d: the run of %s differs from step 0's" % [chain_seed, step])
			_expect(failures, on.plans == start.plans, "seed %d: the plans of %s differ from step 0's" % [chain_seed, step])
		var off := await _feel_run(FINAL_STEP, chain_seed, false, 900)
		_expect(failures, off.dip == 0.0 and off.widest == REST_FOV, "seed %d: with the effects off the camera still moved (dip %.3f m, widest %.2f)" % [chain_seed, off.dip, off.widest])
		_expect(failures, off.snapshots == start.snapshots, "seed %d: the run of the finished step with the effects off differs from step 0's" % chain_seed)
		_expect(failures, off.plans == start.plans, "seed %d: the plans with the effects off differ" % chain_seed)
		_note("seed %d: %d snapshots (every 30 ticks of 900) equal in step 0 and in steps 1, 2 and 3, with the camera effects on and off (dip %.3f m, widest %.2f degrees, %d steps), the player in room %d" % [chain_seed, start.snapshots.size(), start.dip, start.widest, start.steps, start.snapshots[-1][1]])
	return failures

#endregion

#region The game underneath (tutorial 09's final state)

## Room 2 entered: the door of room 1 starts to close behind the player, room 0 is the oldest room.
func _door_closing_behind_room_2(step: String) -> Node:
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	level.rooms[0].door.open() # builds room 1
	level._on_room_entered(level.player, 1)
	await _wait_physics(45)
	level.rooms[1].door.open() # builds room 2
	await _wait_physics(45)
	level._on_room_entered(level.player, 2)
	return main

## Through the door behind the player the picture goes along the room just left, to the doorway of the one before it.
func test_rooms_wait_for_the_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _door_closing_behind_room_2(step)
	var level: Node3D = main.get_node("Level")
	_expect(failures, level.rooms.has(0), "room 0 went while the door behind the player stood open")
	await _wait_physics(45)
	_expect(failures, not level.rooms.has(0), "room 0 is still there behind the shut door")
	_expect(failures, level.rooms.has(1), "the room just left went with room 0")
	_expect(failures, not level.rooms[1].get_node("Shell/WallEntrance/Opening").visible, "the room just left has no wall at its entrance")
	await _unload(main)
	main = await _door_closing_behind_room_2(step)
	level = main.get_node("Level")
	await _wait_physics(10)
	level.rooms[1].door.open() # the player turned around while the leaf still swings
	await _wait_physics(45)
	_expect(failures, level.rooms.has(0), "room 0 went while the door stood open again")
	level.start()
	if level.has_method("_on_door_closed"):
		level._on_door_closed(2) # a restart is faster than the door of the old run
		_expect(failures, level.rooms.has(0), "the door of the old run took room 0 of the new one")
	else:
		_expect(failures, false, "level.gd has no _on_door_closed")
	await _unload(main)
	return failures

func test_full_run() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP)
	var level: Node3D = main.get_node("Level")
	var room_label := main.get_node("HUD/Stats/RoomLabel") as Label
	var pilot := Autopilot.new(level)
	_fast_forward(true)
	var finished := await _walk_to_finish(level, pilot, 60 * 60 * 5, Callable())
	_fast_forward(false)
	_expect(failures, finished, "the run did not finish (room %d, %.1f s)" % [level.current, level.run_time])
	_expect(failures, level.current == GOAL_ROOM, "finished in room %d" % level.current)
	_expect(failures, room_label.text == "Room %d / %d" % [GOAL_ROOM, GOAL_ROOM], "the HUD says '%s' in the goal room" % room_label.text)
	_expect(failures, level.run_time > 30.0 and level.run_time < 150.0, "the run took %.1f s" % level.run_time)
	_note("full run, seed 42: finished in room %d, %.2f s of game time, %d rooms made, %d alive at the end" % [level.current, level.run_time, level.chain.plans.size(), level.rooms.size()])
	await _unload(main)
	return failures

func _state(player: CharacterBody3D) -> String:
	var tree := player.get_node("Body/AnimationTree") as AnimationTree
	return (tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).get_current_node()

func test_restart() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var tree := player.get_node("Body/AnimationTree") as AnimationTree
	Input.action_press("move_forward")
	await _wait_physics(30)
	Input.action_release("move_forward")
	await _action("regenerate")
	await _wait_physics(40)
	_expect(failures, player.global_position.distance_to(Vector3(0.0, 0.0, 3.5)) < 0.05, "the player is at %s" % player.global_position)
	_expect(failures, _state(player) == "Move", "the tree is in %s" % _state(player))
	_expect(failures, is_zero_approx(tree.get("parameters/Move/blend_position")), "blend position %.2f" % tree.get("parameters/Move/blend_position"))
	await _unload(main)
	return failures

func test_scene_runs(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	for i in 30:
		await process_frame
	_expect(failures, is_instance_valid(main) and main.is_inside_tree(), "scene left the tree")
	await _unload(main)
	return failures

## The autopilot walks the finished game from the first door to the goal for seeds 1-200. It has no eyes and never steers around
## anything, so a place where the player can be held for good shows up as a run that stops moving (this is how the end of the open
## door leaf was found once). A run is about 3600 physics ticks, so the seeds are split over SWEEP_WORKERS processes
## (tools/sweep_seeds.gd), each at 8 times real time (the engine's limit of 8 physics steps per frame; faster, Jolt warns about
## running out of jobs). A seed walks the same way in any of them. Every door the run goes through says the number the HUD shows after it.
func test_autopilot_seed_sweep() -> Array[String]:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(_save_dir)
	var per_worker := ceili(float(SWEEP_SEEDS) / SWEEP_WORKERS)
	var workers: Array[Dictionary] = []
	for index in SWEEP_WORKERS:
		var first := index * per_worker + 1
		var last := mini(first + per_worker - 1, SWEEP_SEEDS)
		if first > last:
			continue
		var out := _save_dir.path_join("sweep_%d.txt" % index)
		DirAccess.remove_absolute(out)
		var arguments := ["--headless", "--quiet", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/sweep_seeds.gd", "--", "--from=%d" % first, "--to=%d" % last, "--out=%s" % out]
		var pid := OS.create_process(OS.get_executable_path(), arguments)
		_expect(failures, pid > 0, "could not start the sweep for seeds %d-%d" % [first, last])
		workers.append({"pid": pid, "out": out, "first": first, "last": last})
	while workers.any(func(worker: Dictionary) -> bool: return worker["pid"] > 0 and OS.is_process_running(worker["pid"])):
		await create_timer(1.0).timeout
	var held: Array[String] = []
	var wrong: Array[String] = []
	var walked := 0
	var doors := 0
	var longest := 0
	for worker in workers:
		var text := FileAccess.get_file_as_string(worker["out"])
		var lines := text.strip_edges().split("\n", false)
		_expect(failures, lines.size() > 0 and lines[-1] == "done", "the sweep for seeds %d-%d did not finish (%d lines in %s)" % [worker["first"], worker["last"], lines.size(), worker["out"]])
		for line in lines:
			var parts := line.split(" ")
			if parts[0] == "ok":
				walked += 1
				longest = maxi(longest, int(parts[2]))
				doors += int(parts[3])
			elif parts[0] == "numbers":
				wrong.append("seed %s, room %s: %s" % [parts[1], parts[2], " ".join(parts.slice(3))])
			elif parts[0] == "held":
				walked += 1
				held.append("seed %s: held in room %s at %s after %s ticks" % [parts[1], parts[2], " ".join(parts.slice(3, parts.size() - 1)), parts[-1]])
		DirAccess.remove_absolute(worker["out"])
	_expect(failures, walked == SWEEP_SEEDS, "%d of %d seeds were walked" % [walked, SWEEP_SEEDS])
	_expect(failures, held.is_empty(), "%d of %d seeds did not reach the goal: %s" % [held.size(), SWEEP_SEEDS, held.slice(0, 4)])
	_expect(failures, wrong.is_empty(), "%d doors said a number other than the plan's or the HUD's: %s" % [wrong.size(), wrong.slice(0, 4)])
	_expect(failures, doors == SWEEP_SEEDS * GOAL_ROOM, "%d doors were gone through in %d runs, expected %d: the number check does not cover every door" % [doors, SWEEP_SEEDS, SWEEP_SEEDS * GOAL_ROOM])
	_note("seeds 1-%d to goal room %d: %d of %d runs reached the goal (the longest took %d ticks, %.1f s of game time); %d doors gone through, each said the number the HUD showed after it; %d wrong" % [SWEEP_SEEDS, GOAL_ROOM, walked - held.size(), SWEEP_SEEDS, longest, longest / 60.0, doors, wrong.size()])
	return failures

#endregion

#region Harness

func _run(test_name: String, test: Callable) -> void:
	if not _selected(test_name):
		return
	await process_frame # the engine empties its message queue between tests: the chain tests build thousands of room scenes
	_notes.clear()
	_skipped_whole = false
	var failures: Array[String] = await test.call()
	_report(test_name, failures)

func _selected(test_name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only=") and not test_name.contains(argument.trim_prefix("--only=")):
			return false
	return true

func _report(test_name: String, failures: Array[String]) -> void:
	var script_errors := _script_errors.count - _script_errors_reported
	_script_errors_reported = _script_errors.count
	if script_errors > 0: # the test stopped at the failing line and the engine returned an empty array, which would read as a pass
		failures.insert(0, "the test stopped with a script error: see the log")
	if failures.is_empty() and _skipped_whole:
		return
	if failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
		for note in _notes:
			print("        ", note)
		return
	_failed += 1
	print("FAIL  ", test_name)
	for message: String in failures.slice(0, 8):
		print("        ", message)
	if failures.size() > 8:
		print("        ... and %d more" % (failures.size() - 8))
	for note in _notes:
		print("        (measured) ", note)

## whole: the test stops here, so it is neither a pass nor a fail; false: the rest of the test ran and passes.
func _skip(test_name: String, reason: String, whole := true) -> void:
	_skipped += 1
	_skipped_whole = _skipped_whole or whole
	print("SKIP  ", test_name)
	print("        ", reason)

func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

## A figure the running test measured: printed under its PASS line, for the plan's "Measured" and the voice.
func _note(text: String) -> void:
	_notes.append(text)

## Instances a step's main scene. By default it waits until the CSG shapes have built their collision.
## props are set on the Level before it enters the tree (goal_room, seed_text, lock_chance ...; "chain_seed" is the
## text of the seed's digits). "settings_path" is the file of the settings box.
## Every level gets a fresh temporary save file unless props bring one, and so does the settings box.
func _load_step(step: String, settle := true, props := {}) -> Node:
	var scene: PackedScene = load("res://steps/%s/main.tscn" % step)
	var main := scene.instantiate()
	var level := main.get_node("Level")
	if not props.has("save_path"):
		level.set("save_path", _fresh_save_path())
	for key: String in props:
		if key == "settings_path":
			continue
		if key == "chain_seed":
			level.set("seed_text", str(props[key]))
		else:
			level.set(key, props[key])
	var menu := main.get_node_or_null("HUD/Settings")
	if menu != null: # the settings box reads and writes a file of its own
		menu.set("save_path", props.get("settings_path", _fresh_settings_path()))
	root.add_child(main)
	if settle:
		await _wait_physics(10)
	return main

func _unload(main: Node) -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down", "jump", "walk"]:
		Input.action_release(action)
	for sound: Node in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.call("stop") # a sound that still plays when its player is freed is reported as leaked at exit (Godot issue 76745)
	root.remove_child(main)
	main.free()
	await process_frame

## A path in the temporary test folder that no file exists at.
func _fresh_save_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("best_times_%d.json" % _save_counter)

func _fresh_settings_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("settings_%d.json" % _save_counter)

func _wipe_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir):
		return
	for file in DirAccess.get_files_at(_save_dir):
		DirAccess.remove_absolute(_save_dir.path_join(file))
	DirAccess.remove_absolute(_save_dir)

## Runs the simulation faster than real time with the same 1/60 s steps: the engine ticks
## SPEED_UP times as often and hands out SPEED_UP times the delta of each (smaller) tick.
func _fast_forward(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEED_UP if on else 1)
	Engine.time_scale = float(SPEED_UP) if on else 1.0

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame

## The names of an action's keyboard keys ("F3"), by physical key.
func _physical_keys(action: StringName) -> Array[String]:
	var keys: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
	return keys

#endregion
