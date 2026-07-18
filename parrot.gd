# parrot.gd — 앵무새 캐릭터
# 상태: 날기 / 걷기 / 천장 앉기 / 잠자기 / 파리 추격 / 낙하 / 멍때리기(깃털 고르기)
# 그림 파일 없이 _draw()로 직접 그림.

class_name Parrot
extends Node2D

enum State { FLYING, WALKING, PERCHED, SLEEPING, CHASING, FALLING, IDLE }

var state: int = State.FLYING

# 이동 관련
var velocity := Vector2.ZERO
var target := Vector2.ZERO
const FLY_SPEED := 220.0
const CHASE_SPEED := 340.0
const WALK_SPEED := 60.0
const GRAVITY := 900.0

# 화면 경계 (main에서 창 크기가 정해진 뒤 _ready에서 계산)
var floor_y := 0.0
var ceil_y := 26.0

# 애니메이션 관련
var flap_phase := 0.0        # 날개 퍼덕임 위상
var wing_angle := 0.0
var facing := 1.0            # 1 = 오른쪽, -1 = 왼쪽
var bob_time := 0.0          # 비행 중 위아래 흔들림
var eat_effect_timer := 0.0  # 파리 먹은 뒤 하트 표시 시간
var gulp_scale := 1.0        # 꿀꺽 할 때 몸 통통 튀는 효과
var head_tilt := 0.0         # 두리번거림
var preen_timer := 0.0       # 깃털 고르기 동작 시간

# 상태 지속 타이머
var state_timer := 0.0
var walk_dir := 1.0
var fall_time := 0.0


func _ready() -> void:
	floor_y = get_viewport_rect().size.y - 28.0
	_pick_fly_target()


func _process(delta: float) -> void:
	state_timer -= delta
	bob_time += delta
	if eat_effect_timer > 0.0:
		eat_effect_timer -= delta
	gulp_scale = lerpf(gulp_scale, 1.0, delta * 6.0)

	# 파리가 존재하고, 자는 중이 아니면 추격 시작 (자다가도 파리 소리에 깸)
	var flies := get_tree().get_nodes_in_group("flies")
	if flies.size() > 0 and state != State.FALLING:
		if state != State.CHASING:
			state = State.CHASING

	match state:
		State.FLYING:
			_do_fly(delta, FLY_SPEED)
			if position.distance_to(target) < 24.0:
				_arrived()
		State.CHASING:
			_do_chase(delta, flies)
		State.WALKING:
			_do_walk(delta)
		State.PERCHED:
			_do_perch(delta)
		State.IDLE:
			_do_idle(delta)
		State.SLEEPING:
			_do_sleep(delta)
		State.FALLING:
			_do_fall(delta)

	# 날개 퍼덕임 속도: 상태별로 다르게
	var flap_speed := 0.0
	match state:
		State.FLYING: flap_speed = 14.0
		State.CHASING: flap_speed = 22.0
		State.FALLING: flap_speed = 4.0
		_: flap_speed = 0.0
	if flap_speed > 0.0:
		flap_phase += delta * flap_speed
		wing_angle = sin(flap_phase) * 0.9
	else:
		wing_angle = lerpf(wing_angle, 0.15, delta * 8.0)  # 접은 날개

	# 화면 밖으로 못 나가게
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, 30.0, vp.x - 30.0)
	position.y = clampf(position.y, ceil_y, floor_y)

	queue_redraw()


# ------------------------------------------------------------------ 행동들

func _do_fly(delta: float, speed: float) -> void:
	var dir := (target - position).normalized()
	velocity = dir * speed
	position += velocity * delta
	position.y += sin(bob_time * 6.0) * 0.6  # 살랑살랑 위아래 흔들림
	_update_facing()


func _do_chase(delta: float, flies: Array) -> void:
	if flies.is_empty():
		state = State.FLYING
		_pick_fly_target()
		return
	# 가장 가까운 파리 추격
	var nearest: Node2D = flies[0]
	var best := position.distance_to(nearest.position)
	for f in flies:
		var d := position.distance_to(f.position)
		if d < best:
			best = d
			nearest = f
	target = nearest.position
	_do_fly(delta, CHASE_SPEED)
	if best < 22.0:
		nearest.queue_free()          # 냠!
		eat_effect_timer = 0.9        # 하트 표시
		gulp_scale = 1.35             # 꿀꺽 통통 효과


func _do_walk(delta: float) -> void:
	position.y = floor_y
	position.x += walk_dir * WALK_SPEED * delta
	facing = walk_dir
	# 가끔 방향 전환
	if randf() < delta * 0.4:
		walk_dir *= -1.0
	if state_timer <= 0.0:
		_choose_next_after_ground()


func _do_perch(delta: float) -> void:
	position.y = ceil_y
	head_tilt = sin(bob_time * 2.0) * 0.25  # 고개 갸웃갸웃
	if state_timer <= 0.0:
		state = State.FLYING
		_pick_fly_target()


func _do_idle(delta: float) -> void:
	# 깃털 고르기: 고개를 몸쪽으로 숙였다 들었다
	preen_timer += delta
	head_tilt = sin(preen_timer * 5.0) * 0.5 + 0.3
	if state_timer <= 0.0:
		head_tilt = 0.0
		_choose_next_after_ground()


func _do_sleep(_delta: float) -> void:
	head_tilt = 0.5  # 고개 푹 숙임
	# 잠은 toggle_sleep() 또는 파리 등장으로만 깸


func _do_fall(delta: float) -> void:
	fall_time += delta
	velocity.y += GRAVITY * delta
	position += velocity * delta
	rotation = sin(fall_time * 10.0) * 0.2  # 허둥지둥 흔들림
	# 0.7초 떨어지거나 바닥 근처에 오면 정신 차리고 날아오름
	if fall_time > 0.7 or position.y > floor_y - 60.0:
		rotation = 0.0
		state = State.FLYING
		_pick_fly_target()


# ------------------------------------------------------------------ 상태 전환

func _arrived() -> void:
	var r := randf()
	if r < 0.5:
		_pick_fly_target()                    # 계속 날기
	elif r < 0.8:
		state = State.WALKING                 # 바닥에 착지해서 걷기
		position.y = floor_y
		state_timer = randf_range(4.0, 8.0)
		walk_dir = 1.0 if randf() < 0.5 else -1.0
	else:
		state = State.PERCHED                 # 천장(화면 상단)에 앉기
		position.y = ceil_y
		state_timer = randf_range(3.0, 6.0)


func _choose_next_after_ground() -> void:
	var r := randf()
	if r < 0.4:
		state = State.FLYING
		_pick_fly_target()
	elif r < 0.7:
		state = State.IDLE                    # 깃털 고르기
		preen_timer = 0.0
		state_timer = randf_range(2.0, 4.0)
	else:
		state = State.WALKING
		state_timer = randf_range(3.0, 6.0)


func _pick_fly_target() -> void:
	var vp := get_viewport_rect().size
	target = Vector2(
		randf_range(vp.x * 0.1, vp.x * 0.9),
		randf_range(vp.y * 0.15, vp.y * 0.75)
	)


func _update_facing() -> void:
	if absf(velocity.x) > 10.0:
		facing = 1.0 if velocity.x > 0.0 else -1.0


# ------------------------------------------------------------------ 외부에서 호출

func knock_off() -> void:
	# "앉아있던 창이 닫힘" 시뮬레이션
	state = State.FALLING
	fall_time = 0.0
	velocity = Vector2(randf_range(-40.0, 40.0), 60.0)


func toggle_sleep() -> void:
	if state == State.SLEEPING:
		state = State.FLYING
		head_tilt = 0.0
		_pick_fly_target()
	else:
		state = State.SLEEPING
		position.y = floor_y  # 바닥에서 잠


# ------------------------------------------------------------------ 그리기

func _draw() -> void:
	# 몸 전체는 facing 방향으로 좌우 반전해서 그림
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing * gulp_scale, gulp_scale))

	var body_green := Color(0.22, 0.65, 0.28)
	var head_green := Color(0.30, 0.78, 0.35)
	var wing_green := Color(0.16, 0.52, 0.22)
	var beak_orange := Color(0.95, 0.55, 0.15)
	var tail_red := Color(0.85, 0.25, 0.2)

	# 꼬리 (뒤쪽으로 뾰족)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, -4), Vector2(-38, 6), Vector2(-34, 14), Vector2(-14, 8)
	]), tail_red)

	# 몸통
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing * gulp_scale, gulp_scale * 0.92))
	draw_circle(Vector2(0, 0), 20.0, body_green)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing * gulp_scale, gulp_scale))

	# 다리 (걷기/앉기/잠잘 때만)
	if state in [State.WALKING, State.IDLE, State.SLEEPING]:
		var leg_swing := sin(bob_time * 10.0) * 3.0 if state == State.WALKING else 0.0
		draw_line(Vector2(-5, 16), Vector2(-5 + leg_swing, 26), beak_orange, 2.5)
		draw_line(Vector2(5, 16), Vector2(5 - leg_swing, 26), beak_orange, 2.5)
	elif state == State.PERCHED:
		# 천장에 매달린 발
		draw_line(Vector2(-5, -16), Vector2(-5, -24), beak_orange, 2.5)
		draw_line(Vector2(5, -16), Vector2(5, -24), beak_orange, 2.5)

	# 날개 (어깨를 축으로 회전)
	var wing_pivot := Vector2(-2, -4)
	draw_set_transform(wing_pivot * Vector2(facing, 1.0), wing_angle * facing,
			Vector2(facing * gulp_scale, gulp_scale))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(-6, 22), Vector2(4, 24), Vector2(9, 4)
	]), wing_green)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing * gulp_scale, gulp_scale))

	# 머리 (head_tilt만큼 앞으로 기울임)
	var head_offset := Vector2(13, -17).rotated(head_tilt * 0.5)
	draw_circle(head_offset, 13.0, head_green)

	# 눈
	var eye_pos := head_offset + Vector2(5, -3)
	if state == State.SLEEPING:
		draw_line(eye_pos + Vector2(-3, 0), eye_pos + Vector2(3, 0), Color.BLACK, 2.0)
	else:
		draw_circle(eye_pos, 4.0, Color.WHITE)
		draw_circle(eye_pos + Vector2(1, 0), 2.2, Color.BLACK)

	# 부리
	var beak_root := head_offset + Vector2(11, 0)
	draw_colored_polygon(PackedVector2Array([
		beak_root + Vector2(0, -5), beak_root + Vector2(10, 1), beak_root + Vector2(0, 4)
	]), beak_orange)

	# ---- 여기부터는 반전 없이 그림 (글자/이펙트) ----
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 잠잘 때 Zzz
	if state == State.SLEEPING:
		var f := ThemeDB.fallback_font
		var zoff := sin(bob_time * 2.0) * 3.0
		draw_string(f, Vector2(18, -34 + zoff), "Z z z",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.5, 1.0, 0.9))

	# 파리 먹은 직후 하트
	if eat_effect_timer > 0.0:
		var t := 0.9 - eat_effect_timer  # 시간이 지날수록 위로 떠오름
		var hp := Vector2(0, -44.0 - t * 30.0)
		var a := clampf(eat_effect_timer / 0.9, 0.0, 1.0)
		var heart := Color(1.0, 0.3, 0.45, a)
		draw_circle(hp + Vector2(-4, 0), 5.0, heart)
		draw_circle(hp + Vector2(4, 0), 5.0, heart)
		draw_colored_polygon(PackedVector2Array([
			hp + Vector2(-8.5, 2), hp + Vector2(8.5, 2), hp + Vector2(0, 13)
		]), heart)
