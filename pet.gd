extends Node2D
## A little desktop cat with platforming.
##  - It stands on top of other apps' windows, visible desktop icons, and the
##    Dock; walks along their edges, rides windows that move, and falls (with
##    a squish landing) when its perch disappears.
##  - Drag with the left mouse button to carry it (drop it onto a window!).
##  - Right-click to feed it a cookie.
##  - Click (without dragging) to boop it — this also wakes it from a nap.
##  - Middle-click or press P to toggle play mode: it chases your cursor,
##    jumping after it, until it gets tired.
##  - Press B to cycle characters: Eevee and Snorlax behave like the cat
##    (walk + ballistic jumps), Fletchling behaves like the bird (flies
##    between ledges). Sleep, play mode, feeding, and going home all work
##    exactly the same for every character.
##  - Esc or Q quits.
##
## Characters are rendered from PMD-style sprite sheets in res://sprites/
## (<Name>/<Anim>-Anim.png + AnimData.xml). Sheets are loaded directly from
## disk at runtime, so no editor import pass is needed.
##
## Other windows are detected by helpers/window_list (a tiny CoreGraphics
## helper, see helpers/window_list.c). Desktop icons are read from Finder via
## osascript (macOS will ask once for permission to control Finder; if denied,
## the pet simply ignores icons). Without the helper the pet still works but
## only knows about the Dock line and screen bottom.

enum State { IDLE, WANDER, EAT, NAP, DRAG, FALL, PLAY, HOP, GO_HOME, ENTER_HOME, HOME, EXIT_HOME }
enum Form { EEVEE, SNORLAX, FLETCHLING }

# Per-character config: sprite folder, whether it uses the bird behavior
# (fly instead of jump), and which sheet each situation uses.
# An anim may be "Sheet" or "Sheet:first-last[:ticks]" — the latter plays only
# frames first..last of that sheet (optionally at a fixed ticks-per-frame).
# NOTE: Fletchling's FlapAround sheet spins the bird through all 8 directions
# within one loop, so playing it whole looks like tumbling; frames 0-1 of the
# facing row are a clean directional flap, and that pair is its flight.
const FORM_DEFS: Array[Dictionary] = [
	{ name = "Eevee", bird = false, anims = {
		idle = "Idle", walk = "Walk", sleep = "Sleep", eat = "Eat",
		air = "Hurt", crouch = "Hop", drag = "Float", fly = "" } },
	{ name = "Snorlax", bird = false, anims = {
		idle = "Idle", walk = "Walk", sleep = "Sleep", eat = "Swing",
		air = "Hurt", crouch = "Hop", drag = "Hurt", fly = "" } },
	{ name = "Fletchling", bird = true, anims = {
		idle = "Idle", walk = "Walk", sleep = "Sleep", eat = "Attack",
		air = "Hurt", crouch = "Hop", drag = "FlapAround:0-1:5", fly = "FlapAround:0-1:5" } },
]

const CENTER := Vector2(380.0, 400.0)
const FOOT_Y := 660.0        # feet line, in window-local pixels
const FOOT_HALF := 40.0      # half-width of the pet's footprint
const GRAVITY := 2600.0
const MAX_FALL_SPEED := 1600.0
const MIN_LEDGE := 90.0      # narrowest window edge worth standing on
const MIN_ICON_LEDGE := 80.0 # icons need to hold the bigger footprint too
const LEDGE_MARGIN := 14.0   # how far feet may hang past a ledge
const SPRITE_SCALE := 7.5    # sprite sheets are tiny GBA-scale pixels
const VFX_SCALE := SPRITE_SCALE / 3.0  # move_VFX overlays, deliberately daintier
const SPRITE_TICK := 1.0 / 60.0  # AnimData durations are 60 Hz ticks
const WANDER_SPEED := 90.0
const PLAY_SPEED := 320.0    # chase speed in play mode
const JUMP_VY := -1600.0     # jump impulse in play mode
const PLAY_LENGTH := 35.0    # seconds of play before it gets tired
const HOP_MAX_UP := 950.0    # highest ledge it will hop up to (cartoon legs)
const HOP_MAX_DROP := 1200.0 # furthest it will hop down
const HOP_MAX_DX := 720.0    # horizontal hop reach
const HOP_MAX_VX := 620.0    # fastest horizontal hop speed
const HOP_CROUCH := 0.18     # wind-up squat before launching
const FLY_SPEED := 420.0     # bird flight speed between ledges
const FLY_MAX_RANGE := 1500.0
const FLY_ARRIVE_DIST := 16.0
const HUNGRY_AFTER := 45.0   # seconds until the cat looks hungry
const NAP_MIN := 25.0        # seconds of wakefulness before a nap can start
const NAP_MAX := 60.0
const NAP_LENGTH_MIN := 12.0
const NAP_LENGTH_MAX := 25.0
const HOME_W := 320          # home (Pokéball) window size — big enough for the flash
const HOME_H := 260
const HOME_FLOOR := 200.0    # floor line inside the home window
const HOME_DOOR_X := 160.0   # ball center
const HOME_SPEED := 260.0    # walking speed when heading home
const ENTER_TIME := 1.6      # seconds of capture/release beam animation
const HomeArt := preload("res://home.gd")

var state: State = State.FALL   # spawn in the air and drop onto something
var t := 0.0                 # global animation clock
var state_timer := 0.0       # counts down inside timed states
var facing := 1              # 1 = facing right, -1 = facing left

var hunger := 0.0
var nap_in := 0.0            # wall-clock until the next nap

var eat_progress := 0.0      # 0..1 while a cookie is being eaten

var wander_dir := 1

var play_mode := false
var play_timer := 0.0

var hop_vy := 0.0            # launch velocities for the pending hop
var hop_vx := 0.0
var hop_crouch := 0.0        # >0 while winding up to jump

var form: Form = Form.FLETCHLING     # current character (B cycles)
var fly_target := Vector2.ZERO       # feet destination while flying (global px)
var fly_target_ground := -1          # platform id fly_target sits on
var fly_bob_time := 0.0

# Sprite animation state. _sprites[form] = { anim_name: {tex, fw, fh, rows,
# durs (seconds per frame), total, foot/top (content bounds within a frame),
# half_w (content half-width from frame center)} }
var _sprites := {}
# _metrics[form] = idle-pose content size {half_w, height} in sprite pixels —
# used to place the shadow, particles, and cookie around any character.
var _metrics := {}
var _anim_name := ""
var _anim_clock := 0.0

var going_home := false      # persists across falls/hops on the way home
var anim_progress := 0.0     # 0..1 during ENTER_HOME / EXIT_HOME

# The home: a second always-on-top window that sits on the Dock line.
var home_win: Window
var home_node: Node2D
var _home_dragging := false
var _home_drag_moved := false
var _home_drag_offset := Vector2i.ZERO
var _home_press_pos := Vector2i.ZERO

# Virtual<->real bridge (see README): ~/.desktop-pet/ holds a `state` file,
# a `command` file polled by the pet, and optional on_enter_home/on_exit_home
# executable hooks — the handoff point for a physical pet robot.
var bridge_dir := ""
var _pending_cmd := ""       # mutex-protected, set by the poll thread

var dragging := false
var drag_moved := false
var drag_offset := Vector2i.ZERO
var press_pos := Vector2i.ZERO

# Platforming state.
var pos_f := Vector2.ZERO    # logical window position (the OS may refuse it)
# macOS pins windows below the menu bar, so the window can't always go where
# pos_f wants (feet could never rise above window-top + FOOT_Y — the pet
# "walked on air" toward high ledges). vis_off is whatever part of the move
# the OS refused, applied instead as an in-window drawing/click-box offset.
var vis_off := Vector2.ZERO
var vy := 0.0
var ground_id := -2          # platform id we stand on; -2 = airborne.
                             # Window ids are positive, -1 = Dock line,
                             # -1000 - n = desktop icon n.
var land_squish := 0.0       # >0 briefly after landing
# Standable ledges rebuilt every frame: {id: int, y: float, x1: float, x2: float}
var platforms: Array[Dictionary] = []

# Background polling of other apps' windows and desktop icons.
var _thread: Thread
var _mutex := Mutex.new()
var _poll_running := true
var _windows: Array = []     # {id: int, rect: Rect2} in points, front-to-back
var _icons: Array = []       # icon centers, in points
var _icon_size := 64.0       # in points
var _icon_status := "pending"  # for PET_DEBUG: result of the last icon poll
# Icons come from Finder; PET_NO_ICONS=1 skips that poll entirely — useful
# where the Finder-automation permission dialog can't be answered, since an
# unanswered prompt makes osascript block the whole poll thread.
var _icons_supported := OS.get_name() == "macOS" \
	and OS.get_environment("PET_NO_ICONS") == ""
var _helper_path := ""
var _icons_script_path := ""

# Floating decorations: hearts when booped, a pixel Zzz while napping,
# musical notes in play mode, and a cookie thought-bubble when hungry.
var particles: Array[Dictionary] = []
# move_VFX overlay animations (see _load_vfx): kind -> {frames, ft}.
# Particles whose kind is in here play the frames in place instead of the
# procedural drift-and-fade behavior.
var _vfx := {}

@onready var win: Window = get_window()

# Run with PET_DEBUG=1 in the environment to log state once per second.
@onready var _debug := OS.get_environment("PET_DEBUG") != ""
# PET_SNAP=/path.png saves one viewport snapshot (plus the home ball's view
# as …-home.png) PET_SNAP_AT seconds after launch (default ~2 s).
@onready var _snap_path := OS.get_environment("PET_SNAP")
@onready var _snap_at := maxf(OS.get_environment("PET_SNAP_AT").to_float(), 0.5)


func _ready() -> void:
	randomize()
	get_viewport().transparent_bg = true
	nap_in = randf_range(NAP_MIN, NAP_MAX)
	pos_f = Vector2(win.position)
	# PET_SPAWN="x,y" drops the pet at a chosen spot (handy for testing).
	var spawn := OS.get_environment("PET_SPAWN")
	if spawn.contains(","):
		var parts := spawn.split(",")
		pos_f = Vector2(parts[0].to_float(), parts[1].to_float())
		_place_window()
	var helper_file := "window_list.exe" if OS.get_name() == "Windows" else "window_list"
	_helper_path = ProjectSettings.globalize_path("res://helpers/" + helper_file)
	_icons_script_path = ProjectSettings.globalize_path("res://helpers/desktop_icons.applescript")
	# PET_PLAY=1 starts in play mode (handy for testing).
	if OS.get_environment("PET_PLAY") != "":
		_toggle_play()
	# PET_FORM forces a starting character (handy for testing). The old
	# cat/parrot names still work as aliases.
	match OS.get_environment("PET_FORM").to_lower():
		"eevee", "cat": form = Form.EEVEE
		"snorlax": form = Form.SNORLAX
		"fletchling", "parrot", "bird": form = Form.FLETCHLING
	# PET_NAP=1 makes it nap at the first opportunity (handy for testing).
	if OS.get_environment("PET_NAP") != "":
		nap_in = 0.0
	texture_filter = TEXTURE_FILTER_NEAREST  # crisp pixel art when scaled
	_load_form_sprites(form)
	_load_vfx()
	if _is_bird():
		_begin_flight()  # give the initial fall a real flight target
	_init_bridge()
	_create_home()
	if FileAccess.file_exists(_helper_path):
		_thread = Thread.new()
		_thread.start(_poll_windows.bind(OS.get_process_id()))
	else:
		push_warning("window-list helper not found — pet will only walk on the taskbar line. "
			+ "Build it with the command at the top of helpers/window_list.c (macOS) "
			+ "or helpers/window_list_win.c (Windows).")


func _exit_tree() -> void:
	_poll_running = false
	if _thread:
		_thread.wait_to_finish()


func _init_bridge() -> void:
	bridge_dir = OS.get_environment("PET_BRIDGE_DIR")
	if bridge_dir == "":
		var home_dir := OS.get_environment("HOME")
		if home_dir == "":
			home_dir = OS.get_environment("USERPROFILE")  # Windows
		bridge_dir = home_dir.path_join(".desktop-pet")
	DirAccess.make_dir_recursive_absolute(bridge_dir)
	_write_state("virtual")


func _write_state(s: String) -> void:
	var f := FileAccess.open(bridge_dir.path_join("state"), FileAccess.WRITE)
	if f:
		f.store_line(s)


## Runs an optional executable hook from the bridge dir, non-blocking.
func _run_hook(hook: String) -> void:
	var path := bridge_dir.path_join(hook)
	if FileAccess.file_exists(path):
		OS.create_process(path, [])


func _create_home() -> void:
	home_win = Window.new()
	home_win.title = "Pet Home"
	home_win.borderless = true
	home_win.unresizable = true
	home_win.transparent = true
	home_win.always_on_top = true
	home_win.transparent_bg = true
	home_win.size = Vector2i(HOME_W, HOME_H)
	home_node = HomeArt.new()
	home_win.add_child(home_node)
	add_child(home_win)
	# Re-assert per-pixel transparency now that the OS window exists — set
	# only before add_child it has been seen to come up gray.
	home_win.transparent = true
	home_win.transparent_bg = true
	home_win.window_input.connect(_on_home_input)
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	home_win.position = Vector2i(usable.end.x - HOME_W - 80, usable.end.y - int(HOME_FLOOR))
	# Only the ball itself should catch clicks — the rest of this (mostly
	# empty) window passes them through to whatever is underneath.
	var bm := 24.0
	home_win.mouse_passthrough_polygon = PackedVector2Array([
		Vector2(HOME_DOOR_X - HomeArt.BALL_R - bm, HOME_FLOOR - HomeArt.BALL_R * 2.0 - bm),
		Vector2(HOME_DOOR_X + HomeArt.BALL_R + bm, HOME_FLOOR - HomeArt.BALL_R * 2.0 - bm),
		Vector2(HOME_DOOR_X + HomeArt.BALL_R + bm, HOME_FLOOR + 8.0),
		Vector2(HOME_DOOR_X - HomeArt.BALL_R - bm, HOME_FLOOR + 8.0),
	])


## Where feet stand when at the ball, in global pixels.
func _door_feet() -> Vector2:
	return Vector2(home_win.position) + Vector2(HOME_DOOR_X, HOME_FLOOR)


## Keeps the ball sitting on the Dock line (the user drags it only sideways).
func _snap_home() -> void:
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	home_win.position = Vector2i(
		clampi(home_win.position.x, usable.position.x, usable.end.x - HOME_W),
		usable.end.y - int(HOME_FLOOR))


func _on_home_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_home_press_pos = DisplayServer.mouse_get_position()
			_home_drag_offset = _home_press_pos - home_win.position
			_home_dragging = true
			_home_drag_moved = false
		else:
			_home_dragging = false
			if not _home_drag_moved:
				# A click on the ball recalls the pet into it, or lets it out.
				if state == State.HOME:
					_start_exit_home()
				else:
					_head_home()
	elif event is InputEventMouseMotion and _home_dragging:
		var m := DisplayServer.mouse_get_position()
		if Vector2(m - _home_press_pos).length() > 4.0:
			_home_drag_moved = true
		if _home_drag_moved:
			home_win.position = Vector2i(m.x - _home_drag_offset.x, home_win.position.y)


# ----------------------------------------------------------------------------
# Background polling (runs on _thread — no DisplayServer/Window calls here).
# ----------------------------------------------------------------------------

func _poll_windows(own_pid: int) -> void:
	var ticks := 0
	while _poll_running:
		var output := []
		var code := OS.execute(_helper_path, [str(own_pid)], output)
		if code == 0 and output.size() > 0:
			var parsed: Variant = JSON.parse_string(str(output[0]))
			if parsed is Array:
				var wins: Array = []
				for d in parsed:
					wins.append({ id = int(d.id), rect = Rect2(d.x, d.y, d.w, d.h) })
				_mutex.lock()
				_windows = wins
				_mutex.unlock()
		# Icons move rarely and Finder scripting is slow, so poll every ~2.4 s.
		# (Finder-based, so macOS only.)
		if _icons_supported and ticks % 8 == 0:
			_poll_icons()
		_poll_command()
		ticks += 1
		OS.delay_msec(300)


## Reads and deletes the bridge command file, if a robot-side process wrote one.
func _poll_command() -> void:
	var cmd_path := bridge_dir.path_join("command")
	if not FileAccess.file_exists(cmd_path):
		return
	var f := FileAccess.open(cmd_path, FileAccess.READ)
	var cmd := f.get_as_text().strip_edges() if f else ""
	f = null
	DirAccess.remove_absolute(cmd_path)
	if cmd != "":
		_mutex.lock()
		_pending_cmd = cmd
		_mutex.unlock()


func _poll_icons() -> void:
	# Icons hidden via `defaults write com.apple.finder CreateDesktop false`?
	# (A missing pref means the default: visible.)
	var pref := []
	if OS.execute("defaults", ["read", "com.apple.finder", "CreateDesktop"], pref) == 0 \
			and pref.size() > 0:
		var v := str(pref[0]).strip_edges().to_lower()
		if v == "0" or v == "false":
			_mutex.lock()
			_icons = []
			_mutex.unlock()
			return
	# The script lives in a file because OS.execute mangles quoted inline
	# AppleScript. Output: "iconSize,x,y,x,y,..." in points.
	var out := []
	var code := OS.execute("osascript", [_icons_script_path],
			out, true)  # read stderr too — errors only explain themselves there
	if code != 0:
		# Most likely: automation permission denied — just skip icons.
		_icon_status = "err %d: %s" % [code, " ".join(out).strip_edges().left(120)]
		return
	var icons: Array = []
	var icon_pt := 64.0
	if out.size() > 0:
		var tokens := str(out[0]).strip_edges().split(",", false)
		if tokens.size() % 2 == 1 and tokens[0].strip_edges().is_valid_float():
			icon_pt = maxf(tokens[0].strip_edges().to_float(), 16.0)
			for i in range(1, tokens.size() - 1, 2):
				var xs := tokens[i].strip_edges()
				var ys := tokens[i + 1].strip_edges()
				if xs.is_valid_float() and ys.is_valid_float():
					icons.append(Vector2(xs.to_float(), ys.to_float()))
	_icon_status = "ok: %d icons" % icons.size()
	_mutex.lock()
	_icons = icons
	_icon_size = icon_pt
	_mutex.unlock()


# ----------------------------------------------------------------------------
# Ledges
# ----------------------------------------------------------------------------

## Turns the window and icon lists into standable ledges: top edges minus the
## parts hidden behind windows in front, plus the Dock line.
func _rebuild_platforms() -> void:
	_mutex.lock()
	var wins := _windows.duplicate()
	var icons := _icons.duplicate()
	var icon_pt: float = _icon_size
	_mutex.unlock()
	# The macOS helper and Finder report points; Godot's DisplayServer uses
	# physical pixels, so on Retina screens everything must be scaled up.
	# The Windows helper already reports physical pixels — no scaling there.
	var sf := DisplayServer.screen_get_scale(win.current_screen) \
		if OS.get_name() == "macOS" else 1.0
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var scaled: Array[Rect2] = []
	for w in wins:
		var r: Rect2 = w.rect
		scaled.append(Rect2(r.position * sf, r.size * sf))
	platforms.clear()
	# Window top edges, occluded by windows in front of them.
	for i in wins.size():
		var r := scaled[i]
		if r.size.x < MIN_LEDGE:
			continue
		var y := r.position.y
		# No room for the pet above edges too close to the menu bar (it
		# needs its own height of headroom), and edges at/under the Dock
		# line are pointless.
		if y < usable.position.y + _m().height * SPRITE_SCALE * 0.75 \
				or y > usable.end.y - 2.0:
			continue
		var segs: Array[Vector2] = [Vector2(r.position.x, r.end.x)]
		for j in i:  # windows in front of this one
			if scaled[j].position.y < y and scaled[j].end.y > y:
				segs = _subtract_interval(segs, scaled[j].position.x, scaled[j].end.x)
		for s in segs:
			if s.y - s.x >= MIN_LEDGE:
				platforms.append({ id = wins[i].id, y = y, x1 = s.x, x2 = s.y })
	# Desktop icons sit behind every window, so all windows occlude them.
	# Finder's "desktop position" is the icon's center.
	var icon_half := icon_pt * 0.5 * sf
	for k in icons.size():
		var c: Vector2 = icons[k] * sf
		var y := c.y - icon_half
		if y < usable.position.y + _m().height * SPRITE_SCALE * 0.75 \
				or y > usable.end.y - 2.0:
			continue
		var segs: Array[Vector2] = [Vector2(c.x - icon_half, c.x + icon_half)]
		for r in scaled:
			if r.position.y < y and r.end.y > y:
				segs = _subtract_interval(segs, r.position.x, r.end.x)
		for s in segs:
			if s.y - s.x >= MIN_ICON_LEDGE:
				platforms.append({ id = -1000 - k, y = y, x1 = s.x, x2 = s.y })
	# The ball's crown is a wonderful (if precarious) circus perch.
	if home_win:
		var hp := Vector2(home_win.position)
		platforms.append({
			id = -2000, y = hp.y + HOME_FLOOR - HomeArt.BALL_R * 2.0,
			x1 = hp.x + HOME_DOOR_X - 41.0, x2 = hp.x + HOME_DOOR_X + 41.0,
		})
	# The Dock: the usable rect excludes it, so its top edge is the usable
	# rect's bottom. (With no Dock this is simply the screen bottom.)
	platforms.append({
		id = -1, y = float(usable.end.y),
		x1 = float(usable.position.x), x2 = float(usable.end.x),
	})


func _subtract_interval(segs: Array[Vector2], a: float, b: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in segs:
		if b <= s.x or a >= s.y:      # no overlap
			out.append(s)
			continue
		if a > s.x:
			out.append(Vector2(s.x, a))
		if b < s.y:
			out.append(Vector2(b, s.y))
	return out


func _feet_x() -> float:
	return pos_f.x + CENTER.x


func _feet_y() -> float:
	return pos_f.y + FOOT_Y


## Moves the OS window to pos_f, pre-clamped to where macOS will actually
## allow it (below the menu bar); the shortfall becomes vis_off. Clamping
## ourselves keeps vis_off deterministic — reading win.position back after a
## refused move returns stale values depending on frame timing.
func _place_window() -> void:
	var want := Vector2i(pos_f.round())
	var top := DisplayServer.screen_get_usable_rect(win.current_screen).position.y
	var wp := Vector2i(want.x, maxi(want.y, top))
	win.position = wp
	vis_off = Vector2(want - wp)


## The platform we're currently standing on, or {} if it's gone.
func _current_platform() -> Dictionary:
	var fx := _feet_x()
	for p in platforms:
		if p.id == ground_id and fx >= p.x1 - LEDGE_MARGIN and fx <= p.x2 + LEDGE_MARGIN:
			return p
	return {}


## Grounded states call this every frame: follow the platform if it moved,
## start falling if it's gone. Returns false when we started to fall.
func _stick_to_ground() -> bool:
	var p := _current_platform()
	if p.is_empty():
		_start_fall()
		return false
	pos_f.y = p.y - FOOT_Y
	_place_window()
	return true


func _is_bird() -> bool:
	return FORM_DEFS[form].bird


## Idle-pose content metrics of the current form, in sprite pixels.
func _m() -> Dictionary:
	return _metrics.get(form, { half_w = 12.0, height = 24.0 })


## A point just above the character's head (dx in window px).
func _above_head(dx: float = 0.0) -> Vector2:
	return Vector2(CENTER.x + dx, FOOT_Y - _m().height * SPRITE_SCALE - 50.0)


## Only the box around the sprite should catch the mouse — everything else
## in this big window must pass clicks through to whatever is underneath.
func _update_passthrough() -> void:
	if state == State.HOME:
		return  # entering HOME already set the tiny all-passthrough triangle
	var sheets: Dictionary = _sprites.get(form, {})
	if not sheets.has(_anim_name):
		win.mouse_passthrough_polygon = PackedVector2Array()
		return
	var sp: Dictionary = sheets[_anim_name]
	var margin := 16.0
	var hw: float = sp.half_w * SPRITE_SCALE + margin
	var top: float = FOOT_Y - (sp.foot - sp.top) * SPRITE_SCALE - margin
	var bot := FOOT_Y + margin
	win.mouse_passthrough_polygon = PackedVector2Array([
		Vector2(CENTER.x - hw, top) + vis_off, Vector2(CENTER.x + hw, top) + vis_off,
		Vector2(CENTER.x + hw, bot) + vis_off, Vector2(CENTER.x - hw, bot) + vis_off,
	])


func _start_fall() -> void:
	if state == State.NAP:
		nap_in = randf_range(NAP_MIN, NAP_MAX)  # rude awakening
	land_squish = 0.0
	if _is_bird():
		_begin_flight()  # a bird doesn't fall — it takes off
	else:
		vy = 0.0
		ground_id = -2
		state = State.FALL


## Ledges reachable by flight: everything but the one we're currently on,
## within FLY_MAX_RANGE, preferring windows/icons over the plain Dock line.
func _flight_candidates() -> Array:
	var fx := _feet_x()
	var fy := _feet_y()
	var options: Array = []
	for p in platforms:
		if p.id == ground_id:
			continue
		var lo: float = p.x1 + FOOT_HALF
		var hi: float = p.x2 - FOOT_HALF
		if lo > hi:
			continue
		var tx: float = clampf(fx, lo, hi)
		if Vector2(tx, p.y).distance_to(Vector2(fx, fy)) > FLY_MAX_RANGE:
			continue
		options.append(p)
	var fancy := options.filter(func(c): return c.id != -1)
	return fancy if not fancy.is_empty() else options


## Commits to flying toward a chosen ledge.
func _fly_to(pick: Dictionary) -> void:
	var lo: float = pick.x1 + FOOT_HALF
	var hi: float = pick.x2 - FOOT_HALF
	var tx: float = clampf(_feet_x() + randf_range(-140.0, 140.0), lo, hi)
	fly_target = Vector2(tx, pick.y)
	fly_target_ground = pick.id
	if absf(tx - _feet_x()) > 1.0:
		facing = 1 if tx > _feet_x() else -1
	ground_id = -2
	vy = 0.0
	land_squish = 0.0
	state = State.FALL


## Takes off toward a reachable ledge — the parrot's equivalent of falling or
## hopping. Always lands on something: if nothing is in range, it flies down
## to the Dock, which spans the full screen width.
func _begin_flight() -> void:
	ground_id = -2
	vy = 0.0
	land_squish = 0.0
	if going_home and home_win:
		# Heading home: fly straight to the doorstep instead of a random perch.
		# The door sits on the Dock line, so landing there resumes GO_HOME
		# right at the doorway.
		fly_target = _door_feet()
		fly_target_ground = -1
		state = State.FALL
		return
	var options := _flight_candidates()
	if options.is_empty():
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		var fx := _feet_x()
		fly_target = Vector2(
			clampf(fx, float(usable.position.x) + FOOT_HALF, float(usable.end.x) - FOOT_HALF),
			float(usable.end.y))
		fly_target_ground = -1
		state = State.FALL
	else:
		_fly_to(options.pick_random())


## One frame of level flight toward fly_target, with a gentle bob. Returns
## true once it has landed on fly_target_ground.
func _fly_step(delta: float) -> bool:
	fly_bob_time += delta
	var feet := Vector2(_feet_x(), _feet_y())
	var to_target := fly_target - feet
	if to_target.length() <= FLY_ARRIVE_DIST:
		pos_f = fly_target - Vector2(CENTER.x, FOOT_Y)
		ground_id = fly_target_ground
		vy = 0.0
		land_squish = 0.25
		_place_window()
		return true
	var dir := to_target.normalized()
	if absf(dir.x) > 0.05:
		facing = 1 if dir.x > 0.0 else -1
	pos_f += dir * FLY_SPEED * delta
	pos_f.y += sin(fly_bob_time * 6.0) * 0.5
	_place_window()
	return false


## One frame of gravity, with optional horizontal steering (px/s).
## Lands on ledges only while descending. Returns true on landing.
func _airborne_step(delta: float, steer: float) -> bool:
	vy = minf(vy + GRAVITY * delta, MAX_FALL_SPEED)
	var prev_feet := _feet_y()
	pos_f.y += vy * delta
	pos_f.x += steer * delta
	var new_feet := _feet_y()
	var fx := _feet_x()
	# Land on the highest ledge our feet crossed this frame.
	var best := {}
	if vy > 0.0:
		for p in platforms:
			if fx >= p.x1 - LEDGE_MARGIN and fx <= p.x2 + LEDGE_MARGIN \
					and p.y >= prev_feet - 2.0 and p.y <= new_feet:
				if best.is_empty() or p.y < best.y:
					best = p
	if best.is_empty():
		# Safety net: never fall through the very bottom of the screen.
		var scr := win.current_screen
		var bottom := float(DisplayServer.screen_get_position(scr).y
			+ DisplayServer.screen_get_size(scr).y)
		if new_feet >= bottom:
			best = { id = -1, y = bottom, x1 = 0.0, x2 = 0.0 }
	if not best.is_empty():
		pos_f.y = best.y - FOOT_Y
		ground_id = best.id
		vy = 0.0
		land_squish = 0.3
		_place_window()
		return true
	_place_window()
	return false


# ----------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	_update_particles(delta)
	_snap_home()
	_rebuild_platforms()
	_consume_command()
	if land_squish > 0.0:
		land_squish = maxf(land_squish - delta * 1.6, 0.0)

	var at_home := state == State.HOME or state == State.ENTER_HOME \
		or state == State.EXIT_HOME
	if state != State.NAP and not at_home:
		hunger += delta
	if state == State.IDLE or state == State.WANDER or state == State.EAT:
		nap_in -= delta

	match state:
		State.IDLE:
			if not _stick_to_ground():
				pass
			elif going_home:
				state = State.GO_HOME
			elif play_mode:
				state = State.PLAY
			elif nap_in <= 0.0:
				_start_nap()
			elif randf() < delta * 0.15 and _try_hop():
				pass  # bounding off to another ledge
			elif randf() < delta * 0.12:
				_start_wander()
			elif randf() < delta * 0.006:
				_head_home()  # every few minutes it goes home on its own
			elif hunger > HUNGRY_AFTER and randf() < delta * 0.35:
				_spawn(&"thought", _above_head(facing * (_m().half_w * SPRITE_SCALE + 70.0)))
		State.WANDER:
			_wander(delta)
		State.EAT:
			_stick_to_ground()
			if state == State.EAT:  # may have started falling
				eat_progress += delta / 1.6
				if eat_progress >= 1.0:
					hunger = 0.0
					_spawn(&"heart", _above_head())
					state = _grounded_state()
		State.NAP:
			if _stick_to_ground():
				state_timer -= delta
				if fmod(t, 1.4) < delta:
					# +45: the sleeping pose lies much lower than the idle
					# height _above_head assumes, minus a little breathing
					# room above the body.
					_spawn(&"zzz", _above_head(facing * 60.0) + Vector2(0, 45))
				if state_timer <= 0.0:
					_wake_up()
		State.FALL:
			if _is_bird():
				if _fly_step(delta):
					state = _grounded_state()
			elif _airborne_step(delta, 0.0):
				state = _grounded_state()
		State.HOP:
			if hop_crouch > 0.0:
				if _stick_to_ground():  # platform may vanish mid-crouch
					hop_crouch -= delta
					if hop_crouch <= 0.0:  # launch!
						vy = hop_vy
						ground_id = -2
			elif _airborne_step(delta, hop_vx):
				state = _grounded_state()
		State.GO_HOME:
			_go_home_tick(delta)
		State.ENTER_HOME:
			anim_progress += delta / ENTER_TIME
			home_node.set_transfer("capture", anim_progress)
			var door := _door_feet()
			pos_f.x = lerpf(pos_f.x, door.x - CENTER.x, minf(anim_progress * 2.0, 1.0))
			pos_f.y = door.y - FOOT_Y
			_place_window()
			if anim_progress >= 1.0:
				going_home = false
				state = State.HOME
				# The main window can't be hidden, so vanish by other means:
				# stop drawing and let every click pass straight through.
				visible = false
				win.mouse_passthrough_polygon = PackedVector2Array([
					Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
				home_node.set_transfer("", 0.0)
				home_node.cat_inside = true
				_write_state("home")
				_run_hook("on_enter_home")
		State.HOME:
			pass  # the soul is in the robot now; the ball wobbles for us
		State.EXIT_HOME:
			anim_progress += delta / ENTER_TIME
			home_node.set_transfer("release", anim_progress)
			pos_f = _door_feet() - Vector2(CENTER.x, FOOT_Y)
			_place_window()
			if anim_progress >= 1.0:
				home_node.set_transfer("", 0.0)
				if _is_bird():
					_begin_flight()  # flies out and off to the nearest perch
				else:
					# Pop out with a little hop, away from the house wall.
					var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
					var mid := (usable.position.x + usable.end.x) * 0.5
					hop_vx = (1.0 if _feet_x() < mid else -1.0) * randf_range(200.0, 320.0)
					facing = 1 if hop_vx > 0.0 else -1
					vy = -900.0
					hop_crouch = 0.0
					ground_id = -2
					state = State.HOP
		State.PLAY:
			_play(delta)
		State.DRAG:
			var mouse := DisplayServer.mouse_get_position()
			if Vector2(mouse - press_pos).length() > 4.0:
				drag_moved = true
			if drag_moved:
				pos_f = Vector2(mouse - drag_offset)
				_place_window()

	# Capture / release beam: while the ball is open the pet shrinks into (or
	# grows out of) it, washing out to white-hot light, converging on the
	# ball's center. Everything drawn is shifted by vis_off so the sprite sits
	# where the physics says even when the OS refused to move the window that
	# high.
	if state == State.ENTER_HOME or state == State.EXIT_HOME:
		var p := clampf(anim_progress, 0.0, 1.0)
		var s: float
		if state == State.ENTER_HOME:
			# Ball opens (p<0.25), pet beams in (0.25..0.65), flash + close.
			s = clampf(1.0 - (p - 0.25) / 0.4, 0.0, 1.0)
		else:
			# Flash builds (p<0.3), pet beams out (0.3..0.75), ball closes.
			s = clampf((p - 0.3) / 0.45, 0.0, 1.0)
		var glow := (1.0 - s) * 6.0
		scale = Vector2.ONE * maxf(s, 0.001)  # exactly 0 breaks the transform
		position = Vector2(CENTER.x, FOOT_Y - HomeArt.BALL_CENTER_UP) * (1.0 - s) + vis_off
		modulate = Color(1.0 + glow, 1.0 + glow, 1.0 + glow, clampf(s * 2.5, 0.0, 1.0))
	else:
		scale = Vector2.ONE
		position = vis_off
		modulate = Color(1, 1, 1, 1)

	# Advance the sprite animation; switching sheets restarts the clock.
	var desired := _current_anim()
	if desired.name != _anim_name:
		_anim_name = desired.name
		_anim_clock = 0.0
	_anim_clock += delta * desired.speed
	_update_passthrough()

	if _snap_path != "" and t > _snap_at:
		get_viewport().get_texture().get_image().save_png(_snap_path)
		# The ball lives in its own window; save its view too (…-home.png).
		home_win.get_viewport().get_texture().get_image().save_png(
			_snap_path.get_basename() + "-home.png")
		_snap_path = ""

	if _debug and fmod(t, 1.0) < delta:
		print("state=%-9s form=%-10s anim=%-10s pos=%s vis=%d ground=%d home=%s icons=[%s] ledges=%s" % [
			State.keys()[state], Form.keys()[form], _anim_name, Vector2i(pos_f.round()), int(vis_off.y),
			ground_id, home_win.position, _icon_status,
			platforms.map(func(p): return Vector2i(int(p.x1), int(p.y)))])

	queue_redraw()


## Which sprite animation the current state calls for, plus playback speed
## and whether to freeze on the last frame instead of looping.
func _current_anim() -> Dictionary:
	var anims: Dictionary = FORM_DEFS[form].anims
	var bird := _is_bird()
	match state:
		State.NAP:
			return { name = anims.sleep, speed = 1.0, hold = false }
		State.EAT:
			return { name = anims.eat, speed = 1.0, hold = false }
		State.DRAG:
			if drag_moved:
				return { name = anims.drag, speed = 1.0, hold = not bird }
			return { name = anims.idle, speed = 1.0, hold = false }
		State.WANDER:
			return { name = anims.walk, speed = 1.0, hold = false }
		State.GO_HOME:
			return { name = anims.walk, speed = 1.3, hold = false }
		State.ENTER_HOME, State.EXIT_HOME:
			# Held still while the ball's beam does its thing.
			return { name = anims.idle, speed = 1.0, hold = false }
		State.FALL:
			if bird:
				return { name = anims.fly, speed = 1.0, hold = false }
			return { name = anims.air, speed = 1.0, hold = true }
		State.HOP:
			if hop_crouch > 0.0:
				return { name = anims.crouch, speed = 0.0, hold = false }  # crouch pose
			return { name = anims.air, speed = 1.0, hold = true }
		State.PLAY:
			if ground_id == -2:
				return { name = anims.fly if bird else anims.air, speed = 1.0, hold = not bird }
			return { name = anims.walk, speed = 1.6, hold = false }
		_:
			return { name = anims.idle, speed = 1.0, hold = false }


## Consumes a command written to the bridge command file by an external
## process (e.g. the robot bridge).
func _consume_command() -> void:
	_mutex.lock()
	var cmd := _pending_cmd
	_pending_cmd = ""
	_mutex.unlock()
	match cmd:
		"enter_home":
			_head_home()
		"exit_home":
			if state == State.HOME:
				_start_exit_home()
		"feed":
			_feed()
		"play":
			if not play_mode and state != State.HOME:
				_toggle_play()


## Which grounded state to resume after landing.
func _grounded_state() -> State:
	if going_home:
		return State.GO_HOME
	return State.PLAY if play_mode else State.IDLE


## Sends the cat toward its house (from anywhere).
func _head_home() -> void:
	if state == State.HOME or state == State.ENTER_HOME or state == State.GO_HOME \
			or state == State.EXIT_HOME:
		return
	if state == State.NAP:
		_wake_up()
	play_mode = false
	going_home = true
	if state == State.IDLE or state == State.WANDER or state == State.PLAY:
		state = State.GO_HOME
	elif _is_bird() and state == State.FALL:
		_begin_flight()  # already airborne — retarget straight to the door


func _start_exit_home() -> void:
	visible = true
	win.mouse_passthrough_polygon = PackedVector2Array()  # clickable again
	home_node.cat_inside = false
	home_node.set_transfer("release", 0.0)
	pos_f = _door_feet() - Vector2(CENTER.x, FOOT_Y)
	_place_window()
	anim_progress = 0.0
	state = State.EXIT_HOME
	_write_state("virtual")
	_run_hook("on_exit_home")


func _go_home_tick(delta: float) -> void:
	var door := _door_feet()
	var dxd := door.x - _feet_x()
	if absf(_feet_y() - door.y) < 40.0 and absf(dxd) < 10.0:
		facing = 1 if door.x >= _feet_x() else -1
		anim_progress = 0.0
		state = State.ENTER_HOME
		return
	var p := _current_platform()
	if p.is_empty():
		_start_fall()  # going_home persists through the fall
		return
	pos_f.y = p.y - FOOT_Y
	facing = 1 if dxd > 0.0 else -1
	pos_f.x += signf(dxd) * minf(HOME_SPEED * delta, absf(dxd))
	var fx := _feet_x()
	if fx < p.x1 - LEDGE_MARGIN or fx > p.x2 + LEDGE_MARGIN:
		_start_fall()  # marches right off the edge on its way home
		return
	_place_window()


func _wander(delta: float) -> void:
	var p := _current_platform()
	if p.is_empty():
		_start_fall()
		return
	pos_f.y = p.y - FOOT_Y
	state_timer -= delta
	var lo: float = p.x1 + FOOT_HALF
	var hi: float = p.x2 - FOOT_HALF
	var fx := _feet_x() + wander_dir * WANDER_SPEED * delta
	if lo > hi:
		state = State.IDLE  # ledge too narrow to pace on
	elif fx < lo or fx > hi:
		if p.id != -1 and randf() < 0.3:
			# Sometimes it just walks off the edge.
			var over: float = p.x2 + FOOT_HALF if wander_dir > 0 else p.x1 - FOOT_HALF
			pos_f.x = over - CENTER.x
			_place_window()
			_start_fall()
			return
		wander_dir = -wander_dir
		facing = wander_dir
		pos_f.x = clampf(fx, lo, hi) - CENTER.x
	else:
		pos_f.x = fx - CENTER.x
	_place_window()
	if state == State.WANDER and state_timer <= 0.0:
		state = State.IDLE


## Picks a reachable ledge and starts a hop (or, for a parrot, a flight)
## toward it. Returns false if nothing is in range.
func _try_hop() -> bool:
	if _is_bird():
		var options := _flight_candidates()
		if options.is_empty():
			return false
		_fly_to(options.pick_random())
		return true
	var fx := _feet_x()
	var fy := _feet_y()
	var picks: Array = []
	for p in platforms:
		if p.id == ground_id:
			continue
		var lo: float = p.x1 + FOOT_HALF
		var hi: float = p.x2 - FOOT_HALF
		if lo > hi:
			continue
		var dy: float = p.y - fy  # negative = ledge is above us
		if dy < -HOP_MAX_UP or dy > HOP_MAX_DROP:
			continue
		var tx := clampf(fx + randf_range(-90.0, 90.0), lo, hi)
		if absf(tx - fx) > HOP_MAX_DX:
			continue
		# Solve the jump arc: apex comfortably above both ledges, then the
		# horizontal speed that arrives at tx exactly when we come down to p.y.
		var apex: float = minf(fy, p.y) - randf_range(200.0, 320.0)
		var vy0 := -sqrt(2.0 * GRAVITY * (fy - apex))
		var t_up := -vy0 / GRAVITY
		var t_down := sqrt(2.0 * maxf(p.y - apex, 1.0) / GRAVITY)
		var vx := (tx - fx) / (t_up + t_down)
		if absf(vx) > HOP_MAX_VX:
			continue  # too far to reach with a believable jump
		picks.append({ id = p.id, vy0 = vy0, vx = vx })
	if picks.is_empty():
		return false
	# Prefer perching on windows and icons over the plain Dock line.
	var fancy := picks.filter(func(c): return c.id != -1)
	if not fancy.is_empty():
		picks = fancy
	var choice: Dictionary = picks.pick_random()
	hop_vy = choice.vy0
	hop_vx = choice.vx
	hop_crouch = HOP_CROUCH
	if absf(hop_vx) > 1.0:
		facing = 1 if hop_vx > 0.0 else -1
	state = State.HOP
	return true


func _play(delta: float) -> void:
	play_timer -= delta
	if play_timer <= 0.0 and ground_id != -2:
		# All tired out — play is over, nap soon.
		play_mode = false
		nap_in = minf(nap_in, 6.0)
		state = State.IDLE
		return
	var mouse := Vector2(DisplayServer.mouse_get_position())
	var dx := mouse.x - _feet_x()
	if absf(dx) > 8.0:
		facing = 1 if dx > 0.0 else -1
	if ground_id == -2:
		# Mid-jump: gravity plus a little air steering toward the cursor.
		var steer := clampf(dx, -1.0, 1.0) * PLAY_SPEED * 0.5
		_airborne_step(delta, steer)
		return
	var p := _current_platform()
	if p.is_empty():
		ground_id = -2
		vy = 0.0
		return
	pos_f.y = p.y - FOOT_Y
	if absf(dx) > 12.0:
		pos_f.x += signf(dx) * minf(PLAY_SPEED * delta, absf(dx))
		var fx := _feet_x()
		if fx < p.x1 - LEDGE_MARGIN or fx > p.x2 + LEDGE_MARGIN:
			ground_id = -2  # chased right off the ledge
			vy = 0.0
	elif mouse.y < _feet_y() - 90.0 and randf() < delta * 2.5:
		# Cursor is overhead — pounce!
		ground_id = -2
		vy = JUMP_VY
	elif absf(dx) <= 12.0 and mouse.y >= _feet_y() - 90.0 and randf() < delta * 1.2:
		# Caught it! A little burst of musical notes overhead.
		_spawn(&"notes", _above_head(randf_range(-40.0, 40.0)) + Vector2(0, 65))
	_place_window()


# ----------------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_Q:
			get_tree().quit()
		elif event.keycode == KEY_P:
			_toggle_play()
		elif event.keycode == KEY_B:
			_toggle_form()
		elif event.keycode == KEY_H:
			if state == State.HOME:
				_start_exit_home()
			else:
				_head_home()
	elif event is InputEventMouseButton:
		if state == State.HOME or state == State.ENTER_HOME or state == State.EXIT_HOME:
			return  # mid-transition; the house handles its own clicks
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = DisplayServer.mouse_get_position()
				drag_offset = press_pos - Vector2i(pos_f.round())
				drag_moved = false
				going_home = false  # picking it up interrupts the trip home
				if state == State.NAP:
					_wake_up()
				if state != State.EAT:
					state = State.DRAG
			elif state == State.DRAG:
				_start_fall()  # drop wherever it was released
				if not drag_moved:
					_boop()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_feed()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_toggle_play()


func _toggle_form() -> void:
	form = ((form + 1) % FORM_DEFS.size()) as Form
	_load_form_sprites(form)
	if _is_bird() and (state == State.FALL or state == State.HOP):
		_begin_flight()  # mid-air shapeshift — give it a real destination


func _toggle_play() -> void:
	if state == State.HOME or state == State.ENTER_HOME or state == State.EXIT_HOME:
		return
	going_home = false
	play_mode = not play_mode
	if play_mode:
		play_timer = PLAY_LENGTH
		if state == State.NAP:
			_wake_up()
		if state == State.IDLE or state == State.WANDER:
			state = State.PLAY
		_spawn(&"notes", _above_head() + Vector2(0, 65))
	elif state == State.PLAY:
		state = State.IDLE


func _feed() -> void:
	if state == State.EAT or state == State.FALL or state == State.DRAG \
			or state == State.HOME or state == State.ENTER_HOME \
			or state == State.EXIT_HOME:
		return
	if state == State.NAP:
		_wake_up()
	if state == State.PLAY and ground_id == -2:
		return  # can't eat mid-jump
	eat_progress = 0.0
	state = State.EAT


func _boop() -> void:
	_spawn(&"heart", _above_head(randf_range(-40.0, 40.0)))


func _start_wander() -> void:
	wander_dir = 1 if randf() < 0.5 else -1
	facing = wander_dir
	state_timer = randf_range(1.5, 4.0)
	state = State.WANDER


func _start_nap() -> void:
	state = State.NAP
	state_timer = randf_range(NAP_LENGTH_MIN, NAP_LENGTH_MAX)


func _wake_up() -> void:
	nap_in = randf_range(NAP_MIN, NAP_MAX)
	state = State.IDLE


func _spawn(kind: StringName, pos: Vector2) -> void:
	particles.append({ kind = kind, pos = pos, age = 0.0 })


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.age += delta
		var v: Dictionary = _vfx.get(p.kind, {})
		if not v.is_empty():
			# VFX overlays animate inside their frames — stationary, one
			# play-through, then gone.
			if p.age >= v.frames.size() * v.ft:
				particles.remove_at(i)
			continue
		p.pos += Vector2(22.0 * sin(p.age * 3.0), -42.0) * delta
		if p.age >= 2.2:
			particles.remove_at(i)


# ----------------------------------------------------------------------------
# Drawing — the characters come from PMD sprite sheets; the shadow, cookie,
# and floating particles are still drawn procedurally.
# ----------------------------------------------------------------------------

func _draw() -> void:
	var airborne := (state == State.DRAG and drag_moved) or state == State.FALL \
		or ground_id == -2

	# Shadow: the sheet's own pixel shadow resting on the ledge, clipped
	# horizontally to the ledge so it never hangs past an edge into thin air.
	if not airborne:
		var lo := -INF
		var hi := INF
		var p := _current_platform()
		if not p.is_empty() and p.x2 > p.x1:
			lo = p.x1 - pos_f.x
			hi = p.x2 - pos_f.x
		_draw_pet_shadow(lo, hi)

	_draw_sprite()

	# Cookie being eaten (held in front of the snout/beak)
	if state == State.EAT:
		var cookie_scale := 1.0 - eat_progress
		if cookie_scale > 0.05:
			var mtr := _m()
			var cookie_pos := Vector2(
				CENTER.x + facing * (mtr.half_w * SPRITE_SCALE + 30.0),
				FOOT_Y - mtr.height * SPRITE_SCALE * 0.45)
			draw_set_transform(cookie_pos, 0.0, Vector2(cookie_scale, cookie_scale))
			draw_circle(Vector2.ZERO, 28.0, Color("c98a4b"))
			for chip in [Vector2(-10, -8), Vector2(10, -3), Vector2(-3, 12)]:
				draw_circle(chip, 5.0, Color("6b4226"))

	# Floating particles
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p in particles:
		var alpha: float = clampf(1.0 - p.age / 2.2, 0.0, 1.0)
		match p.kind:
			&"heart":
				_draw_heart(p.pos, 2.5 + p.age * 0.5, Color(1.0, 0.42, 0.5, alpha))
			&"notes", &"zzz":
				_draw_vfx(p)
			&"thought":
				draw_circle(p.pos, 34.0, Color(1, 1, 1, alpha * 0.85))
				draw_circle(p.pos + Vector2(-30, 30), 10.0, Color(1, 1, 1, alpha * 0.7))
				draw_circle(p.pos, 16.0, Color("c98a4b", alpha))


## The character's PMD pixel shadow for the current frame — the sheet's
## `<Anim>-Shadow.png` marker recolored black at load — drawn translucent
## under the sprite exactly where the sheet places it (ellipse centered on
## the feet line), clipped to [lo, hi] (the ledge's extent in window-local
## x). Falls back to the smooth ellipse for sheets without a shadow file.
func _draw_pet_shadow(lo: float, hi: float) -> void:
	var fi := _frame_info()
	if fi.is_empty() or fi.sp.shadow == null:
		_draw_shadow(lo, hi, _m().half_w * SPRITE_SCALE * 1.15)
		return
	var sp: Dictionary = fi.sp
	# A ledge narrower than the shadow itself (the ball's crown, mostly)
	# shrinks the whole shadow to fit instead of chopping its sides off;
	# clipping is kept for the ordinary near-an-edge overhang case.
	var k := 1.0
	var sw: float = sp.shalf * 2.0 * SPRITE_SCALE
	if hi - lo < sw:
		k = maxf((hi - lo) / sw, 0.3)
	var sx: float = (1.0 + fi.squash) * (-1.0 if fi.flip else 1.0) * k
	var sy: float = (1.0 - fi.squash) * k
	# The ledge interval mapped into the sprite's local (scaled/flipped) space.
	var a: float = (lo - CENTER.x) / sx
	var b: float = (hi - CENTER.x) / sx
	var w: float = sp.fw * SPRITE_SCALE
	var x0: float = maxf(-w * 0.5, minf(a, b))
	var x1: float = minf(w * 0.5, maxf(a, b))
	if x1 <= x0:
		return
	var src_x: float = (int(sp.col0) + fi.idx) * sp.fw + x0 / SPRITE_SCALE + sp.fw * 0.5
	draw_set_transform(Vector2(CENTER.x, FOOT_Y), 0.0, Vector2(sx, sy))
	draw_texture_rect_region(sp.shadow,
		Rect2(x0, -sp.foot * SPRITE_SCALE, x1 - x0, sp.fh * SPRITE_SCALE),
		Rect2(src_x, fi.row * sp.fh, (x1 - x0) / SPRITE_SCALE, sp.fh),
		Color(1, 1, 1, 0.20))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Fallback shadow ellipse whose bottom touches the feet line, clipped to
## [lo, hi] (the ledge's extent in window-local x). rx varies per character.
func _draw_shadow(lo: float, hi: float, rx: float) -> void:
	var ry := rx * 0.2
	var cy := FOOT_Y - ry
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(Vector2(
			clampf(CENTER.x + cos(a) * rx, lo, hi),
			cy + sin(a) * ry
		))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.16))


## Sheet + frame index + row/flip/squash for the current animation state,
## shared by the sprite and its shadow. {} while sheets are missing.
func _frame_info() -> Dictionary:
	var sheets: Dictionary = _sprites.get(form, {})
	if not sheets.has(_anim_name):
		return {}
	var sp: Dictionary = sheets[_anim_name]
	var flip := false
	var row := 0
	if int(sp.rows) >= 8:
		row = 2 if facing > 0 else 6  # PMD rows: 0=down, 2=right, 4=up, 6=left
	else:
		flip = facing < 0  # single-direction sheet — mirror it instead
	return {
		sp = sp,
		idx = _anim_frame_index(sp, _current_anim().hold),
		row = row, flip = flip,
		squash = land_squish * 0.5 \
			+ (0.15 if state == State.HOP and hop_crouch > 0.0 else 0.0),
	}


## Draws the current character's animation frame, anchored so the sprite's
## content bottom (its feet) sits on the FOOT_Y line.
func _draw_sprite() -> void:
	var fi := _frame_info()
	if fi.is_empty():
		return  # sheets missing — pet stays functional, just invisible
	var sp: Dictionary = fi.sp
	var w: float = sp.fw * SPRITE_SCALE
	var h: float = sp.fh * SPRITE_SCALE
	var foot: float = sp.foot * SPRITE_SCALE
	draw_set_transform(Vector2(CENTER.x, FOOT_Y), 0.0,
		Vector2((1.0 + fi.squash) * (-1.0 if fi.flip else 1.0), 1.0 - fi.squash))
	draw_texture_rect_region(sp.tex,
		Rect2(-w * 0.5, -foot, w, h),
		Rect2((int(sp.col0) + fi.idx) * sp.fw, fi.row * sp.fh, sp.fw, sp.fh))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Current frame index from the animation clock and per-frame durations.
func _anim_frame_index(sp: Dictionary, hold: bool) -> int:
	var durs: Array = sp.durs
	if durs.is_empty():
		return 0
	var total: float = sp.total
	if hold and _anim_clock >= total:
		return durs.size() - 1
	var tt := fmod(_anim_clock, total)
	for i in durs.size():
		tt -= durs[i]
		if tt < 0.0:
			return i
	return durs.size() - 1


## Loads one character's sheets straight from disk (no editor import needed):
## parses AnimData.xml for frame sizes and durations, then finds the feet
## line of each sheet by scanning frame 0's alpha.
func _load_form_sprites(fi: int) -> void:
	if _sprites.has(fi):
		return
	var def: Dictionary = FORM_DEFS[fi]
	var dir := ProjectSettings.globalize_path("res://sprites/" + def.name)
	var xml := FileAccess.get_file_as_string(dir.path_join("AnimData.xml"))
	if xml == "":
		push_warning("sprites/%s/AnimData.xml not found — %s will be invisible."
			% [def.name, def.name])
		_sprites[fi] = {}
		return
	var info := {}  # anim name -> {fw, fh, durs}
	for block in xml.split("<Anim>"):
		if not (block.contains("</Name>") and block.contains("<FrameWidth>")):
			continue  # header junk or CopyOf-alias entries without own sheet
		var aname := block.get_slice("<Name>", 1).get_slice("</Name>", 0)
		var durs: Array[float] = []
		var parts := block.split("<Duration>")
		for i in range(1, parts.size()):
			durs.append(parts[i].get_slice("</Duration>", 0).to_float() * SPRITE_TICK)
		info[aname] = {
			fw = block.get_slice("<FrameWidth>", 1).get_slice("</FrameWidth>", 0).to_int(),
			fh = block.get_slice("<FrameHeight>", 1).get_slice("</FrameHeight>", 0).to_int(),
			durs = durs,
		}
	var sheets := {}
	for spec in def.anims.values():
		# spec is "Sheet" or "Sheet:first-last[:ticks]" (frame subset).
		var aname: String = spec.get_slice(":", 0)
		if spec == "" or sheets.has(spec) or not info.has(aname):
			continue
		var img := Image.load_from_file(dir.path_join(aname + "-Anim.png"))
		if img == null:
			continue
		var meta: Dictionary = info[aname]
		var fw: int = meta.fw
		var fh: int = meta.fh
		var rows := img.get_height() / fh
		var durs: Array = meta.durs
		var col0 := 0
		if spec.contains(":"):
			var rng: String = spec.get_slice(":", 1)
			col0 = rng.get_slice("-", 0).to_int()
			var last := mini(rng.get_slice("-", 1).to_int(), durs.size() - 1)
			durs = durs.slice(col0, last + 1)
			if spec.get_slice_count(":") > 2:
				var tick: float = spec.get_slice(":", 2).to_float() * SPRITE_TICK
				durs = durs.map(func(_d): return tick)
		# Content bounds of the anim's first frame in the right-facing row
		# (or the only row): the bottom anchors every anim on the same ground
		# line, the full box drives the click-through region around the sprite.
		var scan_row := 2 if rows >= 8 else 0
		var minx := fw
		var maxx := -1
		var miny := fh
		var maxy := -1
		for y in fh:
			for x in fw:
				if img.get_pixel(col0 * fw + x, scan_row * fh + y).a > 0.1:
					minx = mini(minx, x)
					maxx = maxi(maxx, x)
					miny = mini(miny, y)
					maxy = maxi(maxy, y)
		if maxy < 0:  # fully transparent frame — fall back to full frame
			minx = 0
			maxx = fw - 1
			miny = 0
			maxy = fh - 1
		# The matching pixel shadow sheet (<Anim>-Shadow.png, same frame
		# grid): PMD marks the shadow ellipse in blue/red/green/white size
		# layers, centered on the frame's ground line — recolored to plain
		# black here, translucency comes from the draw-time modulate.
		var shadow_tex: ImageTexture = null
		var shalf := fw * 0.5  # shadow content half-width, for narrow ledges
		var simg := Image.load_from_file(dir.path_join(aname + "-Shadow.png"))
		if simg != null and simg.get_size() == img.get_size():
			var sminx := fw
			var smaxx := -1
			for y in fh:
				for x in fw:
					if simg.get_pixel(col0 * fw + x, scan_row * fh + y).a > 0.1:
						sminx = mini(sminx, x)
						smaxx = maxi(smaxx, x)
			if smaxx >= 0:
				shalf = maxf(fw * 0.5 - sminx, smaxx + 1 - fw * 0.5)
			for y in simg.get_height():
				for x in simg.get_width():
					if simg.get_pixel(x, y).a > 0.1:
						simg.set_pixel(x, y, Color.BLACK)
			shadow_tex = ImageTexture.create_from_image(simg)
		var total := 0.0
		for d in durs:
			total += d
		sheets[spec] = {
			tex = ImageTexture.create_from_image(img),
			fw = fw, fh = fh, rows = rows, col0 = col0,
			durs = durs, total = maxf(total, 0.01),
			foot = float(maxy + 1), top = float(miny),
			half_w = maxf(fw * 0.5 - minx, maxx + 1 - fw * 0.5),
			shadow = shadow_tex, shalf = shalf,
		}
	_sprites[fi] = sheets
	# Idle-pose metrics for shadow/particle/cookie placement.
	if sheets.has(def.anims.idle):
		var idle: Dictionary = sheets[def.anims.idle]
		_metrics[fi] = {
			half_w = maxf(idle.half_w, 4.0),
			height = maxf(idle.foot - idle.top, 8.0),
		}
	else:
		_metrics[fi] = { half_w = 12.0, height = 24.0 }


## One frame of a move_VFX overlay animation, bottom-center anchored on the
## particle's position, with a quick fade right at the end of its life.
func _draw_vfx(p: Dictionary) -> void:
	var v: Dictionary = _vfx.get(p.kind, {})
	if v.is_empty():
		return
	var frames: Array = v.frames
	var idx := clampi(int(p.age / v.ft), 0, frames.size() - 1)
	var tex: Texture2D = frames[idx]
	var tw: float = tex.get_width() * v.sc
	var th: float = tex.get_height() * v.sc
	var a := clampf((frames.size() * v.ft - p.age) / 0.25, 0.0, 1.0)
	draw_texture_rect(tex, Rect2(p.pos.x - tw * 0.5, p.pos.y - th, tw, th),
		false, Color(1, 1, 1, a))


## Loads the move_VFX overlay animations played by _draw_vfx, straight from
## disk like the character sheets: musical notes for play mode (0007/001,
## one PNG per frame) and the wobbling Zzz bubble for naps (0078/<frame>/,
## one PNG inside each numbered folder). Frame canvases vary per frame, so
## they are drawn bottom-center anchored.
func _load_vfx() -> void:
	var notes: Array = []
	var dir := ProjectSettings.globalize_path("res://sprites/move_VFX/0007/001")
	var files: Array = Array(DirAccess.get_files_at(dir))
	files = files.filter(func(f): return str(f).ends_with(".png"))
	files.sort()
	# 011.png is a baked-in one-frame "blink" (the right-hand note vanishes
	# and pops back on 012) — natural at GBA frame rates, a flicker at ours.
	# Without it the note simply drops out for good at 013.
	files.erase("011.png")
	for f in files:
		var img := Image.load_from_file(dir.path_join(f))
		if img != null:
			notes.append(ImageTexture.create_from_image(img))
	if notes.is_empty():
		push_warning("sprites/move_VFX/0007/001 not found — play notes VFX disabled.")
	else:
		_vfx[&"notes"] = { frames = notes, ft = 0.07, sc = VFX_SCALE * 1.5 }
	var zzz: Array = []
	for i in 8:
		var img := Image.load_from_file(ProjectSettings.globalize_path(
			"res://sprites/move_VFX/0078/%03d/000.png" % i))
		if img != null:
			zzz.append(ImageTexture.create_from_image(img))
	if zzz.is_empty():
		push_warning("sprites/move_VFX/0078 not found — nap Zzz VFX disabled.")
	else:
		_vfx[&"zzz"] = { frames = zzz, ft = 0.16, sc = VFX_SCALE }


func _draw_heart(pos: Vector2, s: float, color: Color) -> void:
	draw_set_transform(pos, 0.0, Vector2(s, s))
	draw_circle(Vector2(-3.2, -2.0), 4.0, color)
	draw_circle(Vector2(3.2, -2.0), 4.0, color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6.8, 0.0), Vector2(6.8, 0.0), Vector2(0.0, 8.5)
	]), color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
