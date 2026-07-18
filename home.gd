extends Node2D
## The pet's house, drawn procedurally in its own transparent window.
## When the cat is inside (= handed off to the real robot), a pair of amber
## eyes peeks out of the dark doorway.

const WALL := Color("c96f52")
const ROOF := Color("7a4636")
const DOOR := Color("2b1a12")
const TRIM := Color("f2e2c8")

var cat_inside := false

var _t := 0.0
var _blink := 0.0
var _blink_timer := 2.0


func _process(delta: float) -> void:
	_t += delta
	if _blink > 0.0:
		_blink -= delta
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink = 0.15
			_blink_timer = randf_range(1.5, 4.0)
	queue_redraw()


func _draw() -> void:
	# Ground shadow
	draw_set_transform(Vector2(95, 158), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 78.0, Color(0, 0, 0, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Walls (floor line at y = 158)
	draw_rect(Rect2(30, 62, 130, 96), WALL)
	# Roof with a little overhang, ridge cap on top
	draw_colored_polygon(PackedVector2Array([
		Vector2(18, 70), Vector2(95, 18), Vector2(172, 70)
	]), ROOF)
	draw_circle(Vector2(95, 20), 6.0, TRIM)
	# Arched doorway
	draw_circle(Vector2(95, 122), 26.0, DOOR)
	draw_rect(Rect2(69, 122, 52, 36), DOOR)
	draw_arc(Vector2(95, 122), 26.0, PI, TAU, 20, TRIM, 3.0, true)
	# Door mat
	draw_set_transform(Vector2(95, 160), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 34.0, TRIM.darkened(0.15))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Round window, lit from inside when the cat is home
	draw_circle(Vector2(140, 90), 11.0, Color("f7d98c") if cat_inside else Color("6b3d2e"))
	draw_arc(Vector2(140, 90), 11.0, 0, TAU, 20, ROOF, 2.5, true)
	draw_line(Vector2(129, 90), Vector2(151, 90), ROOF, 2.0)
	draw_line(Vector2(140, 79), Vector2(140, 101), ROOF, 2.0)
	# Eyes peeking out of the dark
	if cat_inside:
		var sway := sin(_t * 1.3) * 3.0
		for side in [-1, 1]:
			var e := Vector2(95 + side * 10 + sway, 128)
			if _blink > 0.0:
				draw_line(e + Vector2(-4, 0), e + Vector2(4, 0), Color("f7c860"), 2.0, true)
			else:
				draw_circle(e, 4.0, Color("f7c860"))
				draw_circle(e, 2.0, DOOR)
