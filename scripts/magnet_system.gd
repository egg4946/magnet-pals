extends Node2D
## 2人の間の磁力を計算して各プレイヤーの magnet_force に書き込む。
## 作用範囲・磁力線・頭上ラベル・画面外インジケータの描画も担当する。
## ルールの説明は docs/prototype-spec.md の「磁力ルール」を参照。

const Player = preload("res://scripts/player.gd")

const ATTRACT_COLOR := Color(0.75, 0.45, 1.0)
const REPEL_COLOR := Color(1.0, 0.8, 0.25)
const SCREEN_WIDTH := 1280.0
## 重心がこれより近いとき（凹形が相方を包んだときなど）は向きが不安定なので力を止める
const MIN_DISTANCE := 4.0
## この距離まで近づいていれば「くっついている」とみなす。
## 地上どうしは摩擦で数px手前に止まり、物理的には接触しないことがあるため。
const TOUCH_MARGIN := 6.0

var a: Player
var b: Player
var font: Font

var relation := 0          ## +1 = 反発, -1 = 引力
var in_range := false
var strength01 := 0.0      ## 今の磁力の強さ（0〜1）
var _ramp := 1.0
var _burst_cooldown := 0.0


func setup(p1: Player, p2: Player, ui_font: Font) -> void:
	a = p1
	b = p2
	font = ui_font
	reset()


func reset() -> void:
	relation = a.pole * b.pole
	_ramp = 1.0
	_burst_cooldown = 0.0
	strength01 = 0.0
	in_range = false


func step(delta: float) -> void:
	var new_relation := a.pole * b.pole
	if new_relation != relation:
		# くっつき反転：接触中に引力→反発へ切り替わった瞬間に弾ける
		if new_relation > 0 and _burst_cooldown <= 0.0 and _are_touching():
			_burst()
		relation = new_relation
		_ramp = 0.0
	var ramp_time := Tuning.val("ramp_time")
	_ramp = 1.0 if ramp_time <= 0.0 else minf(_ramp + delta / ramp_time, 1.0)
	_burst_cooldown -= delta

	var offset := b.global_position - a.global_position
	var dist := offset.length()
	var reach := Tuning.val("magnet_range")
	in_range = dist < reach
	if not in_range or dist < MIN_DISTANCE:
		a.magnet_force = Vector2.ZERO
		b.magnet_force = Vector2.ZERO
		strength01 = 0.0
		return

	var falloff := pow(1.0 - dist / reach, Tuning.val("falloff_power"))
	strength01 = falloff * _ramp
	var dir := offset / dist
	var force_on_b := dir * Tuning.val("magnet_strength") * strength01 * float(relation)
	a.magnet_force = -force_on_b * _anchor(a)
	b.magnet_force = force_on_b * _anchor(b)


func _anchor(p: Player) -> float:
	return Tuning.val("anchor_factor") if p.anchored else 1.0


func _are_touching() -> bool:
	if a.touching_partner or b.touching_partner:
		return true
	return _nudge_hits(a, b) or _nudge_hits(b, a)


## from を相手の方向へ TOUCH_MARGIN だけ動かしたら相手にぶつかるか
func _nudge_hits(from: Player, to: Player) -> bool:
	var dir := (to.global_position - from.global_position).normalized()
	var hit := KinematicCollision2D.new()
	if from.test_move(from.global_transform, dir * TOUCH_MARGIN, hit):
		return hit.get_collider() == to
	return false


func _burst() -> void:
	var offset := b.global_position - a.global_position
	var dir := offset.normalized() if offset.length() > 0.01 else Vector2.UP
	var speed := Tuning.val("burst_speed")
	var spin := Tuning.val("burst_spin")
	a.add_velocity(-dir * speed * _anchor(a), randf_range(-spin, spin))
	b.add_velocity(dir * speed * _anchor(b), randf_range(-spin, spin))
	_burst_cooldown = Tuning.val("burst_cooldown")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if a == null or b == null:
		return
	var reach := Tuning.val("magnet_range")
	_draw_range(a, reach)
	_draw_range(b, reach)

	if in_range and strength01 > 0.0:
		var col := REPEL_COLOR if relation > 0 else ATTRACT_COLOR
		col.a = 0.35 + 0.6 * strength01
		draw_line(a.global_position, b.global_position, col, 2.0 + 10.0 * strength01, true)
		var mid := (a.global_position + b.global_position) * 0.5
		var word := "反発" if relation > 0 else "引力"
		draw_string(font, mid + Vector2(-30, -14), word, HORIZONTAL_ALIGNMENT_CENTER, 60, 16, col)

	_draw_label(a)
	_draw_label(b)


func _draw_range(p: Player, reach: float) -> void:
	draw_arc(p.global_position, reach, 0.0, TAU, 64, Color(p.pole_color(), 0.22), 2.0, true)


func _draw_label(p: Player) -> void:
	var pos := p.global_position
	var text := "%dP %s" % [p.index + 1, "N" if p.pole == Player.POLE_N else "S"]
	if pos.y < 0.0:
		# 画面より上に飛び出したら、上端に矢印と高さを出す
		var x := clampf(pos.x, 20.0, SCREEN_WIDTH - 20.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, 6), Vector2(x - 10, 24), Vector2(x + 10, 24)]), p.pole_color())
		draw_string(font, Vector2(x - 60, 44), "%s ↑%d" % [text, int(-pos.y)], HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color.WHITE)
	else:
		draw_string(font, pos + Vector2(-40, -46), text, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color.WHITE)
