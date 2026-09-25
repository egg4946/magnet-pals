extends CanvasLayer
## F4 で開くお絵描き画面。1P・2P がそれぞれ一筆書きで自分の磁石の形を描く。
## 開いている間はゲームを一時停止する（この画面だけは停止中も動く）。

signal finished(polygons: Array)   ## [1Pの形, 2Pの形]。描かなかった方は空
signal cancelled

const DrawCanvas = preload("res://scripts/draw_canvas.gd")

var _canvases: Array = []


func build(font: Font, titles: Array[String], fills: Array[Color], outlines: Array[Color]) -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	add_child(root)

	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.06, 0.93)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 20
	box.offset_bottom = -20
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)

	var heading := Label.new()
	heading.text = "お絵描き：自分の磁石の形を一筆書きで描こう"
	heading.add_theme_font_size_override("font_size", 24)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)

	var help := Label.new()
	help.text = "書き始めの近くで描き終えると閉じた形、離れた所で終えると太い線の形になります。描き直すと上書き。\nどんな形も同じ面積にそろえます（大きすぎる形は縮みます）。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(help)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	box.add_child(row)
	for i in 2:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		row.add_child(column)
		var canvas := DrawCanvas.new()
		canvas.title = titles[i]
		canvas.fill_color = fills[i]
		canvas.outline_color = outlines[i]
		canvas.font = font
		column.add_child(canvas)
		_canvases.append(canvas)
		var clear_button := _button("消す", canvas.clear)
		clear_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(clear_button)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	box.add_child(buttons)
	buttons.add_child(_button("完成（Enter）", _on_done))
	buttons.add_child(_button("やめる（Esc）", _on_cancel))


## 今の形を表示して開く。current は [1Pの形, 2Pの形]（未描画なら空）
func open(current: Array) -> void:
	for i in 2:
		(_canvases[i] as DrawCanvas).show_existing(current[i])
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_on_done()
		KEY_ESCAPE, KEY_F4:
			_on_cancel()
	get_viewport().set_input_as_handled()


func _on_done() -> void:
	var polygons: Array = []
	for canvas in _canvases:
		polygons.append((canvas as DrawCanvas).result)
	close()
	finished.emit(polygons)


func _on_cancel() -> void:
	close()
	cancelled.emit()


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(160, 40)
	button.pressed.connect(callback)
	return button
