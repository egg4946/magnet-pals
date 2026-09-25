extends Control
## お絵描き画面の描画欄（1人分）。マウスの左ボタン（タッチパッドのドラッグ）で一筆書きする。
## ボタンを離すと ShapeLib.from_stroke で形に変換し、ゲームでの見た目をプレビューする。

signal changed

const ShapeLib = preload("res://scripts/shape_lib.gd")

## 一筆で使えるインクの量（線の長さ, px）
const MAX_INK := 1400.0
## この距離以上動いたら点を追加する
const MIN_POINT_GAP := 4.0
const BG_COLOR := Color(0.09, 0.1, 0.13)
const GUIDE_COLOR := Color(1, 1, 1, 0.06)
const STROKE_COLOR := Color(1, 1, 1, 0.9)
const HINT_COLOR := Color(1, 1, 1, 0.45)

var title := ""
var fill_color := Color.WHITE
var outline_color := Color.WHITE
var font: Font
## 変換済みの形（重心が原点・面積そろえ済み）。空なら未完成
var result := PackedVector2Array()

var _stroke := PackedVector2Array()
var _ink_used := 0.0
var _drawing := false
var _message := ""


func _ready() -> void:
	custom_minimum_size = Vector2(420, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func show_existing(poly: PackedVector2Array) -> void:
	_stroke.clear()
	_ink_used = 0.0
	_drawing = false
	result = poly
	_message = "" if not poly.is_empty() else "ここに一筆書きで自分の形を描こう"
	queue_redraw()


func clear() -> void:
	show_existing(PackedVector2Array())
	changed.emit()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_stroke = PackedVector2Array([button.position])
			_ink_used = 0.0
			_drawing = true
			result = PackedVector2Array()
			_message = ""
			queue_redraw()
		elif _drawing:
			_finish_stroke()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _drawing:
		var p := motion.position.clamp(Vector2.ZERO, size)
		var d := p.distance_to(_stroke[_stroke.size() - 1])
		if d >= MIN_POINT_GAP:
			if _ink_used + d > MAX_INK:
				_finish_stroke()  # インク切れ
				return
			_stroke.append(p)
			_ink_used += d
			queue_redraw()
		accept_event()


func _finish_stroke() -> void:
	_drawing = false
	result = ShapeLib.from_stroke(_stroke)
	_message = "" if not result.is_empty() else "形にできませんでした。もう少し大きく描いてください"
	queue_redraw()
	changed.emit()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BG_COLOR)
	var center := size / 2.0
	draw_line(Vector2(center.x, 0), Vector2(center.x, size.y), GUIDE_COLOR, 1.0)
	draw_line(Vector2(0, center.y), Vector2(size.x, center.y), GUIDE_COLOR, 1.0)
	draw_rect(rect, outline_color, false, 3.0)
	if font:
		draw_string(font, Vector2(12, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, outline_color)

	if not result.is_empty() and not _drawing:
		_draw_preview(center)
	elif _stroke.size() >= 2:
		draw_polyline(_stroke, STROKE_COLOR, 4.0, true)
		# 書き始めの位置（ここに戻ると閉じた形になる）
		draw_circle(_stroke[0], 8.0, Color(outline_color, 0.5))

	if font and _message != "":
		draw_string(font, Vector2(0, center.y + 6), _message, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, HINT_COLOR)

	# インクの残量
	var ink_left := 1.0 - _ink_used / MAX_INK
	var bar := Rect2(12, size.y - 22, size.x - 24, 10)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(ink_left, 0.0, 1.0), bar.size.y)), outline_color)
	if font:
		draw_string(font, bar.position + Vector2(0, -6), "インク", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HINT_COLOR)


## ゲームでの見た目を拡大して表示し、右下に実際の大きさも出す
func _draw_preview(center: Vector2) -> void:
	var radius := ShapeLib.bounding_radius(result)
	var zoom := (minf(size.x, size.y) * 0.36) / maxf(radius, 1.0)
	draw_set_transform(center, 0.0, Vector2(zoom, zoom))
	_draw_shape(3.0 / zoom)
	draw_set_transform(size - Vector2(70, 80), 0.0, Vector2.ONE)
	_draw_shape(2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if font:
		draw_string(font, size - Vector2(140, 36), "実際の大きさ", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, HINT_COLOR)


func _draw_shape(line_width: float) -> void:
	draw_colored_polygon(result, fill_color)
	var outline := result.duplicate()
	outline.append(result[0])
	draw_polyline(outline, outline_color, line_width, true)
	for eye in [Vector2(-7, -4), Vector2(7, -4)]:
		draw_circle(eye, 5.0, Color.WHITE)
		draw_circle(eye, 2.4, Color.BLACK)
