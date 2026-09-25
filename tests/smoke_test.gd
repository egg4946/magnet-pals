extends Node
## 自動スモークテスト。キー入力を擬似的に送り、磁力おもちゃの基本挙動を数値で確認する。
## 実行: godot --headless --path . res://tests/smoke_test.tscn

const MainScene = preload("res://scenes/main.tscn")
const PlayerInput = preload("res://scripts/player_input.gd")
const ShapeLib = preload("res://scripts/shape_lib.gd")

var main: Node
var p1: RigidBody2D
var p2: RigidBody2D
var failures := 0


func _ready() -> void:
	Tuning.reset()  # 保存済みの調整値ではなく初期値で測る
	main = MainScene.instantiate()
	main.persist_drawings = false
	add_child(main)
	p1 = main.players[0]
	p2 = main.players[1]
	(main.inputs[1] as PlayerInput).device = PlayerInput.Device.ARROWS
	await _run()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "NG", failures])
	get_tree().quit(failures)


func _run() -> void:
	await _frames(120)
	print("settle: p1=%s anchored=%s  p2=%s anchored=%s" % [p1.global_position.round(), p1.anchored, p2.global_position.round(), p2.anchored])
	_check(p1.anchored and p2.anchored, "2人とも着地している")
	_check(not main.magnet.in_range, "開始時は作用範囲外")

	# 1P 右へ移動
	var x0 := p1.global_position.x
	_key(KEY_D, true)
	await _frames(60)
	_key(KEY_D, false)
	print("walk: p1 x %.0f -> %.0f" % [x0, p1.global_position.x])
	_check(p1.global_position.x > x0 + 30, "1P が右へ進む")

	# 通常ジャンプの高さ（2P、1Pから離れた位置で）
	main.restart()
	await _frames(120)
	var apex := await _jump_apex(p2, KEY_UP)
	print("normal jump apex (2P, 範囲外): %.0f px" % apex)
	_check(apex > 60 and apex < 250, "通常ジャンプの高さが妥当")

	# くっつき反転：2Pが1Pに近づき、引力のまま待ってから1Pが反発に切り替える
	main.restart()
	await _frames(120)
	_key(KEY_LEFT, true)
	await _frames(90)
	_key(KEY_LEFT, false)
	await _frames(120)
	print("approach: dist=%.1f relation=%d in_range=%s" % [p1.global_position.distance_to(p2.global_position), main.magnet.relation, main.magnet.in_range])
	_check(main.magnet.in_range, "近づくと作用範囲に入る")
	var v_before := p2.linear_velocity.length()
	_key(KEY_S, true)
	await _frames(3)
	_key(KEY_S, false)
	var v_after := p2.linear_velocity.length()
	print("burst: relation=%d p2 speed %.0f -> %.0f" % [main.magnet.relation, v_before, v_after])
	_check(main.magnet.relation == 1, "トグルで反発になる")
	# 2人とも地上なので、踏ん張りで burst_speed × anchor_factor 程度になる
	_check(v_after > 100.0, "くっつき反転が発動する")

	# 奈落を越えられるか（形の影響を除くため2人とも四角で測る）
	p1.set_shape("四角")
	p2.set_shape("四角")
	var edge: float = main.stage["pit"].x - 28.0
	var solo := await _pit_jump(Vector2(140, 576), Vector2(edge, 576), 1, 1, p2, KEY_RIGHT, KEY_UP, false)
	print("pit: 通常ジャンプのみ -> %s" % solo)
	_check(solo != "crossed", "通常ジャンプだけでは奈落を越えられない")
	var send := await _pit_jump(Vector2(edge - 52.0, 576), Vector2(edge, 576), 1, 1, p2, KEY_RIGHT, KEY_UP, false)
	print("pit: 送り出し（1Pのすぐ右で反発）-> %s" % send)
	_check(send == "crossed", "送り出しで奈落を越えられる")
	var catch := await _pit_jump(Vector2(edge, 576), Vector2(main.stage["pit"].y + 30.0, 576), 1, -1, p1, KEY_D, KEY_W, true)
	print("pit: 迎え入れ（向こう岸の2Pが引力）-> %s" % catch)
	_check(catch == "crossed", "迎え入れで奈落を越えられる")
	p1.set_shape(main.START_SHAPES[0])
	p2.set_shape(main.START_SHAPES[1])

	# 全形状が生成・物理で動くか
	for shape_name in ShapeLib.NAMES:
		main.restart()
		p1.set_shape(shape_name)
		p2.set_shape(shape_name)
		await _frames(90)
		var ok: bool = p1.global_position.y < float(main.stage["death_y"]) and p1.polygon.size() >= 3
		print("shape %s: verts=%d area=%.0f p1.y=%.0f" % [shape_name, p1.polygon.size(), absf(ShapeLib.signed_area(p1.polygon)), p1.global_position.y])
		_check(ok, "形 %s が生成され床に立つ" % shape_name)

	# 落下でリスタート
	main.restart()
	await _frames(30)
	var retries_before: int = main.retries
	p2.reset_to(Vector2(640, 700), -1)
	await _frames(150)
	_check(main.retries == retries_before + 1, "奈落に落ちるとリスタート")

	await _test_drawing()


## お絵描き：いろいろな一筆を形に変換できるか、画面の操作で反映されるか、物理で床に立つか
func _test_drawing() -> void:
	for name in _sample_strokes():
		var stroke: PackedVector2Array = _sample_strokes()[name]
		var poly := ShapeLib.from_stroke(stroke)
		if name == "小さすぎる点":
			_check(poly.is_empty(), "お絵描き: %s は失敗として扱う" % name)
			continue
		var radius := ShapeLib.bounding_radius(poly)
		print("drawing %s: verts=%d area=%.0f radius=%.0f" % [name, poly.size(), absf(ShapeLib.signed_area(poly)), radius])
		_check(ShapeLib.is_valid(poly) and poly.size() <= ShapeLib.MAX_VERTS and radius <= ShapeLib.MAX_RADIUS + 0.01, "お絵描き: %s が形になる" % name)

	# F4 キーで開き、もう一度 F4 で閉じる
	main.load_stage(0)
	await _frames(5)
	var screen: CanvasLayer = main.draw_screen
	await _tap(KEY_F4)
	_check(screen.visible and get_tree().paused, "F4 でお絵描き画面が開く")
	await _tap(KEY_F4)
	_check(not screen.visible and not get_tree().paused, "もう一度 F4 で閉じる")

	# 画面の操作：1Pの欄に丸っこい形、2Pの欄に縦の線を描いて「完成」
	screen.open(main.drawings)
	_check(get_tree().paused, "お絵描き画面を開くとゲームが止まる")
	var blob := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		blob.append(Vector2(210, 210) + Vector2(cos(a) * 120, sin(a) * 90))
	var vertical := PackedVector2Array()
	for i in 60:
		vertical.append(Vector2(210, 40 + i * 6))
	_draw_on(screen._canvases[0], blob)
	_draw_on(screen._canvases[1], vertical)
	screen._on_done()
	_check(not get_tree().paused, "完成でゲームが再開する")
	_check(p1.shape_name == ShapeLib.DRAWN and p2.shape_name == ShapeLib.DRAWN, "描いた形が2人に反映される")

	# 縦長の形でも床にめり込まずに出現し、落ちずに立っている
	var retries_before: int = main.retries
	await _frames(180)
	print("drawn shapes: p1=%s contact=%s  p2=%s contact=%s radius2=%.0f" % [p1.global_position.round(), p1.has_contact, p2.global_position.round(), p2.has_contact, ShapeLib.bounding_radius(p2.polygon)])
	_check(main.retries == retries_before and p1.has_contact and p2.has_contact, "描いた形で床に立てる")

	p1.set_shape(main.START_SHAPES[0])
	p2.set_shape(main.START_SHAPES[1])


## 描画欄にマウス操作を送って一筆を描く
func _draw_on(canvas: Control, points: PackedVector2Array) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = points[0]
	canvas._gui_input(press)
	for i in range(1, points.size()):
		var motion := InputEventMouseMotion.new()
		motion.position = points[i]
		canvas._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = points[points.size() - 1]
	canvas._gui_input(release)


func _sample_strokes() -> Dictionary:
	var strokes := {}
	var s := PackedVector2Array()
	for i in 60:
		var a := TAU * i / 60.0
		s.append(Vector2(200, 200) + Vector2(cos(a) * 120, sin(a) * 80) * (1.0 + 0.1 * sin(a * 5)))
	strokes["閉じたでこぼこの楕円"] = s
	s = PackedVector2Array()
	for i in 80:
		var a := TAU * i / 80.0
		s.append(Vector2(200, 200) + Vector2(sin(a) * 120, sin(2 * a) * 60))
	strokes["8の字（交差あり）"] = s
	s = PackedVector2Array()
	for i in 50:
		s.append(Vector2(50 + i * 6, 200))
	strokes["まっすぐな線"] = s
	s = PackedVector2Array()
	for i in 40:
		s.append(Vector2(50 + i * 8, 200 + (40 if i % 2 == 0 else -40)))
	strokes["ギザギザの線"] = s
	s = PackedVector2Array()
	for i in 200:
		var a := i * 0.15
		s.append(Vector2(200, 200) + Vector2(cos(a), sin(a)) * (10 + i * 0.8))
	strokes["渦巻き"] = s
	s = PackedVector2Array()
	for i in 100:
		s.append(Vector2(100 + (i % 10) * 20, 100 + (i / 10) * 20 + (i % 2) * 5))
	strokes["ぐちゃぐちゃ"] = s
	s = PackedVector2Array()
	for i in 6:
		s.append(Vector2(200 + i, 200 + (i % 2)))
	strokes["小さすぎる点"] = s
	return strokes


## 2人を配置し、jumper が右へ走りながらジャンプして奈落を越えられるか。
## 戻り値: "crossed"（右岸に着地）/ "fell"（落下してリスタート）/ "short"（どちらでもない）
func _pit_jump(pos1: Vector2, pos2: Vector2, pole1: int, pole2: int, jumper: RigidBody2D, right_key: Key, jump_key: Key, run_up: bool) -> String:
	p1.reset_to(pos1, pole1)
	p2.reset_to(pos2, pole2)
	main.magnet.reset()
	await _frames(60)
	var retries_before: int = main.retries
	_key(right_key, true)
	if run_up:
		await _frames(10)
	_key(jump_key, true)
	var result := "short"
	for i in 480:  # 迎え入れは壁を引き上げられる時間も含めて最大4秒
		await get_tree().physics_frame
		if main.retries != retries_before:
			result = "fell"
			break
		if jumper.global_position.x > main.stage["pit"].y + 10.0 and jumper.global_position.y < 600.0 and jumper.has_contact:
			result = "crossed"
			break
	_key(jump_key, false)
	_key(right_key, false)
	main.restart()
	await _frames(10)
	return result


func _jump_apex(p: RigidBody2D, jump_key: Key) -> float:
	var start_y := p.global_position.y
	var min_y := start_y
	_key(jump_key, true)
	for i in 120:
		await get_tree().physics_frame
		min_y = minf(min_y, p.global_position.y)
	_key(jump_key, false)
	await _frames(60)
	return start_y - min_y


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


## キーを押して離す
func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if cond else "NG", label])
	if not cond:
		failures += 1
