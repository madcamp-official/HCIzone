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
##  - Press B to toggle bird mode: it becomes a parrot and flies smoothly
##    between ledges instead of jumping. Sleep, play mode, feeding, and going
##    home all work exactly the same either way.
##  - Esc or Q quits.
##
## Other windows are detected by helpers/window_list (a tiny CoreGraphics
## helper, see helpers/window_list.c). Desktop icons are read from Finder via
## osascript (macOS will ask once for permission to control Finder; if denied,
## the pet simply ignores icons). Without the helper the pet still works but
## only knows about the Dock line and screen bottom.

enum State { IDLE, WANDER, EAT, NAP, DRAG, FALL, PLAY, HOP, GO_HOME, ENTER_HOME, HOME, EXIT_HOME }
enum Form { CAT, PARROT }

const CENTER := Vector2(110.0, 118.0)
const FOOT_Y := 162.0        # feet line, in window-local pixels
const FOOT_HALF := 22.0      # half-width of the pet's footprint
const GRAVITY := 2600.0
const MAX_FALL_SPEED := 1600.0
const MIN_LEDGE := 70.0      # narrowest window edge worth standing on
const MIN_ICON_LEDGE := 30.0 # icons are small; allow narrower perches
const LEDGE_MARGIN := 6.0    # how far feet may hang past a ledge
const BODY_COLOR := Color("f2a65a")
const BELLY_COLOR := Color("ffd9a8")
const DARK := Color("5a3a22")
const BLUSH := Color(1.0, 0.55, 0.55, 0.5)
const WANDER_SPEED := 55.0
const PLAY_SPEED := 230.0    # chase speed in play mode
const JUMP_VY := -1150.0     # jump impulse in play mode
const PLAY_LENGTH := 35.0    # seconds of play before it gets tired
const HOP_MAX_UP := 950.0    # highest ledge it will hop up to (cartoon legs)
const HOP_MAX_DROP := 1200.0 # furthest it will hop down
const HOP_MAX_DX := 720.0    # horizontal hop reach
const HOP_MAX_VX := 620.0    # fastest horizontal hop speed
const HOP_CROUCH := 0.18     # wind-up squat before launching
const FLY_SPEED := 260.0     # parrot flight speed between ledges
const FLY_MAX_RANGE := 1500.0
const FLY_ARRIVE_DIST := 16.0
const DROP_SNAP_UP := 120.0  # dropped parrot may snap up to a ledge this far above its feet
const HUNGRY_AFTER := 45.0   # seconds until the cat looks hungry
const NAP_MIN := 25.0        # seconds of wakefulness before a nap can start
const NAP_MAX := 60.0
const NAP_LENGTH_MIN := 12.0
const NAP_LENGTH_MAX := 25.0
const HOME_W := 190          # home window size
const HOME_H := 170
const HOME_FLOOR := 158.0    # floor line inside the home window
const HOME_DOOR_X := 95.0    # doorway center
const HOME_SPEED := 180.0    # walking speed when heading home
const ENTER_TIME := 0.7      # seconds to slip into / out of the door
const HomeArt := preload("res://home.gd")

var state: State = State.FALL   # spawn in the air and drop onto something
var t := 0.0                 # global animation clock
var state_timer := 0.0       # counts down inside timed states
var facing := 1              # 1 = facing right, -1 = facing left

var blink := 0.0             # >0 while eyes are mid-blink
var blink_timer := 2.0

var hunger := 0.0
var nap_in := 0.0            # wall-clock until the next nap

var eat_progress := 0.0      # 0..1 while a cookie is being eaten

var wander_dir := 1

var play_mode := false
var play_timer := 0.0

var hop_vy := 0.0            # launch velocities for the pending hop
var hop_vx := 0.0
var hop_crouch := 0.0        # >0 while winding up to jump

var form: Form = Form.PARROT # cat walks and jumps; parrot flies instead
var fly_target := Vector2.ZERO       # feet destination while flying (global px)
var fly_target_ground := -1          # platform id fly_target sits on
var fly_bob_time := 0.0

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
var pos_f := Vector2.ZERO    # float mirror of the OS window position
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
var _icons_supported := OS.get_name() == "macOS"  # icons come from Finder
var _helper_path := ""
var _icons_script_path := ""

# Floating decorations: hearts when booped, z's while napping,
# and a cookie thought-bubble when hungry.
var particles: Array[Dictionary] = []

@onready var win: Window = get_window()

# Run with PET_DEBUG=1 in the environment to log state once per second.
@onready var _debug := OS.get_environment("PET_DEBUG") != ""


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
		win.position = Vector2i(pos_f.round())
	var helper_file := "window_list.exe" if OS.get_name() == "Windows" else "window_list"
	_helper_path = ProjectSettings.globalize_path("res://helpers/" + helper_file)
	_icons_script_path = ProjectSettings.globalize_path("res://helpers/desktop_icons.applescript")
	# PET_PLAY=1 starts in play mode (handy for testing).
	if OS.get_environment("PET_PLAY") != "":
		_toggle_play()
	# PET_FORM=cat or parrot forces a starting form (handy for testing).
	match OS.get_environment("PET_FORM").to_lower():
		"cat": form = Form.CAT
		"parrot": form = Form.PARROT
	if form == Form.PARROT:
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
	home_win.window_input.connect(_on_home_input)
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	home_win.position = Vector2i(usable.end.x - HOME_W - 80, usable.end.y - int(HOME_FLOOR))


## Where feet stand when at the doorway, in global pixels.
func _door_feet() -> Vector2:
	return Vector2(home_win.position) + Vector2(HOME_DOOR_X, HOME_FLOOR)


## Keeps the house sitting on the Dock line (the user drags it only sideways).
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
				# A click on the house summons the cat home, or lets it out.
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
		# No room for the pet above edges too close to the menu bar,
		# and edges at/under the Dock line are pointless.
		if y < usable.position.y + 40.0 or y > usable.end.y - 2.0:
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
		if y < usable.position.y + 40.0 or y > usable.end.y - 2.0:
			continue
		var segs: Array[Vector2] = [Vector2(c.x - icon_half, c.x + icon_half)]
		for r in scaled:
			if r.position.y < y and r.end.y > y:
				segs = _subtract_interval(segs, r.position.x, r.end.x)
		for s in segs:
			if s.y - s.x >= MIN_ICON_LEDGE:
				platforms.append({ id = -1000 - k, y = y, x1 = s.x, x2 = s.y })
	# The house's roof ridge is a wonderful perch.
	if home_win:
		var hp := Vector2(home_win.position)
		platforms.append({
			id = -2000, y = hp.y + 24.0,
			x1 = hp.x + HOME_DOOR_X - 20.0, x2 = hp.x + HOME_DOOR_X + 20.0,
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
	win.position = Vector2i(pos_f.round())
	return true


func _start_fall() -> void:
	if state == State.NAP:
		nap_in = randf_range(NAP_MIN, NAP_MAX)  # rude awakening
	land_squish = 0.0
	if form == Form.PARROT:
		_begin_flight()  # a parrot doesn't fall — it takes off
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


## Lands the pet after a drag release. The cat just falls, so it settles on the
## ledge below the drop point. The parrot must NOT _begin_flight here — that
## picks a random perch and the drop position would be ignored entirely.
## Instead it glides down onto the same ledge gravity would find (with a small
## upward snap, so releasing it slightly onto a window still perches on it).
func _drop_release() -> void:
	if form != Form.PARROT:
		_start_fall()
		return
	land_squish = 0.0
	var fx := _feet_x()
	var fy := _feet_y()
	var best := {}
	for p in platforms:
		if fx < p.x1 - LEDGE_MARGIN or fx > p.x2 + LEDGE_MARGIN:
			continue
		if p.y < fy - DROP_SNAP_UP:
			continue  # too far above to snap up onto
		if best.is_empty() or p.y < best.y:
			best = p
	if best.is_empty():
		_start_fall()  # released past the screen edge — fly off to some perch
		return
	var lo: float = best.x1 + FOOT_HALF
	var hi: float = best.x2 - FOOT_HALF
	fly_target = Vector2(clampf(fx, lo, hi) if lo <= hi else (best.x1 + best.x2) * 0.5, best.y)
	fly_target_ground = best.id
	ground_id = -2
	vy = 0.0
	state = State.FALL


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
		win.position = Vector2i(pos_f.round())
		return true
	var dir := to_target.normalized()
	if absf(dir.x) > 0.05:
		facing = 1 if dir.x > 0.0 else -1
	pos_f += dir * FLY_SPEED * delta
	pos_f.y += sin(fly_bob_time * 6.0) * 0.5
	win.position = Vector2i(pos_f.round())
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
		win.position = Vector2i(pos_f.round())
		return true
	win.position = Vector2i(pos_f.round())
	return false


# ----------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	_update_blink(delta)
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
				_spawn(&"thought", CENTER + Vector2(38 * facing, -62))
		State.WANDER:
			_wander(delta)
		State.EAT:
			_stick_to_ground()
			if state == State.EAT:  # may have started falling
				eat_progress += delta / 1.6
				if eat_progress >= 1.0:
					hunger = 0.0
					_spawn(&"heart", CENTER + Vector2(0, -60))
					state = _grounded_state()
		State.NAP:
			if _stick_to_ground():
				state_timer -= delta
				if fmod(t, 1.4) < delta:
					_spawn(&"zzz", CENTER + Vector2(28 * facing, -48))
				if state_timer <= 0.0:
					_wake_up()
		State.FALL:
			if form == Form.PARROT:
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
			var door := _door_feet()
			pos_f.x = lerpf(pos_f.x, door.x - CENTER.x, minf(anim_progress * 1.5, 1.0))
			pos_f.y = door.y - FOOT_Y
			win.position = Vector2i(pos_f.round())
			if anim_progress >= 1.0:
				going_home = false
				state = State.HOME
				# The main window can't be hidden, so vanish by other means:
				# stop drawing and let every click pass straight through.
				visible = false
				win.mouse_passthrough_polygon = PackedVector2Array([
					Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
				home_node.cat_inside = true
				_write_state("home")
				_run_hook("on_enter_home")
		State.HOME:
			pass  # the soul is in the robot now; the house's eyes blink for us
		State.EXIT_HOME:
			anim_progress += delta / ENTER_TIME
			pos_f = _door_feet() - Vector2(CENTER.x, FOOT_Y)
			win.position = Vector2i(pos_f.round())
			if anim_progress >= 1.0:
				if form == Form.PARROT:
					_begin_flight()  # flies out and off to the nearest perch
				else:
					# Pop out with a little hop, away from the house wall.
					var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
					var mid := (usable.position.x + usable.end.x) * 0.5
					hop_vx = (1.0 if _feet_x() < mid else -1.0) * randf_range(130.0, 210.0)
					facing = 1 if hop_vx > 0.0 else -1
					vy = -650.0
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
				win.position = mouse - drag_offset

	# Shrink into / grow out of the doorway.
	if state == State.ENTER_HOME or state == State.EXIT_HOME:
		var s := clampf(1.0 - anim_progress if state == State.ENTER_HOME else anim_progress,
			0.0, 1.0)
		scale = Vector2(s, s)
		position = Vector2(CENTER.x, FOOT_Y) * (1.0 - s)
		modulate.a = maxf(s, 0.15)
	elif scale != Vector2.ONE:
		scale = Vector2.ONE
		position = Vector2.ZERO
		modulate.a = 1.0

	if _debug and fmod(t, 1.0) < delta:
		print("state=%-9s form=%-6s pos=%s ground=%d home=%s icons=[%s] ledges=%s" % [
			State.keys()[state], Form.keys()[form], win.position, ground_id, home_win.position,
			_icon_status,
			platforms.map(func(p): return Vector2i(int(p.x1), int(p.y)))])

	queue_redraw()


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
	elif form == Form.PARROT and state == State.FALL:
		_begin_flight()  # already airborne — retarget straight to the door


func _start_exit_home() -> void:
	visible = true
	win.mouse_passthrough_polygon = PackedVector2Array()  # clickable again
	home_node.cat_inside = false
	pos_f = _door_feet() - Vector2(CENTER.x, FOOT_Y)
	win.position = Vector2i(pos_f.round())
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
	win.position = Vector2i(pos_f.round())


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
			win.position = Vector2i(pos_f.round())
			_start_fall()
			return
		wander_dir = -wander_dir
		facing = wander_dir
		pos_f.x = clampf(fx, lo, hi) - CENTER.x
	else:
		pos_f.x = fx - CENTER.x
	win.position = Vector2i(pos_f.round())
	if state == State.WANDER and state_timer <= 0.0:
		state = State.IDLE


## Picks a reachable ledge and starts a hop (or, for a parrot, a flight)
## toward it. Returns false if nothing is in range.
func _try_hop() -> bool:
	if form == Form.PARROT:
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
		var apex: float = minf(fy, p.y) - randf_range(80.0, 150.0)
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
		_spawn(&"heart", CENTER + Vector2(randf_range(-14, 14), -58))  # caught it!
	win.position = Vector2i(pos_f.round())


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
				drag_offset = press_pos - win.position
				drag_moved = false
				going_home = false  # picking it up interrupts the trip home
				if state == State.NAP:
					_wake_up()
				if state != State.EAT:
					state = State.DRAG
			elif state == State.DRAG:
				_drop_release()  # settle right where it was released
				if not drag_moved:
					_boop()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_feed()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_toggle_play()


func _toggle_form() -> void:
	form = Form.PARROT if form == Form.CAT else Form.CAT
	if form == Form.PARROT and (state == State.FALL or state == State.HOP):
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
		_spawn(&"heart", CENTER + Vector2(0, -64))
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
	_spawn(&"heart", CENTER + Vector2(randf_range(-14, 14), -58))


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


func _update_blink(delta: float) -> void:
	if blink > 0.0:
		blink -= delta
	else:
		blink_timer -= delta
		if blink_timer <= 0.0:
			blink = 0.12
			blink_timer = randf_range(2.0, 5.0)


func _spawn(kind: StringName, pos: Vector2) -> void:
	particles.append({ kind = kind, pos = pos, age = 0.0 })


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.age += delta
		p.pos += Vector2(10.0 * sin(p.age * 3.0), -18.0) * delta
		if p.age >= 2.2:
			particles.remove_at(i)


# ----------------------------------------------------------------------------
# Drawing — the whole cat is procedural, no image assets needed.
# ----------------------------------------------------------------------------

func _draw() -> void:
	var napping := state == State.NAP
	var eating := state == State.EAT
	var playing := state == State.PLAY and ground_id != -2
	var breathe := sin(t * (1.6 if napping else 3.2)) * (0.045 if napping else 0.025)
	var airborne := (state == State.DRAG and drag_moved) or state == State.FALL \
		or ground_id == -2

	# Shadow: an ellipse resting ON the ledge (entirely above the feet line so
	# the Dock — which draws over us — can't cut it off), clipped horizontally
	# to the ledge so it never hangs past an edge into thin air.
	if not airborne:
		var lo := -INF
		var hi := INF
		var p := _current_platform()
		if not p.is_empty() and p.x2 > p.x1:
			lo = p.x1 - pos_f.x
			hi = p.x2 - pos_f.x
		_draw_shadow(lo, hi)

	# Dangling feet while carried or falling (cat only — a flying parrot
	# tucks its feet; its wings carry the "airborne" read instead)
	if airborne and form == Form.CAT:
		var kick := sin(t * 10.0) * 5.0
		draw_set_transform(CENTER, 0.0, Vector2.ONE)
		draw_circle(Vector2(-18, 44 + kick), 8.0, BODY_COLOR.darkened(0.08))
		draw_circle(Vector2(18, 44 - kick), 8.0, BODY_COLOR.darkened(0.08))

	# Squash: with breathing, when napping, on landing, and while crouching
	# before a (cat-only) hop.
	var squash := (0.12 if napping else 0.0) + land_squish * 0.7 \
		+ (0.18 if state == State.HOP and hop_crouch > 0.0 else 0.0)
	var f := Vector2(facing * 6.0, -6.0)  # face shifts toward facing direction
	var eyes_closed := napping or blink > 0.0

	if form == Form.CAT:
		# Tail
		draw_set_transform(CENTER, 0.0, Vector2.ONE)
		var tail_speed := 9.0 if (airborne or playing) else (2.0 if napping else 5.0)
		var tail_points := PackedVector2Array()
		for i in 12:
			var u := i / 11.0
			var wag := (0.6 if napping else 1.0) * sin(t * tail_speed + u * 3.0)
			tail_points.append(Vector2(
				-facing * (38.0 + u * 26.0),
				22.0 - u * 30.0 + wag * 7.0 * u
			))
		draw_polyline(tail_points, BODY_COLOR.darkened(0.12), 9.0, true)

		# Body (squishes with breathing)
		draw_set_transform(CENTER, 0.0, Vector2(1.0 + breathe + squash, 1.0 - breathe - squash))
		draw_circle(Vector2.ZERO, 44.0, BODY_COLOR)
		draw_set_transform(CENTER + Vector2(0, 12), 0.0, Vector2(1.0 + breathe, 0.8))
		draw_circle(Vector2.ZERO, 28.0, BELLY_COLOR)

		# Ears
		draw_set_transform(CENTER, 0.0, Vector2(1.0, 1.0 - squash))
		for side in [-1, 1]:
			var base := Vector2(side * 26.0, -32.0)
			var flick := 2.0 * sin(t * 7.0 + side) * (0.0 if napping else 1.0)
			draw_colored_polygon(PackedVector2Array([
				base + Vector2(-11, 6), base + Vector2(11, 6), base + Vector2(side * 4 + flick, -20)
			]), BODY_COLOR.darkened(0.05))
			draw_colored_polygon(PackedVector2Array([
				base + Vector2(-5, 3), base + Vector2(5, 3), base + Vector2(side * 2 + flick, -12)
			]), Color("e8896b"))

		# Face
		draw_set_transform(CENTER + f, 0.0, Vector2.ONE)
		for side in [-1, 1]:
			var e := Vector2(side * 15.0, -6.0)
			if eyes_closed:
				# Gentle closed-eye arcs
				draw_arc(e + Vector2(0, 1), 5.0, PI * 0.15, PI * 0.85, 8, DARK, 2.4, true)
			else:
				var pupil := 6.0 if (airborne or playing) else 5.0  # wide-eyed
				draw_circle(e, pupil, DARK)
				draw_circle(e + Vector2(1.5, -1.5), 1.7, Color.WHITE)
				if playing:
					draw_circle(e + Vector2(-1.5, 1.0), 1.0, Color.WHITE)  # sparkle
		# Blush
		draw_circle(Vector2(-22, 4), 5.0, BLUSH)
		draw_circle(Vector2(22, 4), 5.0, BLUSH)
		# Nose + mouth
		draw_circle(Vector2(0, 3), 2.6, Color("d96c5f"))
		if eating:
			var chomp: float = 3.0 + 3.0 * absf(sin(t * 12.0))
			draw_circle(Vector2(0, 11), chomp, DARK)
		elif airborne:
			draw_circle(Vector2(0, 11), 3.0, DARK)  # little surprised "o"
		elif napping:
			draw_arc(Vector2(0, 10), 4.0, PI * 0.1, PI * 0.9, 8, DARK, 2.0, true)
		elif playing:
			# Big open smile
			draw_arc(Vector2(0, 9), 5.5, PI * 0.08, PI * 0.92, 10, DARK, 2.4, true)
		elif hunger > HUNGRY_AFTER:
			# Sad little mouth when hungry
			draw_arc(Vector2(0, 14), 5.0, PI * 1.15, PI * 1.85, 8, DARK, 2.0, true)
		else:
			draw_arc(Vector2(-3, 8), 3.0, PI * 0.1, PI * 0.9, 8, DARK, 2.0, true)
			draw_arc(Vector2(3, 8), 3.0, PI * 0.1, PI * 0.9, 8, DARK, 2.0, true)
		# Whiskers
		for side in [-1, 1]:
			for w in 2:
				var y := 2.0 + w * 5.0
				draw_line(Vector2(side * 24.0, y), Vector2(side * 38.0, y - 2.0 + w * 4.0),
					Color(DARK, 0.5), 1.4, true)
	else:
		_draw_parrot(napping, eating, playing, breathe, squash, airborne, eyes_closed, f)

	# Cookie being eaten
	if eating:
		var cookie_scale := 1.0 - eat_progress
		if cookie_scale > 0.05:
			var anchor := (Vector2(facing * 30.0, 14.0) if form == Form.CAT
				else Vector2(facing * 32.0, -20.0))
			var cookie_pos := CENTER + f + anchor
			draw_set_transform(cookie_pos, 0.0, Vector2(cookie_scale, cookie_scale))
			draw_circle(Vector2.ZERO, 11.0, Color("c98a4b"))
			for chip in [Vector2(-4, -3), Vector2(4, -1), Vector2(-1, 5)]:
				draw_circle(chip, 2.0, Color("6b4226"))

	# Floating particles
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	for p in particles:
		var alpha: float = clampf(1.0 - p.age / 2.2, 0.0, 1.0)
		match p.kind:
			&"heart":
				_draw_heart(p.pos, 1.0 + p.age * 0.2, Color(1.0, 0.42, 0.5, alpha))
			&"zzz":
				var size := int(14 + p.age * 6)
				draw_string(font, p.pos, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size,
					Color(0.45, 0.55, 0.9, alpha))
			&"thought":
				draw_circle(p.pos, 13.0, Color(1, 1, 1, alpha * 0.85))
				draw_circle(p.pos + Vector2(-12, 12), 4.0, Color(1, 1, 1, alpha * 0.7))
				draw_circle(p.pos, 6.0, Color("c98a4b", alpha))


## Shadow ellipse whose bottom touches the feet line, clipped to [lo, hi]
## (the ledge's extent in window-local x).
func _draw_shadow(lo: float, hi: float) -> void:
	var rx := 44.0
	var ry := 9.0
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


## Draws a little green parrot in place of the cat's body, tail, and face —
## same shared shadow/particles/cookie as the cat, drawn around the same
## CENTER/FOOT_Y frame so the two forms share identical footing.
func _draw_parrot(napping: bool, eating: bool, playing: bool, breathe: float,
		squash: float, airborne: bool, eyes_closed: bool, f: Vector2) -> void:
	var body_c := Color("3ba84a")
	var head_c := Color("4bc95a")
	var wing_c := Color("2a8a38")
	var beak_c := Color("f2913a")
	var tail_c := Color("d94433")
	var origin := CENTER + Vector2(0, 8)

	var flap := 0.0
	if airborne:
		flap = sin(t * 16.0)
	elif not napping:
		flap = sin(t * 3.0) * 0.05  # gentle resting ruffle

	# Tail
	var tail_speed := 9.0 if (airborne or playing) else (2.0 if napping else 4.0)
	var wag := sin(t * tail_speed) * (0.05 if napping else 0.15)
	draw_set_transform(origin, wag, Vector2(facing, 1.0))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-14, -6), Vector2(-44, 4), Vector2(-40, 14), Vector2(-12, 10)
	]), tail_c)

	# Body
	draw_set_transform(origin, 0.0, Vector2(1.0 + breathe + squash, 1.0 - breathe - squash))
	draw_circle(Vector2.ZERO, 34.0, body_c)

	# Wing (single side-view wing; flaps briskly while flying)
	var wing_pivot := Vector2(-4, -8)
	draw_set_transform(origin + wing_pivot * Vector2(facing, 1.0), flap * facing,
		Vector2(facing, 1.0))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(-11, 32), Vector2(7, 36), Vector2(15, 4)
	]), wing_c)

	# Head
	draw_set_transform(origin, 0.0, Vector2.ONE)
	var head_offset := Vector2(facing * 20.0, -28.0) + f * 0.4
	draw_circle(head_offset, 19.0, head_c)
	draw_circle(head_offset + Vector2(-facing * 5.0, 5.0), 5.0, Color("f2e7a0"))  # cheek patch

	# Eyes
	var eye_pos := head_offset + Vector2(facing * 6.0, -4.0)
	if eyes_closed:
		draw_line(eye_pos + Vector2(-4, 0), eye_pos + Vector2(4, 0), DARK, 2.2, true)
	else:
		var pupil := 6.0 if (airborne or playing) else 5.0
		draw_circle(eye_pos, pupil, Color.WHITE)
		draw_circle(eye_pos + Vector2(facing * 1.5, -1.0), pupil * 0.45, DARK)
		if playing:
			draw_circle(eye_pos + Vector2(-facing * 1.0, 1.0), 1.1, Color.WHITE)  # sparkle

	# Beak, with a little dark chomp mark while eating
	var beak_root := head_offset + Vector2(facing * 16.0, 3.0)
	draw_colored_polygon(PackedVector2Array([
		beak_root + Vector2(0, -7), beak_root + Vector2(facing * 13.0, -1.0), beak_root + Vector2(0, 5)
	]), beak_c)
	if eating:
		var chomp: float = 2.0 + 2.0 * absf(sin(t * 12.0))
		draw_circle(beak_root + Vector2(facing * 6.0, -1.0), chomp, DARK)


func _draw_heart(pos: Vector2, s: float, color: Color) -> void:
	draw_set_transform(pos, 0.0, Vector2(s, s))
	draw_circle(Vector2(-3.2, -2.0), 4.0, color)
	draw_circle(Vector2(3.2, -2.0), 4.0, color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6.8, 0.0), Vector2(6.8, 0.0), Vector2(0.0, 8.5)
	]), color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
