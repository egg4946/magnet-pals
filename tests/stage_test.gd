extends Node
## ステージの攻略手順が成立するかを1ステップずつ確かめる自動テスト。
## 各ステップは「2人をその場面の位置に置き、技を1回だけ実行する」形で再現する。
## 実行: godot --headless --fixed-fps 120 --path . res://tests/stage_test.tscn（--fixed-fps で実時間より速く回る）
##
## 1P = WASD（発射台・引き上げる側）、2P = 矢印（飛ぶ側）。
## 技の種類:
##   normal   … 1Pは作用範囲の外。2Pが自力でジャンプするだけ（成立しないことを確かめる）
##   send     … 送り出し。2人とも同じ極で並び、2Pが方向キー＋ジャンプ。
##              1Pの位置は使わず、2Pの左に SEND_GAPS の間隔で置いて順に試す（間隔＝力加減）
##   shoulder … 肩車発射。2Pを1Pの上に乗せて引力で待ち、1Pが反発へ切り替え（2Pは方向キー）
##   pull     … つり上げ／迎え入れ。1Pが目的地にいて引力、2Pが方向キー＋ジャンプ

const MainScene = preload("res://scenes/main.tscn")
const PlayerInput = preload("res://scripts/player_input.gd")
const Stages = preload("res://scripts/stages.gd")

## [ステージ番号, 説明, 技, 1Pの位置, 2Pの位置, 2Pの方向キー, 目的地（この枠に2Pが接地すれば成功）, 期待]
const STEPS = [
	[0, "奈落: 自力ジャンプ", "normal", Vector2(90, 576), Vector2(432, 576), KEY_RIGHT, Rect2(770, 520, 510, 60), false],
	[0, "奈落: 送り出し", "send", Vector2.ZERO, Vector2(432, 576), KEY_RIGHT, Rect2(770, 520, 510, 60), true],
	[0, "奈落: 迎え入れ", "pull", Vector2(800, 576), Vector2(432, 576), KEY_RIGHT, Rect2(770, 520, 510, 60), true],
	[0, "高台: 肩車発射", "shoulder", Vector2(1000, 576), Vector2(1000, 526), KEY_RIGHT, Rect2(1060, 270, 220, 60), true],
	[0, "高台: つり上げ", "pull", Vector2(1090, 306), Vector2(1020, 576), KEY_RIGHT, Rect2(1060, 270, 220, 60), true],

	[1, "崖: 自力ジャンプ", "normal", Vector2(100, 576), Vector2(660, 576), KEY_RIGHT, Rect2(700, 270, 580, 60), false],
	[1, "崖: 送り出し", "send", Vector2.ZERO, Vector2(652, 576), KEY_RIGHT, Rect2(700, 270, 580, 60), true],
	[1, "崖: 肩車発射（天井の下）", "shoulder", Vector2(620, 576), Vector2(620, 526), KEY_RIGHT, Rect2(700, 270, 580, 60), true],
	[1, "崖: つり上げ", "pull", Vector2(730, 306), Vector2(670, 576), KEY_RIGHT, Rect2(700, 270, 580, 60), true],
	[1, "棚: 自力ジャンプ", "normal", Vector2(730, 306), Vector2(1030, 306), KEY_RIGHT, Rect2(1060, 60, 220, 60), false],
	[1, "棚: 送り出し", "send", Vector2.ZERO, Vector2(1032, 306), KEY_RIGHT, Rect2(1060, 60, 220, 60), null],
	[1, "棚: 肩車発射", "shoulder", Vector2(1000, 306), Vector2(1000, 256), KEY_RIGHT, Rect2(1060, 60, 220, 60), true],
	[1, "棚: つり上げ", "pull", Vector2(1090, 96), Vector2(1020, 306), KEY_RIGHT, Rect2(1060, 60, 220, 60), true],

	[2, "柱へ: 自力ジャンプ", "normal", Vector2(40, 576), Vector2(375, 576), KEY_RIGHT, Rect2(650, 460, 130, 60), false],
	[2, "柱へ: 送り出し（力加減）", "send", Vector2.ZERO, Vector2(375, 576), KEY_RIGHT, Rect2(650, 460, 130, 60), true],
	[2, "柱へ: 迎え入れ", "pull", Vector2(745, 496), Vector2(375, 576), KEY_RIGHT, Rect2(650, 460, 130, 60), true],
	[2, "岸へ: 自力ジャンプ", "normal", Vector2(40, 576), Vector2(755, 496), KEY_RIGHT, Rect2(990, 380, 290, 60), false],
	[2, "岸へ: 送り出し（全力）", "send", Vector2.ZERO, Vector2(755, 496), KEY_RIGHT, Rect2(990, 380, 290, 60), true],
	[2, "岸へ: 迎え入れ", "pull", Vector2(1020, 416), Vector2(725, 496), KEY_RIGHT, Rect2(990, 380, 290, 60), true],
]
const TRIES := 3
const TIMEOUT_FRAMES := 600
const JUMP_TAP_FRAMES := 48  # 0.4秒。小ジャンプ判定（0.3秒以内に離す）にかからない間隔
## 送り出しで試す2人の中心間の距離（近いほど強く飛ぶ）
const SEND_GAPS = [52.0, 90.0, 130.0, 150.0, 170.0, 190.0, 210.0, 230.0, 250.0]

var main: Node
var p1: RigidBody2D
var p2: RigidBody2D
var failures := 0


func _ready() -> void:
	Tuning.reset()
	# 引数で調整値を上書きできる: -- jump_normal_blend=0.8 magnet_strength=4500 only_square
	var shape_sets := [["四角", "四角"], ["四角", "丸"]]
	for arg in OS.get_cmdline_user_args():
		if arg == "only_square":
			shape_sets = [["四角", "四角"]]
		elif "=" in arg:
			var kv := arg.split("=")
			Tuning.set_value(kv[0], float(kv[1]))
			print("調整値の上書き: %s = %s" % [kv[0], kv[1]])
	main = MainScene.instantiate()
	main.persist_drawings = false
	add_child(main)
	p1 = main.players[0]
	p2 = main.players[1]
	(main.inputs[1] as PlayerInput).device = PlayerInput.Device.ARROWS
	await _frames(10)

	await _check_spawns()
	for shapes in shape_sets:
		p1.set_shape(shapes[0])
		p2.set_shape(shapes[1])
		print("\n=== 形: 1P=%s / 2P=%s ===" % shapes)
		for step in STEPS:
			await _run_step(step, shapes[1] == "四角")
	print("\nRESULT: %s (%d failures)" % ["OK" if failures == 0 else "NG", failures])
	get_tree().quit(failures)


## 各ステージの出現位置で3秒待ち、2人とも落ちずに立っているか
func _check_spawns() -> void:
	for i in Stages.STAGES.size():
		main.load_stage(i)
		await _frames(360)
		var ok: bool = main.retries == 0 and p1.has_contact and p2.has_contact
		print("出現位置 %s: 1P=%s 2P=%s %s" % [main.stage["name"], p1.global_position.round(), p2.global_position.round(), "OK" if ok else "NG"])
		if not ok:
			failures += 1


func _run_step(step: Array, strict: bool) -> void:
	# 期待が null の手順は参考（別の解き方があるので、成立しなくても不合格にしない）
	var reference_only: bool = step[7] == null
	var expected: bool = true if reference_only else step[7]
	var successes := 0
	var tries := 0
	var detail := ""
	if step[2] == "send":
		var good_gaps: Array[String] = []
		for gap in SEND_GAPS:
			var ok_count := 0
			for t in TRIES:
				tries += 1
				if await _attempt(step, gap):
					ok_count += 1
			successes += ok_count
			if ok_count > 0:
				good_gaps.append("%d" % gap)
		detail = "（成功した間隔: %s）" % (", ".join(good_gaps) if good_gaps.size() > 0 else "なし")
	else:
		for t in TRIES:
			tries += 1
			if await _attempt(step, 0.0):
				successes += 1
	# 期待どおりか：成立するはずの手順は1回以上、成立しないはずの手順は0回
	var ok := successes > 0 if expected else successes == 0
	var counts := strict and not reference_only
	var mark := "OK" if ok else ("NG" if counts else "--")
	var expect_text := "参考" if reference_only else ("成立" if expected else "不成立")
	print("  [%s] %s: %d/%d 回成功（期待: %s）%s" % [mark, step[1], successes, tries, expect_text, detail])
	# 四角どうしの結果だけを合否に使う（丸は参考値）
	if counts and not ok:
		failures += 1


func _attempt(step: Array, send_gap: float) -> bool:
	var kind: String = step[2]
	var pos1: Vector2 = step[3]
	var pos2: Vector2 = step[4]
	if kind == "send":
		pos1 = pos2 - Vector2(send_gap, 0)
	var dir_key: Key = step[5]
	var target: Rect2 = step[6]

	main.load_stage(step[0])
	await _frames(5)
	var pole2 := 1 if kind == "send" else -1
	p1.reset_to(pos1, 1)
	p2.reset_to(pos2, pole2)
	main.magnet.reset()
	await _frames(90 if kind == "shoulder" else 40)
	var retries_before: int = main.retries

	_key(dir_key, true)
	if kind == "shoulder":
		_key(KEY_S, true)
		await _frames(2)
		_key(KEY_S, false)
	else:
		_key(KEY_UP, true)

	var success := false
	for i in TIMEOUT_FRAMES:
		# 人がやるように、ジャンプは0.4秒ごとに押し直す（壁に張り付いたら壁キックで登れる）
		if kind != "shoulder" and i > 0:
			if i % JUMP_TAP_FRAMES == 0:
				_key(KEY_UP, false)
			elif i % JUMP_TAP_FRAMES == 4:
				_key(KEY_UP, true)
		await get_tree().physics_frame
		if main.retries != retries_before:
			break
		if target.has_point(p2.global_position) and p2.has_contact:
			success = true
			break
	_key(dir_key, false)
	_key(KEY_UP, false)
	return success


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
