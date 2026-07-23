# fly.gd — 먹이(파리)
# 화면 안을 지그재그로 정신없이 날아다님. 앵무새에게 잡히면 사라짐.

class_name Fly
extends Node2D

var velocity := Vector2.ZERO
var jitter_timer := 0.0
var wing_phase := 0.0


func _ready() -> void:
	add_to_group("flies")
	_new_direction()


func _process(delta: float) -> void:
	wing_phase += delta * 40.0
	jitter_timer -= delta
	if jitter_timer <= 0.0:
		_new_direction()

	position += velocity * delta

	# 화면 밖으로 나가지 않게 튕기기
	var vp := get_viewport_rect().size
	if position.x < 20.0 or position.x > vp.x - 20.0:
		velocity.x *= -1.0
		position.x = clampf(position.x, 20.0, vp.x - 20.0)
	if position.y < 20.0 or position.y > vp.y - 60.0:
		velocity.y *= -1.0
		position.y = clampf(position.y, 20.0, vp.y - 60.0)

	queue_redraw()


func _new_direction() -> void:
	# 0.2~0.6초마다 방향을 홱홱 바꿔서 파리 특유의 정신없는 움직임 연출
	jitter_timer = randf_range(0.2, 0.6)
	var angle := randf_range(0.0, TAU)
	velocity = Vector2.from_angle(angle) * randf_range(80.0, 160.0)


func _draw() -> void:
	# 몸통
	draw_circle(Vector2.ZERO, 4.0, Color(0.15, 0.15, 0.15))
	# 날개 (퍼덕이는 반투명 타원 느낌)
	var w := absf(sin(wing_phase)) * 0.8 + 0.2
	var wing_col := Color(0.8, 0.85, 1.0, 0.6)
	draw_set_transform(Vector2(-2, -3), -0.5, Vector2(1.0, w))
	draw_circle(Vector2.ZERO, 3.5, wing_col)
	draw_set_transform(Vector2(2, -3), 0.5, Vector2(1.0, w))
	draw_circle(Vector2.ZERO, 3.5, wing_col)
