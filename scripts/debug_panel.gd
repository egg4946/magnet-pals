extends CanvasLayer
## F1 で開く調整パネル。数値を動かすとその場で反映される。
## スライダー類はキーボードのフォーカスを取らない（WASD や矢印で値が動かないように）。

signal shape_selected(player_index: int, shape_name: String)
signal device_selected(player_index: int, device: int)
signal side_swap_toggled(on: bool)
signal restart_requested
signal stage_selected(index: int)

const PANEL_WIDTH := 420.0
const HEADER_COLOR := Color(1.0, 0.85, 0.4)

var _rows: Dictionary = {}   ## key -> [HSlider, 値のLabel, step]
var _shape_names: Array[String] = []
var _stage_option: OptionButton
var _shape_options: Array[OptionButton] = []


func build(font: Font, shape_names: Array[String], device_names: Array[String], shapes: Array, devices: Array, stage_names: Array[String]) -> void:
	layer = 10
	_shape_names = shape_names

	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.08, 0.11, 0.94)
	background.content_margin_left = 10.0
	background.content_margin_right = 10.0
	background.content_margin_top = 8.0
	background.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "PanelContainer", background)

	var panel := PanelContainer.new()
	panel.theme = theme
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_header(box, "調整パネル（F1 で閉じる）")
	var stage_row := HBoxContainer.new()
	box.add_child(stage_row)
	stage_row.add_child(_label("ステージ", 64))
	_stage_option = OptionButton.new()
	_stage_option.focus_mode = Control.FOCUS_NONE
	for n in stage_names:
		_stage_option.add_item(n)
	_stage_option.item_selected.connect(_on_stage_item_selected)
	stage_row.add_child(_stage_option)

	for i in 2:
		var row := HBoxContainer.new()
		box.add_child(row)
		row.add_child(_label("%dP" % (i + 1), 32))
		var shape_opt := OptionButton.new()
		shape_opt.focus_mode = Control.FOCUS_NONE
		for n in shape_names:
			shape_opt.add_item(n)
		shape_opt.select(shape_names.find(shapes[i]))
		shape_opt.item_selected.connect(_on_shape_item_selected.bind(i))
		row.add_child(shape_opt)
		_shape_options.append(shape_opt)
		var device_opt := OptionButton.new()
		device_opt.focus_mode = Control.FOCUS_NONE
		for n in device_names:
			device_opt.add_item(n)
		device_opt.select(devices[i])
		device_opt.item_selected.connect(_on_device_item_selected.bind(i))
		row.add_child(device_opt)

	var swap := CheckBox.new()
	swap.text = "マウスのサイドキー上下を入れ替える"
	swap.focus_mode = Control.FOCUS_NONE
	swap.toggled.connect(_on_swap_toggled)
	box.add_child(swap)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_add_button(buttons, "保存", _on_save_pressed)
	_add_button(buttons, "読込", _on_load_pressed)
	_add_button(buttons, "初期値", _on_reset_pressed)
	_add_button(buttons, "やり直し", _on_restart_pressed)

	var group := ""
	for def in Tuning.DEFS:
		if def["group"] != group:
			group = def["group"]
			_add_header(box, group)
		_add_slider(box, def)


func select_shape(player_index: int, shape_name: String) -> void:
	var index := _shape_names.find(shape_name)
	if index >= 0 and player_index < _shape_options.size():
		_shape_options[player_index].select(index)


func select_stage(index: int) -> void:
	if _stage_option:
		_stage_option.select(index)


func refresh() -> void:
	for key in _rows:
		var row: Array = _rows[key]
		var slider: HSlider = row[0]
		slider.set_value_no_signal(Tuning.val(key))
		(row[1] as Label).text = _format(slider.value, row[2])


func _add_slider(box: VBoxContainer, def: Dictionary) -> void:
	var key: String = def["key"]
	var step: float = def["step"]
	var row := HBoxContainer.new()
	box.add_child(row)

	var name_label := _label(def["label"], 150)
	name_label.tooltip_text = def.get("tip", "")
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = def["min"]
	slider.max_value = def["max"]
	slider.step = step
	slider.value = Tuning.val(key)
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(140, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_slider_changed.bind(key))
	row.add_child(slider)

	var value_label := _label(_format(slider.value, step), 64)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_rows[key] = [slider, value_label, step]


func _add_header(box: VBoxContainer, text: String) -> void:
	var header := _label(text, 0)
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	box.add_child(header)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _label(text: String, min_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = min_width
	return label


static func _format(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(roundf(value))
	return "%.2f" % value


func _on_slider_changed(value: float, key: String) -> void:
	Tuning.set_value(key, value)
	var row: Array = _rows[key]
	(row[1] as Label).text = _format(value, row[2])


func _on_shape_item_selected(item: int, player_index: int) -> void:
	shape_selected.emit(player_index, _shape_names[item])


func _on_device_item_selected(item: int, player_index: int) -> void:
	device_selected.emit(player_index, item)


func _on_stage_item_selected(item: int) -> void:
	stage_selected.emit(item)


func _on_swap_toggled(on: bool) -> void:
	side_swap_toggled.emit(on)


func _on_save_pressed() -> void:
	Tuning.save()


func _on_load_pressed() -> void:
	Tuning.load_saved()
	refresh()


func _on_reset_pressed() -> void:
	Tuning.reset()
	refresh()


func _on_restart_pressed() -> void:
	restart_requested.emit()
