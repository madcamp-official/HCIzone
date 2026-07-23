# main.gd — 메인 스크립트
# 역할: 투명 전체화면 창 설정, 앵무새 생성, 파리 생성, 키보드 입력 처리
#
# [조작키]
#   F : 파리 3마리 풀기
#   D : "앉아있던 창이 닫힘" 시뮬레이션 (앵무새 낙하)
#   S : 잠자기 토글
#   Q 또는 ESC : 종료

extends Node2D

# true로 바꾸면 앵무새 주변 외에는 마우스 클릭이 바탕화면으로 통과됨.
# 단, 창 포커스가 풀리면 키보드(F/D/S)가 안 먹을 수 있으므로 테스트 중에는 false 권장.
const ENABLE_CLICK_THROUGH := true

var parrot: Parrot
var help_label: Label


func _ready() -> void:
	_setup_window()

	# 앵무새 생성
	parrot = Parrot.new()
	add_child(parrot)
	var vp := get_viewport_rect().size
	parrot.position = Vector2(vp.x * 0.5, vp.y * 0.4)

	# 좌측 상단 도움말 표시
	help_label = Label.new()
	help_label.text = "F: 파리 풀기 | D: 창 닫힘(낙하) | S: 잠자기 | Q/ESC: 종료"
	help_label.position = Vector2(16, 12)
	help_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	help_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help_label.add_theme_constant_override("outline_size", 6)
	add_child(help_label)
	print("화면 물리 해상도: ", DisplayServer.screen_get_size())
	print("앵무새가 인식하는 좌표 공간: ", get_viewport_rect().size)
	print("실제 창 크기: ", DisplayServer.window_get_size())


func _setup_window() -> void:
	# 배경을 투명하게 (프로젝트 설정에서도 transparent 관련 2개를 켜야 함 — 안내문 참고)
	get_tree().root.transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

	# 작업표시줄을 제외한 화면 영역에 창을 꽉 채움
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(usable.position)



func _process(_delta: float) -> void:
	if ENABLE_CLICK_THROUGH and is_instance_valid(parrot):
		# 앵무새 주변 사각형만 클릭을 받고, 나머지는 바탕화면으로 통과
		var p := parrot.position
		var box := PackedVector2Array([
			p + Vector2(-60, -60), p + Vector2(60, -60),
			p + Vector2(60, 60), p + Vector2(-60, 60),
		])
		DisplayServer.window_set_mouse_passthrough(box)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_spawn_flies(3)
			KEY_D:
				parrot.knock_off()
			KEY_S:
				parrot.toggle_sleep()
			KEY_Q, KEY_ESCAPE:
				get_tree().quit()


func _spawn_flies(count: int) -> void:
	var vp := get_viewport_rect().size
	for i in count:
		var fly := Fly.new()
		add_child(fly)
		# 화면 위쪽 절반의 랜덤 위치에 등장
		fly.position = Vector2(
			randf_range(vp.x * 0.1, vp.x * 0.9),
			randf_range(vp.y * 0.1, vp.y * 0.5)
		)
