extends Node2D
## 磁力おもちゃ（P0）：1画面の部屋に磁石キャラが2人。
## 部屋・プレイヤー・HUD をここで組み立てる。部屋の中身は stages.gd のデータから作る。
## F1 で調整パネル、F4 でお絵描き、R / Backspace でやり直し、F2 / F3 でステージ切り替え。

const Player = preload("res://scripts/player.gd")
const PlayerInput = preload("res://scripts/player_input.gd")
const MagnetSystem = preload("res://scripts/magnet_system.gd")
const DebugPanel = preload("res://scripts/debug_panel.gd")
const ShapeLib = preload("res://scripts/shape_lib.gd")
const Stages = preload("res://scripts/stages.gd")
const DrawScreen = preload("res://scripts/draw_screen.gd")

const DRAWINGS_PATH := "user://drawings.cfg"

const START_SHAPES = ["四角", "丸"]
const CLEAR_WAIT := 3.0
const BLOCK_COLOR := Color(0.36, 0.38, 0.45)
const WALLS = [
	Rect2(-40, -3000, 40, 3800),   # 左の壁
	Rect2(1280, -3000, 40, 3800),  # 右の壁
]
const MOUSE_NAMES = {
	MOUSE_BUTTON_LEFT: "左クリック",
	MOUSE_BUTTON_RIGHT: "右クリック",
	MOUSE_BUTTON_MIDDLE: "ホイール押し",
	MOUSE_BUTTON_XBUTTON1: "サイド下(戻る)",
	MOUSE_BUTTON_XBUTTON2: "サイド上(進む)",
}

var stage_index := 0
var stage: Dictionary = {}
var players: Array = []
var inputs: Array = []
var magnet: MagnetSystem
var panel: DebugPanel
var draw_screen: DrawScreen
## 各プレイヤーが描いた形（まだ描いていなければ空）
var drawings: Array = [PackedVector2Array(), PackedVector2Array()]
## false にすると描いた形を読み込み・保存しない（自動テストが保存済みの絵を上書きしないように）
var persist_drawings := true
var ui_font: Font
var hud_label: Label
var keys_label: Label
var center_label: Label
var held_names: Dictionary = {}
var elapsed := 0.0
var retries := 0
var clear_timer := -1.0
var _respawn_grace := 0.0
var _level_root: Node2D
var _terrain_material := PhysicsMaterial.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.11, 0.12, 0.16))
	ui_font = _make_font()
	_terrain_material.friction = 1.0
	# 地形 → 磁力線 → キャラ の順に描きたいので、この順で追加する
	_level_root = Node2D.new()
	_level_root.name = "Level"
	add_child(_level_root)
	magnet = MagnetSystem.new()
	add_child(magnet)

	var devices := [PlayerInput.Device.WASD, PlayerInput.Device.MOUSE]
	for i in 2:
		var input := PlayerInput.new()
		input.device = devices[i]
		inputs.append(input)
		var p := Player.new()
		p.name = "Player%d" % (i + 1)
		p.index = i
		p.input = input
		add_child(p)
		p.set_shape(START_SHAPES[i])
		players.append(p)
	players[0].partner = players[1]
	players[1].partner = players[0]
	magnet.setup(players[0], players[1], ui_font)

	_build_hud()
	panel = DebugPanel.new()
	add_child(panel)
	var shape_names: Array[String] = ShapeLib.NAMES.duplicate()
	shape_names.append(ShapeLib.DRAWN)
	panel.build(ui_font, shape_names, PlayerInput.DEVICE_NAMES, START_SHAPES, devices, _stage_names())
	panel.shape_selected.connect(_on_shape_selected)
	panel.device_selected.connect(_on_device_selected)
	panel.side_swap_toggled.connect(_on_side_swap_toggled)
	panel.restart_requested.connect(_on_restart_requested)
	panel.stage_selected.connect(load_stage)
	panel.visible = false

	draw_screen = DrawScreen.new()
	add_child(draw_screen)
	var titles: Array[String] = ["1P の形", "2P の形"]
	var fills: Array[Color] = [Player.COLOR_N, Player.COLOR_S]
	draw_screen.build(ui_font, titles, fills, Player.OUTLINE_COLORS)
	draw_screen.finished.connect(_on_drawing_finished)
	draw_screen.cancelled.connect(_on_drawing_cancelled)
	_load_drawings()

	load_stage(0)


## ステージを読み込み、地形を作り直して2人を出現位置に戻す。
func load_stage(index: int) -> void:
	stage_index = wrapi(index, 0, Stages.STAGES.size())
	stage = Stages.STAGES[stage_index]
	_build_level()
	retries = 0
	panel.select_stage(stage_index)
	restart()
	queue_redraw()


## 外部（テストなど）からステージデータを直接渡して読み込む。
func load_stage_data(data: Dictionary) -> void:
	stage = data
	_build_level()
	retries = 0
	restart()
	queue_redraw()


func restart() -> void:
	var spawns: Array = stage["spawns"]
	var poles: Array = stage["poles"]
	for i in 2:
		var p: Player = players[i]
		p.reset_to(spawns[i], poles[i])
	magnet.reset()
	elapsed = 0.0
	clear_timer = -1.0
	center_label.text = ""
	_respawn_grace = 0.2


func _physics_process(delta: float) -> void:
	for i in 2:
		var input: PlayerInput = inputs[i]
		input.update(delta)
		if input.toggle_pressed:
			var p: Player = players[i]
			p.toggle_pole()
	magnet.step(delta)

	if clear_timer >= 0.0:
		clear_timer -= delta
		if clear_timer < 0.0:
			load_stage(stage_index + 1)
		return

	elapsed += delta
	_respawn_grace -= delta
	if _respawn_grace > 0.0:
		return
	for p in players:
		var body: Player = p
		if body.global_position.y > float(stage["death_y"]):
			retries += 1
			restart()
			return
	if _in_goal(players[0]) and _in_goal(players[1]):
		clear_timer = CLEAR_WAIT
		center_label.text = "CLEAR!  %.1f 秒" % elapsed


func _process(_delta: float) -> void:
	_update_mouse_mode()
	var p1: Player = players[0]
	var p2: Player = players[1]
	var in1: PlayerInput = inputs[0]
	var in2: PlayerInput = inputs[1]
	var rel := "圏外"
	if magnet.in_range:
		rel = "反発" if magnet.relation > 0 else "引力"
	hud_label.text = "%s ― %s\n1P [%s] %s極     2P [%s] %s極     関係: %s\n時間 %.1f 秒    やり直し %d 回        F1: 調整パネル    F4: お絵描き    R / Backspace: やり直し    F2 / F3: ステージ切り替え" % [
		stage["name"], stage["hint"],
		PlayerInput.DEVICE_NAMES[in1.device], _pole_text(p1),
		PlayerInput.DEVICE_NAMES[in2.device], _pole_text(p2),
		rel, elapsed, retries,
	]
	keys_label.text = "押しているキー: " + " ".join(PackedStringArray(held_names.keys()))


func _input(event: InputEvent) -> void:
	for input in inputs:
		(input as PlayerInput).handle_event(event)

	var key := event as InputEventKey
	if key:
		var key_name := OS.get_keycode_string(key.physical_keycode)
		if key.pressed:
			held_names[key_name] = true
		else:
			held_names.erase(key_name)
		if key.pressed and not key.echo:
			match key.physical_keycode:
				KEY_F1:
					panel.visible = not panel.visible
				KEY_R, KEY_BACKSPACE:
					retries += 1
					restart()
				KEY_F4:
					draw_screen.open(drawings)
				KEY_F2:
					load_stage(stage_index - 1)
				KEY_F3:
					load_stage(stage_index + 1)
		return

	var mb := event as InputEventMouseButton
	if mb and MOUSE_NAMES.has(mb.button_index):
		var button_name: String = MOUSE_NAMES[mb.button_index]
		if mb.pressed:
			held_names[button_name] = true
		else:
			held_names.erase(button_name)


func _draw() -> void:
	if stage.is_empty():
		return
	var goal: Rect2 = stage["goal"]
	draw_rect(goal, Color(0.3, 0.9, 0.5, 0.12))
	draw_rect(goal, Color(0.3, 0.9, 0.5, 0.6), false, 2.0)
	draw_string(ui_font, goal.position + Vector2(0, 26), "GOAL", HORIZONTAL_ALIGNMENT_CENTER, goal.size.x, 20, Color(0.5, 1.0, 0.6))


func _in_goal(p: Player) -> bool:
	var goal: Rect2 = stage["goal"]
	return goal.has_point(p.global_position)


func _stage_names() -> Array[String]:
	var names: Array[String] = []
	for s in Stages.STAGES:
		names.append(s["name"])
	return names


func _pole_text(p: Player) -> String:
	return "N" if p.pole == Player.POLE_N else "S"


## マウス担当がいるときはカーソルを隠してウィンドウ内に閉じ込める。
## パネルを開いている間はカーソルを戻し、マウス担当の入力を止める。
func _update_mouse_mode() -> void:
	var uses_mouse := false
	for input in inputs:
		var inp: PlayerInput = input
		var is_mouse := inp.device == PlayerInput.Device.MOUSE
		inp.enabled = not (panel.visible and is_mouse)
		uses_mouse = uses_mouse or is_mouse
	var want := Input.MOUSE_MODE_CONFINED_HIDDEN if uses_mouse and not panel.visible else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _build_level() -> void:
	for child in _level_root.get_children():
		child.queue_free()
	var rects: Array = WALLS.duplicate()
	rects.append_array(stage["blocks"])
	for r in rects:
		var rect: Rect2 = r
		var body := StaticBody2D.new()
		body.position = rect.get_center()
		body.physics_material_override = _terrain_material
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)

		var half := rect.size / 2.0
		var art := Polygon2D.new()
		art.polygon = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
		art.color = BLOCK_COLOR
		body.add_child(art)
		_level_root.add_child(body)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 16
	root.theme = theme
	layer.add_child(root)

	hud_label = _hud_label(root, Vector2(12, 8))
	keys_label = _hud_label(root, Vector2(12, 688))
	center_label = _hud_label(root, Vector2(0, 300))
	center_label.size = Vector2(1280, 100)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 64)


func _hud_label(root: Control, pos: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(label)
	return label


func _make_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo UI", "Meiryo", "MS Gothic", "Noto Sans CJK JP", "Hiragino Sans"])
	return font


func _on_shape_selected(player_index: int, shape_name: String) -> void:
	var p: Player = players[player_index]
	if shape_name == ShapeLib.DRAWN:
		var poly: PackedVector2Array = drawings[player_index]
		if poly.is_empty():
			# まだ描いていないのでお絵描き画面を開く
			draw_screen.open(drawings)
			return
		p.set_polygon(poly, ShapeLib.DRAWN)
	else:
		p.set_shape(shape_name)


func _on_drawing_finished(polygons: Array) -> void:
	held_names.clear()  # 一時停止中に離したキーが押しっぱなし表示で残らないように
	for i in 2:
		var poly: PackedVector2Array = polygons[i]
		if poly.is_empty():
			continue
		drawings[i] = poly
		(players[i] as Player).set_polygon(poly, ShapeLib.DRAWN)
		panel.select_shape(i, ShapeLib.DRAWN)
	_save_drawings()
	# 形が変わると床にめり込むことがあるので、出現位置からやり直す
	restart()


func _on_drawing_cancelled() -> void:
	held_names.clear()


## 前回描いた形を読み込み、あればその形で始める
func _load_drawings() -> void:
	var cfg := ConfigFile.new()
	if not persist_drawings or cfg.load(DRAWINGS_PATH) != OK:
		return
	for i in 2:
		var poly: PackedVector2Array = cfg.get_value("drawings", "p%d" % (i + 1), PackedVector2Array())
		if ShapeLib.is_valid(poly):
			drawings[i] = poly
			(players[i] as Player).set_polygon(poly, ShapeLib.DRAWN)
			panel.select_shape(i, ShapeLib.DRAWN)


func _save_drawings() -> void:
	if not persist_drawings:
		return
	var cfg := ConfigFile.new()
	for i in 2:
		cfg.set_value("drawings", "p%d" % (i + 1), drawings[i])
	cfg.save(DRAWINGS_PATH)


func _on_device_selected(player_index: int, device: int) -> void:
	(inputs[player_index] as PlayerInput).device = device


func _on_side_swap_toggled(on: bool) -> void:
	for input in inputs:
		(input as PlayerInput).swap_side_buttons = on


func _on_restart_requested() -> void:
	retries += 1
	restart()
