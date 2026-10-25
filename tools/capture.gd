extends Node
## Plays the game through the real input actions and records it: stills as PNG files, or, in Movie Maker mode, a short
## walkthrough with its sound. Needs a window and the Forward+ renderer (tutorial 09's fog and GI exist only there); the
## video footage comes from tools/shots.gd, this is the quick check: the same three moments of seed 141 in every step
## (room 0 from where the player starts, the vault, the wide room), so the steps compare picture by picture, with the
## squint test on every picture (blurred, does the door still stand out from the wall around it by its value?).
## Tutorial 11 adds what the numbers on the doors need a real picture for:
##   - numbers.txt: how a number is seen in the rendered frame, per step and distance (the room 0 door from 4 m and from
##     the entrance, the vault, the wide room, the long hall from its entrance, 16 m): the digits' height in pixels
##     (scaled to a 1080p picture), the contrast of the digits against the door behind them and of their rim against the
##     door (WCAG ratios of the pixels, fog and tone mapping included), and the squint test of the number itself (blurred to an
##     eighth, how much does the number's patch of the door change?);
##   - the evidence of the steps: a number laid on the leaf's face against one a hair in front of it (z-fighting, in the
##     long hall and in room 0), the back of the door (the leaf hides the number, and step 3 has switched its back off), the door into
##     the goal room, a door half open with its number.
## Stills (PNG files and the text tables, plus the mouse and clipboard checks that only work in a window):
##   godot --path godot/11-numbered-doors res://tools/capture.tscn -- --out=/abs/dir
## Movie (the finished game, seed 141 to the goal pad; convert the .avi with ffmpeg afterwards):
##   godot --path godot/11-numbered-doors --write-movie /abs/file.avi --fixed-fps 30 res://tools/capture.tscn
## --out defaults to docs/captures. `-- --mode=stills` or `-- --mode=movie` overrides the mode.
## Headless dry run (no pictures; the walks and every check still run):
##   godot --headless --fixed-fps 60 --path godot/11-numbered-doors res://tools/capture.tscn
## The exit code is 1 if a screenshot could not be saved or a check failed.
##
## Saves: every level gets its own temporary best_times and settings files (OS temp dir, wiped first), so the
## real best times and settings of the machine are never read or written.

const Autopilot := preload("autopilot.gd")

const SETTLE_TICKS := 60 ## Physics ticks to let a fresh scene build its shapes, shadows, fog and GI.
const SHORT_GOAL := 6 ## The goal room of the quick runs.
const STATE_FINISHED := 2
const SEED := "141" ## Seed 141: rooms 0 to 6 are every room type once (straight, left turn, vault, wide, long, right turn, goal), no lock.
const BOX_SEED := "BLUE-FOX" ## What the window checks type into the seed box.
const STEPS: Array[String] = ["step_00_start", "step_01_label_on_the_leaf", "step_02_numbers_from_the_chain", "step_03_readability_pass"]
const FINAL_STEP := "step_03_readability_pass"
const MOMENTS: Array[int] = [0, 2, 3] ## The rooms of the stills: room 0 (straight), room 2 (the vault), room 3 (the wide room).
const SETTLE_IN_ROOM := 45 ## Physics ticks after the player enters a room before its picture.
const SQUINT_SCALE := 8 ## The squint: the picture shrunk to an eighth and back, the details gone.
const SQUINT_CONTRAST := 0.2 ## The door's value must differ from the wall around it by this much (Weber contrast), in every step.
const SQUINT_NUMBER_COST := 0.07 ## What a number may take from the door's squint contrast of step 0's picture of the same moment.
const BLACK := 0.05 ## A pixel darker than this (luminance, 0 to 1) is crushed black.
const MOST_BLACK := 0.01 ## The share of the picture below its HUD rows that may be crushed black (no crushed black over areas).

var _out_dir := ""
var _failures := 0
var _main: Node
var _level: Node3D
var _save_count := 0
var _squint_reference: Dictionary[String, float] = {} ## Step 0's squint contrast per moment ("-room-0" ...).
var _squint: Array[String] = ["picture                                      door  wall  contrast  door hue  black"]

func _ready() -> void:
	_run()

func _run() -> void:
	await get_tree().process_frame # the scene tree is busy setting up in _ready
	_out_dir = _read_argument("--out", ProjectSettings.globalize_path("res://docs/captures"))
	var movie := OS.has_feature("movie")
	match _read_argument("--mode", ""):
		"movie":
			movie = true
		"stills":
			movie = false
	if movie:
		await _movie()
	else:
		DirAccess.make_dir_recursive_absolute(_out_dir)
		await _stills()
		await _window_checks()
	_release_inputs()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clean_saves()
	print("capture finished, %d problems" % _failures)
	OS.delay_msec(250) # the audio server lets go of the last sounds on the clock (Godot issue 76745)
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)

#region Stills

func _stills() -> void:
	# The same three moments of seed 141 in every step: the steps side by side, the numbers on the doors in each.
	for i in STEPS.size():
		await _walk_and_shoot(STEPS[i], "%02d-%s" % [i, STEPS[i].substr(8).replace("_", "-")], MOMENTS)
	if DisplayServer.get_name() != "headless":
		_save_text("squint.txt", "\n".join(_squint))
	await _numbers_table()
	await _evidence()

	# The real thing: the finished game, seed 141, the whole run.
	_load(FINAL_STEP, SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	var finisher := Autopilot.new(_level)
	await _drive_until(finisher, func() -> bool: return _level.state == STATE_FINISHED, 150 * 60)
	finisher.release()
	await _ticks(15)
	await _save("03-finished")
	await _unload()

## Walks seed 141 with the autopilot and takes a picture SETTLE_IN_ROOM ticks after the player enters each room of `rooms`
## (room 0: after the settle, before the walk).
func _walk_and_shoot(step: String, prefix: String, rooms: Array[int]) -> void:
	_load(step, SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	await _ticks(SETTLE_TICKS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # a released mouse turns nothing: no stray motion of the real mouse tilts the view
	if rooms.has(0):
		await _shoot(prefix + "-room-0")
	var pilot := Autopilot.new(_level)
	for room in rooms:
		if room == 0:
			continue
		await _drive_until(pilot, func() -> bool: return _level.current >= room)
		await _drive_ticks(pilot, SETTLE_IN_ROOM)
		pilot.release()
		await _ticks(30) # the player stops; the fog and the GI settle
		await _shoot("%s-room-%d" % [prefix, room])
	pilot.release()
	await _unload()

## A picture, and the squint test on it: the door the player looks at, against the wall around it, both blurred.
func _shoot(file_name: String) -> void:
	await _save(file_name)
	if DisplayServer.get_name() == "headless":
		return
	var door: Node3D = _level.rooms[_level.current].door
	if door == null:
		return
	var camera := get_viewport().get_camera_3d()
	var leaf := door.get_node("Hinge/Leaf").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var box := leaf.global_transform * leaf.mesh.get_aabb()
	var rect := Rect2()
	for corner in 8:
		var point := box.get_endpoint(corner)
		if camera.is_position_behind(point):
			return
		var screen := camera.unproject_position(point)
		rect = Rect2(screen, Vector2.ZERO) if corner == 0 else rect.expand(screen)
	var image := get_viewport().get_texture().get_image()
	var size := image.get_size()
	var dark := 0
	var total := 0
	for y in range(floori(size.y / 3.0), size.y, 8): # below the map and the stats: only the room
		for x in range(0, size.x, 8):
			total += 1
			dark += 1 if image.get_pixel(x, y).get_luminance() < BLACK else 0
	var black := dark / float(total)
	image.resize(floori(size.x / float(SQUINT_SCALE)), floori(size.y / float(SQUINT_SCALE)), Image.INTERPOLATE_TRILINEAR)
	image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var inner := rect.grow_individual(-rect.size.x * 0.2, -rect.size.y * 0.15, -rect.size.x * 0.2, -rect.size.y * 0.15)
	var outer := rect.grow_individual(rect.size.x * 0.6, 0.0, rect.size.x * 0.6, -rect.size.y * 0.1)
	var door_color := _mean(image, inner, Rect2())
	var wall_color := _mean(image, outer, rect.grow(rect.size.x * 0.1))
	var door_value := door_color.get_luminance()
	var wall_value := wall_color.get_luminance()
	var contrast := absf(door_value - wall_value) / maxf(wall_value, 0.001)
	_squint.append("%-44s %.2f  %.2f  %8.2f  %.3f     %.1f%%" % [file_name, door_value, wall_value, contrast, door_color.h, black * 100.0])
	_check(black <= MOST_BLACK, "%s: %.1f%% of the room is crushed black, at most %.0f%% allowed" % [file_name, black * 100.0, MOST_BLACK * 100.0])
	# Step 0 is tutorial 10's door and keeps tutorial 10's floor. A number is a patch inside the measured area of the door (dark
	# digits darken it): it may take SQUINT_NUMBER_COST at most from step 0's contrast of the same moment.
	var moment := file_name.substr(file_name.rfind("-room-"))
	if file_name.begins_with("00-"):
		_squint_reference[moment] = contrast
	var floor_contrast: float = SQUINT_CONTRAST if file_name.begins_with("00-") else _squint_reference.get(moment, SQUINT_CONTRAST) - SQUINT_NUMBER_COST
	_check(contrast >= floor_contrast, "%s: the squint test: the door (%.2f) against the wall (%.2f), contrast %.2f, expected at least %.2f" % [file_name, door_value, wall_value, contrast, floor_contrast])
	_check(door_color.h > 0.03 and door_color.h < 0.17 and door_color.s > 0.3, "%s: the door does not read orange when blurred (hue %.3f, saturation %.2f)" % [file_name, door_color.h, door_color.s])

## The mean colour of the pixels inside `area` and not inside `hole` (an empty hole: none left out).
func _mean(image: Image, area: Rect2, hole: Rect2) -> Color:
	var bounds := Rect2i(area).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for y in range(bounds.position.y, bounds.end.y, 2):
		for x in range(bounds.position.x, bounds.end.x, 2):
			if hole.has_area() and hole.has_point(Vector2(x, y)):
				continue
			var pixel := image.get_pixel(x, y)
			sum += Color(pixel.r, pixel.g, pixel.b, 0)
			count += 1
	return Color(sum.r / maxi(count, 1), sum.g / maxi(count, 1), sum.b / maxi(count, 1))

## A text file for the captures folder: no window needed.
func _save_text(file_name: String, text: String) -> void:
	var file := FileAccess.open(_out_dir.path_join(file_name), FileAccess.WRITE)
	if file == null:
		printerr("FAIL  could not write ", file_name)
		_failures += 1
		return
	file.store_string(text.strip_edges() + "\n")
	file.close()
	print("SAVED ", _out_dir.path_join(file_name))

## What only a window can show: the captured mouse and the clipboard. Esc releases the mouse, a click takes it again, the seed box
## gives it to the pointer and back, C puts the seed on the clipboard, the finish gives the mouse back and R takes it again.
func _window_checks() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  window checks: the headless display server never reports a captured mouse, and has no clipboard")
		return
	_load(FINAL_STEP, SHORT_GOAL)
	var player: CharacterBody3D = _level.player
	var head: Node3D = player.get_node("Head")
	await _ticks(SETTLE_TICKS)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the mouse is captured at the start")

	var yaw := player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(is_equal_approx(player.rotation.y - yaw, -0.2), "100 px to the right turn the body by -0.2 rad (got %.3f)" % (player.rotation.y - yaw))
	_check(is_zero_approx(head.rotation.x), "yaw does not tilt the head")

	await _press("ui_cancel")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc releases the mouse")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put while the mouse is released")
	await _click()
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "a click captures the mouse again")

	# The seed box: T gives the pointer to the box and stops the view, Esc and Enter give the mouse back.
	await _press_key(KEY_T)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "T releases the mouse for the seed box")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put while the seed box is up")
	await _press_key(KEY_ESCAPE)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not (_main.get_node("HUD/SeedEntry") as Control).visible, "Esc closes the box and captures the mouse")
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y != yaw, "the view turns again after the box")
	await _press_key(KEY_T)
	await _type(BOX_SEED)
	await _press_key(KEY_ENTER)
	await _ticks(10)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _level.seed_text == BOX_SEED, "Enter starts the run with the typed seed and captures the mouse")

	# C puts the seed on the clipboard: paste it into the box and it is the same seed.
	DisplayServer.clipboard_set("something else")
	await _press("copy_seed")
	_check(DisplayServer.clipboard_get() == BOX_SEED, "C puts \"%s\" on the clipboard, it holds \"%s\"" % [BOX_SEED, DisplayServer.clipboard_get()])
	await _press_key(KEY_T)
	var line: LineEdit = _main.get_node("HUD/SeedEntry/Rows/Line")
	line.text = ""
	line.insert_text_at_caret(DisplayServer.clipboard_get())
	_check(line.text == BOX_SEED, "the box takes the copied seed (\"%s\")" % line.text)
	await _press_key(KEY_ESCAPE)

	# The settings box: O gives the pointer to the box and stops the view, O again gives the mouse back.
	await _press_key(KEY_O)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and (_main.get_node("HUD/Settings") as Control).visible, "O opens the settings and releases the mouse")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put while the settings are up")
	await _press_key(KEY_O)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not (_main.get_node("HUD/Settings") as Control).visible, "O again closes the settings and captures the mouse")

	# The finish releases the mouse, and a click does not take it back: the run is over.
	var pilot := Autopilot.new(_level)
	await _drive_until(pilot, func() -> bool: return _level.state == STATE_FINISHED)
	pilot.release()
	await _ticks(10)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the finish releases the mouse")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put after the finish")
	await _click()
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "a click after the finish does not capture the mouse")
	await _press_key(KEY_T)
	await _press_key(KEY_ESCAPE)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "closing the box after the finish does not capture the mouse")

	# R: a new run, the mouse is the player's again.
	await _press("regenerate")
	await _ticks(5)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "R captures the mouse again")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y != yaw, "the view turns after R")
	await _unload()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		printerr("FAIL  ", message)
		_failures += 1

#endregion
#region Numbers

## Where the numbers are looked at. room: the room whose door's number it is (the rooms are looked at in this order: the
## player moves on and the rooms behind are freed), at: metres in front of the door, or -1 for the room's entrance.
const NUMBER_VIEWS: Array[Dictionary] = [
	{room = 0, at = 4.3, name = "room 0, 4 m from the door"},
	{room = 0, at = -1.0, name = "room 0, from the entrance"},
	{room = 2, at = -1.0, name = "vault, from the entrance"},
	{room = 3, at = -1.0, name = "wide room, from the entrance"},
	{room = 4, at = -1.0, name = "long hall, from the entrance"},
]
const REFERENCE_HEIGHT := 1080.0 ## The picture the digit heights are scaled to.
const PC_TEXT_PX := 18.0 ## The floor for text on a PC at 1080p.
const FILL_PIXELS := 12 ## Fewest pixels of digit the measurement wants to see.

## The room at `index`, with every door up to the goal opened so that the rooms exist: the player stays in room 0.
func _build_rooms(step: String, goal: int) -> void:
	_load(step, goal)
	_level.seed_text = SEED
	_level.start()
	await _ticks(SETTLE_TICKS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for index in goal:
		(_level.rooms[index].door as Node3D).call("open") # opening a door builds the room behind it
	await _ticks(45) # the doors swing open
	for index in goal:
		(_level.rooms[index].door as Node3D).call("close") # and shut again: the numbers face the room
	await _ticks(90) # the doors swing shut, the lamps and the fog settle

func _number_label(room: Node3D) -> Label3D:
	return (room.get("door") as Node3D).get_node("Hinge/Number") as Label3D

## The player stands `at` metres in front of the room's door (or at its entrance, 1.5 m in) and looks at its number.
func _look_at_number(room: Node3D, at: float) -> void:
	var label := _number_label(room)
	var door := room.get("door") as Node3D
	var player: CharacterBody3D = _level.player
	if at > 0.0:
		player.global_position = door.global_position + door.global_basis.z * at
	else:
		player.global_position = (room.get("entrance") as Marker3D).global_transform.translated_local(Vector3(0.0, 0.0, -1.5)).origin
	player.velocity = Vector3.ZERO
	var head := player.get_node("Head") as Node3D
	var offset := label.global_position - head.global_position
	player.rotation.y = atan2(-offset.x, -offset.z)
	head.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())

func _digit_ink_px(font: Font, font_size: int) -> float:
	var server := TextServerManager.get_primary_interface()
	var font_rid := font.get_rids()[0]
	var smallest := INF
	for digit in 10:
		var glyph := server.font_get_glyph_index(font_rid, font_size, "0".unicode_at(0) + digit, 0)
		var points: PackedVector3Array = server.font_get_glyph_contours(font_rid, font_size, glyph)["points"]
		var low := INF
		var high := -INF
		for point in points:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		smallest = minf(smallest, high - low)
	return smallest

## Where the digits' ink is on the screen (the rectangle around it), from the font's own numbers and the camera.
func _ink_rect(label: Label3D) -> Rect2i:
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var camera := get_viewport().get_camera_3d()
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
	var bottom := (font.get_height(label.font_size) / 2.0 - font.get_ascent(label.font_size)) * label.pixel_size
	var top := bottom + _digit_ink_px(font, label.font_size) * label.pixel_size
	var rect := Rect2()
	var first := true
	for corner: Vector3 in [Vector3(-width / 2.0, bottom, 0.0), Vector3(width / 2.0, bottom, 0.0), Vector3(-width / 2.0, top, 0.0), Vector3(width / 2.0, top, 0.0)]:
		var screen := camera.unproject_position(label.global_transform * corner)
		rect = Rect2(screen, Vector2.ZERO) if first else rect.expand(screen)
		first = false
	return Rect2i(rect.grow(rect.size.y * 0.35))

func _grab() -> Image:
	await _ticks(10)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

static func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

static func _ratio(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)

func _blurred(image: Image) -> Image:
	var size := image.get_size()
	var copy := image.duplicate() as Image
	copy.resize(floori(size.x / float(SQUINT_SCALE)), floori(size.y / float(SQUINT_SCALE)), Image.INTERPOLATE_TRILINEAR)
	copy.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return copy

func _mean_luminance(image: Image, rect: Rect2i) -> float:
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var sum := 0.0
	var count := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			sum += _luminance(image.get_pixel(x, y))
			count += 1
	return sum / maxf(count, 1)

## How the number on this door looks in the frame: three renders of the same view (the number, its digits without the rim,
## no number) tell which pixels are the digits and which the rim, and what door is behind each.
func _measure_number(room: Node3D) -> Dictionary:
	var label := _number_label(room)
	var rect := _ink_rect(label)
	var with := await _grab()
	label.visible = false
	var without := await _grab()
	label.visible = true
	var rim_size := label.outline_size
	label.outline_size = 0
	var fill_only := await _grab()
	label.outline_size = rim_size
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, with.get_size()))
	# The digits are the pixels that change when the rim is off and the number is on, the rim those that change only with the rim.
	# A pixel counts when it differs from the door behind it by at least a fifth of the biggest difference of the view; the
	# contrast is the one of those pixels against the door behind each (the same pixels of the render without the number).
	var strongest := 0.0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			strongest = maxf(strongest, _difference(fill_only.get_pixel(x, y), without.get_pixel(x, y)))
	var fill := {"n": 0, "digit": 0.0, "door": 0.0}
	var rim := {"n": 0, "digit": 0.0, "door": 0.0}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var behind := without.get_pixel(x, y)
			if strongest < 0.05:
				continue
			if _difference(fill_only.get_pixel(x, y), behind) >= strongest * 0.5:
				fill["n"] += 1
				fill["digit"] += _luminance(with.get_pixel(x, y))
				fill["door"] += _luminance(behind)
			elif rim_size > 0 and _difference(with.get_pixel(x, y), behind) >= strongest * 0.5 and _difference(fill_only.get_pixel(x, y), behind) < strongest * 0.2:
				rim["n"] += 1
				rim["digit"] += _luminance(with.get_pixel(x, y))
				rim["door"] += _luminance(behind)
	var squint_with := _mean_luminance(_blurred(with), bounds)
	var squint_without := _mean_luminance(_blurred(without), bounds)
	var count: int = fill["n"]
	var rim_count: int = rim["n"]
	# The digits' height is the projection of their ink, scaled to a 1080p picture: it is what the font and the camera give.
	var ink_height := rect.size.y / 1.7 # _ink_rect grows the ink by 35 percent above and below
	return {
		"px": ink_height * REFERENCE_HEIGHT / with.get_size().y,
		"digit_pixels": count,
		"strongest": strongest,
		"digits": _ratio(fill["digit"] / maxf(count, 1), fill["door"] / maxf(count, 1)) if count > 0 else 0.0,
		"rim": _ratio(rim["digit"] / maxf(rim_count, 1), rim["door"] / maxf(rim_count, 1)) if rim_count > 0 else 0.0,
		"squint": absf(squint_with - squint_without) / maxf(squint_without, 0.001),
	}

## The biggest difference of a colour channel between two pixels.
static func _difference(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))

## numbers.txt: for steps 1 to 3 and every view, what the number is in the frame. The checks: the digits are at least
## the PC text floor tall at 1080p wherever the player can stand, and step 3 reads on the orange door where step 2 does not.
func _numbers_table() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  numbers.txt: nothing is rendered headless")
		return
	var rows: Array[String] = ["step                            view                            m     digit px   digits/door   rim/door   squint"]
	var by_step: Dictionary[String, Array] = {}
	for step: String in STEPS.slice(1):
		await _build_rooms(step, SHORT_GOAL)
		var results: Array[Dictionary] = []
		for view in NUMBER_VIEWS:
			var room: Node3D = _level.rooms[view.room]
			_look_at_number(room, view.at)
			await _ticks(20)
			var label := _number_label(room)
			var distance := _level.player.get_node("Head").global_position.distance_to(label.global_position) as float
			var m := await _measure_number(room)
			m["distance"] = distance
			results.append(m)
			rows.append("%-30s  %-30s  %4.1f  %8.1f  %11.2f  %9s  %7.3f" % [step, view.name, distance, m.px, m.digits, ("%.2f" % m.rim) if m.rim > 0.0 else "-", m.squint])
			_check(m.digit_pixels >= FILL_PIXELS, "%s, %s: only %d digit pixels found: the number is not seen" % [step, view.name, m.digit_pixels])
			_check(m.px >= PC_TEXT_PX, "%s, %s: the digits are %.1f px tall on a 1080p picture, at least %.0f wanted" % [step, view.name, m.px, PC_TEXT_PX])
		by_step[step] = results
		await _unload()
	# Step 3 against step 2: the dark digits read where the white ones do not.
	for i in NUMBER_VIEWS.size():
		var white: Dictionary = by_step[STEPS[2]][i]
		var dark: Dictionary = by_step[STEPS[3]][i]
		_check(dark.digits >= 2.0 and dark.digits > white.digits * 1.5, "%s: dark digits %.2f:1 against the door, white digits %.2f:1" % [NUMBER_VIEWS[i].name, dark.digits, white.digits])
		_check(dark.squint > white.squint, "%s: blurred, the dark number changes its patch of door by %.3f, the white one by %.3f" % [NUMBER_VIEWS[i].name, dark.squint, white.squint])
	_save_text("numbers.txt", "\n".join(rows))

#endregion

#region Evidence

## A crop of the picture around the number, as a PNG: the evidence of a step.
func _save_crop(file_name: String, label: Label3D, size := Vector2i(560, 380)) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  %s.png (headless: nothing is rendered)" % file_name)
		return
	await _ticks(10)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var at := get_viewport().get_camera_3d().unproject_position(label.global_position)
	var corner := Vector2i(clampi(int(at.x - size.x / 2.0), 0, image.get_width() - size.x), clampi(int(at.y - size.y / 3.0), 0, image.get_height() - size.y))
	var path := _out_dir.path_join(file_name + ".png")
	if image.get_region(Rect2i(corner, size)).save_png(path) != OK:
		printerr("FAIL  could not save ", path)
		_failures += 1
		return
	print("SAVED ", path)

func _evidence() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  the evidence stills: nothing is rendered headless")
		return
	# Step 1: a number laid on the leaf's face fights the leaf for the pixels; a hair in front of it does not.
	await _build_rooms(STEPS[1], SHORT_GOAL)
	for view: Array in [[0, -1.0, "room-0"], [4, -1.0, "long-hall"]]:
		var room: Node3D = _level.rooms[view[0]]
		_look_at_number(room, view[1])
		var label := _number_label(room)
		var rest := label.position.z
		label.position.z = 0.05 # exactly the leaf's front face
		await _save_crop("01-on-the-face-%s" % view[2], label)
		var on_face := await _measure_number(room)
		label.position.z = rest
		await _save_crop("01-in-front-%s" % view[2], label)
		var in_front := await _measure_number(room)
		_check(in_front.digit_pixels > on_face.digit_pixels * 1.5, "%s: a number on the leaf's face shows %d digit pixels, one a hair in front of it %d" % [view[2], on_face.digit_pixels, in_front.digit_pixels])
	await _unload()
	# The back of the door: the leaf is in front of the number, and step 3 has switched the number's back off.
	for step: String in [STEPS[3]]:
		await _build_rooms(step, SHORT_GOAL)
		var door := _level.rooms[0].door as Node3D
		var label := _number_label(_level.rooms[0])
		var player: CharacterBody3D = _level.player
		player.global_position = door.global_position - door.global_basis.z * 3.0 # in room 1, clear of the door's swing: it shuts behind the player
		player.velocity = Vector3.ZERO
		await _ticks(90)
		var head := player.get_node("Head") as Node3D
		var offset := label.global_position - head.global_position
		player.rotation.y = atan2(-offset.x, -offset.z)
		head.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())
		_check(not door.get("is_open"), "%s: the door is still open: the back is not in view" % step)
		await _ticks(20)
		await _save_crop("03-back-of-the-door", label)
		var seen := await _measure_number(_level.rooms[0])
		_check(seen.digit_pixels < FILL_PIXELS, "%s: from behind the number shows %d digit pixels" % [step, seen.digit_pixels])
		await _unload()
	# Step 3: the door into the goal room says the goal's number; a door half open takes its number with it.
	await _build_rooms(STEPS[3], SHORT_GOAL)
	var goal_room: Node3D = _level.rooms[SHORT_GOAL - 1]
	_check(_number_label(goal_room).text == str(SHORT_GOAL), "the door into the goal room says \"%s\"" % _number_label(goal_room).text)
	_check(_level.rooms[SHORT_GOAL].get("door") == null, "the goal room has a door")
	_look_at_number(goal_room, 5.0) # in the room before the goal, in front of its door
	await _ticks(30)
	_check(_level.current == SHORT_GOAL - 1 and (_main.get_node("HUD/Stats/RoomLabel") as Label).text == "Room %d / %d" % [SHORT_GOAL - 1, SHORT_GOAL], "the HUD says \"%s\" in the room before the goal" % (_main.get_node("HUD/Stats/RoomLabel") as Label).text)
	await _save("03-goal-door")
	await _unload()
	_load(STEPS[3], SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	await _ticks(SETTLE_TICKS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var first: Node3D = _level.rooms[0]
	_look_at_number(first, 4.0)
	(first.get("door") as Node3D).call("open")
	await _ticks(12) # a third of the swing
	await _save("03-door-swinging")
	await _unload()

#endregion

#region Movie

## The finished game, seed 141 from room 0 to the goal pad: every room type once, each lamp in its tint.
func _movie() -> void:
	_load(FINAL_STEP, SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	await _ticks(60) # room 0
	var pilot := Autopilot.new(_level)
	await _drive_until(pilot, func() -> bool: return _level.state == STATE_FINISHED)
	pilot.release()
	await _ticks(90) # Finished!
	await _unload()

#endregion

#region Helpers

func _read_argument(name_with_dashes: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name_with_dashes + "="):
			return argument.trim_prefix(name_with_dashes + "=")
	return fallback

## Loads a step. goal: the level's goal_room (0 = its own). save_path: its best times file (default: a fresh temporary one).
func _load(step: String, goal := 0, save_path := "") -> void:
	_main = (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
	_level = _main.get_node("Level")
	if goal > 0:
		_level.set("goal_room", goal)
	if _level.get("save_path") != null:
		_level.set("save_path", save_path if not save_path.is_empty() else _fresh_save_path())
	var menu := _main.get_node_or_null("HUD/Settings")
	if menu != null: # step 5's settings: a temporary file, never the player's own
		menu.set("save_path", _fresh_save_path().trim_suffix(".json") + "-settings.json")
	# Under the root, not under this node: this node keeps running while the tree is paused.
	get_tree().root.add_child(_main)

func _unload() -> void:
	_release_inputs()
	get_tree().root.remove_child(_main)
	_main.queue_free()
	await get_tree().process_frame

func _release_inputs() -> void:
	for action: String in ["move_forward", "move_back", "look_left", "look_right", "look_up", "look_down", "jump"]:
		Input.action_release(action)

func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

## The autopilot walks for count physics ticks.
func _drive_ticks(pilot: RefCounted, count: int) -> void:
	for i in count:
		pilot.physics_step()
		await get_tree().physics_frame

## The autopilot walks until the condition holds (or for 60 s, or `limit` ticks, at most).
func _drive_until(pilot: RefCounted, condition: Callable, limit := 3600) -> void:
	for i in limit:
		if condition.call():
			return
		pilot.physics_step()
		await get_tree().physics_frame
	printerr("FAIL  the walk did not reach its goal in %.0f s" % (limit / 60.0))
	_failures += 1

## Presses and releases an input action as an event, like a key press.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(2)

func _click() -> void:
	for pressed: bool in [true, false]: # a click is a press and a release: a held button changes how a text box takes the focus
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await _ticks(2)

## Presses and releases a key through the input system, like a keyboard does.
func _press_key(code: Key, unicode := 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = unicode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _ticks(2)

## Types a text into whatever has the focus: every character is a key press that carries it.
func _type(text: String) -> void:
	for character in text:
		await _press_key(character.to_upper().unicode_at(0) as Key, character.unicode_at(0))

func _mouse_motion(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	Input.parse_input_event(motion)
	await _ticks(2)

func _save(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  %s.png (headless: nothing is rendered)" % file_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(file_name + ".png")
	if image == null or image.is_empty() or image.save_png(path) != OK:
		printerr("FAIL  could not save ", path)
		_failures += 1
		return
	print("SAVED ", path, " ", image.get_size())

func _save_dir() -> String:
	return OS.get_temp_dir().path_join("phaix-godot-11-capture")

## A path in the temporary folder that no file exists at.
func _fresh_save_path() -> String:
	_save_count += 1
	DirAccess.make_dir_recursive_absolute(_save_dir())
	var path := _save_dir().path_join("best_times_%d.json" % _save_count)
	for suffix: String in ["", ".bad", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	return path

func _clean_saves() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir()):
		return
	for file in DirAccess.get_files_at(_save_dir()):
		DirAccess.remove_absolute(_save_dir().path_join(file))
	DirAccess.remove_absolute(_save_dir())

#endregion
