extends Node2D
## The pet's home: a classic red Pokéball, rendered from the leftmost column
## of "pokeball sprite.png" (a sheet of 64x64 cells stacked vertically).
## It sits on the Dock line in its own transparent window. pet.gd drives the
## capture/release animation via set_transfer(); when the pet is inside
## (= handed off to the real robot) the ball glows softly, wobbles now and
## then, and leaks little sparkles.

const SHEET_PATH := "res://pokeball sprite.png"
const CELL := 64
const BALL_SCALE := 5.0
const FLOOR_Y := 200.0    # must match pet.gd HOME_FLOOR
const CENTER_X := 160.0   # must match pet.gd HOME_DOOR_X

# Frame indices down the sheet's leftmost column (cell row * 64 px).
const F_CLOSED := 3
# Capture: ball opens (4-6), burst of light while the pet beams in (7-11),
# flash fades and the ball snaps shut (12-14, 3).
const CAPTURE_SEQ: Array[int] = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 3]
# Release: flash builds (20-21), ball opens with rays of light while the pet
# beams out (22-24), then closes again (4, 3).
const RELEASE_SEQ: Array[int] = [20, 21, 22, 23, 24, 23, 4, 3]

# Ball content in the closed frame: a 14 px ball at x/y 25..38 of the cell.
const BALL_PX := 14.0            # ball diameter in sheet pixels
const BALL_BOT_PX := 39.0        # ball's bottom edge within the cell
const BALL_R := BALL_PX * 0.5 * BALL_SCALE   # scaled ball radius
const BALL_CENTER_UP := BALL_R   # ball center height above the floor line

var cat_inside := false
var transfer_mode := ""   # "", "capture" or "release" — set by pet.gd
var transfer_p := 0.0     # 0..1 through the current transfer

var _tex: ImageTexture
var _t := 0.0
var _wobble := 0.0        # >0 while the occupied ball rocks side to side
var _wobble_timer := 4.0


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST  # crisp pixel art when scaled
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET_PATH))
	if img:
		_tex = ImageTexture.create_from_image(img)
	else:
		push_warning("pokeball sprite.png not found — the home ball will be invisible.")


func _process(delta: float) -> void:
	_t += delta
	if cat_inside and transfer_mode == "":
		if _wobble > 0.0:
			_wobble = maxf(_wobble - delta, 0.0)
		else:
			_wobble_timer -= delta
			if _wobble_timer <= 0.0:
				_wobble = 0.9
				_wobble_timer = randf_range(3.0, 7.0)
	else:
		_wobble = 0.0
	queue_redraw()


## pet.gd calls this every frame of ENTER_HOME / EXIT_HOME so the ball's
## frames stay locked to the pet's own shrink/grow timeline. mode "" ends
## the transfer and returns the ball to its closed resting pose.
func set_transfer(mode: String, p: float) -> void:
	transfer_mode = mode
	transfer_p = clampf(p, 0.0, 1.0)


func _frame_index() -> int:
	match transfer_mode:
		"capture":
			return CAPTURE_SEQ[clampi(int(transfer_p * CAPTURE_SEQ.size()), 0, CAPTURE_SEQ.size() - 1)]
		"release":
			return RELEASE_SEQ[clampi(int(transfer_p * RELEASE_SEQ.size()), 0, RELEASE_SEQ.size() - 1)]
	return F_CLOSED


func _draw() -> void:
	if _tex == null:
		return
	var ball_center := Vector2(CENTER_X, FLOOR_Y - BALL_CENTER_UP)
	# Ground shadow — chunky pixel rows, matching the characters' PMD shadows.
	for r in [[4.5, -1.5], [7.5, -0.5], [5.5, 0.5]]:  # [half-width, row] in ball px
		draw_rect(Rect2(CENTER_X - r[0] * BALL_SCALE, FLOOR_Y + (r[1] - 0.5) * BALL_SCALE,
			r[0] * 2.0 * BALL_SCALE, BALL_SCALE), Color(0, 0, 0, 0.16))
	# The ball: one cell of the sheet, bottom-anchored to the floor line,
	# rocking around its base when it wobbles. During a transfer the frame is
	# tinted past white so the burst frames' baked-in gray smoke reads as
	# bright light instead of a gray haze. (No procedural glow circles here —
	# big low-alpha discs just look like a gray background on the desktop.)
	var rot := 0.0
	if _wobble > 0.0:
		rot = sin(_wobble * 22.0) * 0.16 * _wobble
	var tint := Color(1.55, 1.4, 1.15) if transfer_mode != "" else Color.WHITE
	draw_set_transform(Vector2(CENTER_X, FLOOR_Y), rot, Vector2.ONE)
	draw_texture_rect_region(_tex,
		Rect2(-CELL * BALL_SCALE * 0.5, -BALL_BOT_PX * BALL_SCALE,
			CELL * BALL_SCALE, CELL * BALL_SCALE),
		Rect2(0, _frame_index() * CELL, CELL, CELL), tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Occupied cue: the ball's button blinks like a little red LED — crisp
	# and contained, unlike a soft glow.
	if cat_inside and transfer_mode == "":
		var pulse := 0.5 + 0.5 * sin(_t * 2.6)
		draw_circle(ball_center, 8.0, Color(1.0, 0.25, 0.2, 0.35 + 0.55 * pulse))
		draw_circle(ball_center, 4.0, Color(1.0, 0.75, 0.7, 0.5 + 0.5 * pulse))
	# Tiny drifting sparkles while occupied — signs of life inside.
	if cat_inside and transfer_mode == "":
		for i in 3:
			var ph := _t * 0.9 + i * 2.1
			var a := 0.5 + 0.5 * sin(ph * 3.7)
			if a < 0.55:
				continue
			var sp := ball_center + Vector2(
				sin(ph * 1.7 + i * 4.0) * BALL_R * 1.5,
				-cos(ph * 1.3 + i) * BALL_R * 1.4)
			_draw_sparkle(sp, 3.0 + sin(ph) * 1.2, Color(1.0, 0.95, 0.7, (a - 0.55) * 1.6))


func _draw_sparkle(p: Vector2, s: float, c: Color) -> void:
	draw_line(p + Vector2(-s, 0), p + Vector2(s, 0), c, 1.5, true)
	draw_line(p + Vector2(0, -s), p + Vector2(0, s), c, 1.5, true)
