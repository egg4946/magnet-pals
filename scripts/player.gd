extends RigidBody2D
## 磁石キャラ。形は多角形データで、回転あり・当たり判定は形そのまま（凹形も可）。
## 速度の操作はすべて _integrate_forces で行い、磁力は MagnetSystem から magnet_force で受け取る。

const ShapeLib = preload("res://scripts/shape_lib.gd")
const PlayerInput = preload("res://scripts/player_input.gd")

const POLE_N := 1
const POLE_S := -1
const COLOR_N := Color(0.92, 0.3, 0.3)
const COLOR_S := Color(0.3, 0.5, 0.95)
const OUTLINE_COLORS: Array[Color] = [Color(1, 1, 1, 0.95), Color(1, 0.85, 0.3, 0.95)]
## ジャンプボタンを早く離したときに小ジャンプ扱いにする時間
const JUMP_CUT_WINDOW := 0.3
## 出現位置が想定している、中心から下端までの距離（四角の半分）
const SPAWN_BOTTOM := 25.0

var index := 0
var pole := POLE_N
var input: PlayerInput
var partner: RigidBody2D
var shape_name := ""
var polygon := PackedVector2Array()

# 接触情報（_integrate_forces で毎フレーム更新）
var anchored := false          ## 地形の上に立っている＝磁力を踏ん張れる
var has_contact := false       ## 天井以外の何かに触れている＝ジャンプできる
var touching_partner := false

## MagnetSystem が毎フレーム書き込む磁力
var magnet_force := Vector2.ZERO

var _pending_velocity := Vector2.ZERO
var _pending_spin := 0.0
var _contact_normal := Vector2.ZERO
var _last_contact_normal := Vector2.UP
var _supports: Array[RigidBody2D] = []
var _coyote := 0.0
var _since_jump := 10.0
var _jump_cut_armed := false
var _reset_pending := false
var _reset_position := Vector2.ZERO

var _collision := CollisionPolygon2D.new()
var _material := PhysicsMaterial.new()


func _ready() -> void:
	mass = 1.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 16
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	physics_material_override = _material
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	add_child(_collision)
	_apply_tuning()


func set_shape(new_shape: String) -> void:
	set_polygon(ShapeLib.make(new_shape), new_shape)


## 形を多角形データで直接指定する（描いた形など）。重心が原点になっていること。
func set_polygon(new_polygon: PackedVector2Array, label: String) -> void:
	shape_name = label
	polygon = new_polygon
	_collision.polygon = polygon
	queue_redraw()


func toggle_pole() -> void:
	pole = -pole


func pole_color() -> Color:
	return COLOR_N if pole == POLE_N else COLOR_S


## 位置のワープは物理エンジンの中でしか安全にできないので、次の _integrate_forces で行う。
func reset_to(pos: Vector2, start_pole: int) -> void:
	pole = start_pole
	# 出現位置は「四角（下端まで約25px）が床に立つ高さ」で決めてあるので、
	# 下に長い形は床にめり込まないようにその分持ち上げる
	var bottom := 0.0
	for p in polygon:
		bottom = maxf(bottom, p.y)
	_reset_position = pos - Vector2(0, maxf(bottom - SPAWN_BOTTOM, 0.0))
	_reset_pending = true
	magnet_force = Vector2.ZERO
	_pending_velocity = Vector2.ZERO
	_pending_spin = 0.0


## 相方や MagnetSystem から瞬間的な速度変化を加える。
func add_velocity(dv: Vector2, spin := 0.0) -> void:
	_pending_velocity += dv
	_pending_spin += spin


func _physics_process(_delta: float) -> void:
	_apply_tuning()


func _process(_delta: float) -> void:
	queue_redraw()


func _apply_tuning() -> void:
	gravity_scale = Tuning.val("gravity_scale")
	angular_damp = Tuning.val("angular_damp")
	var friction := Tuning.val("friction")
	if _material.friction != friction:
		_material.friction = friction
	var bounce := Tuning.val("bounce")
	if _material.bounce != bounce:
		_material.bounce = bounce


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _reset_pending:
		state.transform = Transform2D(0.0, _reset_position)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		_reset_pending = false
		return

	var dt := state.step
	_read_contacts(state)

	var lv := state.linear_velocity
	var av := state.angular_velocity
	var x := 0.0
	var jump_pressed := false
	var jump_held := false
	if input:
		x = input.axis
		jump_pressed = input.jump_pressed
		jump_held = input.jump_held

	# ジャンプ（接している面から離れる向きと真上を混ぜる）。
	# 猶予時間中も最後に触れていた面の向きを使う（壁から離れた直後に真上へ跳べないように）。
	if has_contact:
		_coyote = Tuning.val("coyote_time")
		if _contact_normal.length() > 0.01:
			_last_contact_normal = _contact_normal.normalized()
	else:
		_coyote -= dt
	_since_jump += dt
	if jump_pressed and _coyote > 0.0:
		var dir := Vector2.UP.lerp(_last_contact_normal, Tuning.val("jump_normal_blend")).normalized()
		var along := lv.dot(dir)
		if along < 0.0:
			lv -= dir * along
		var speed := Tuning.val("jump_speed")
		lv += dir * speed
		# 踏み台にした相手（剛体）は反作用で押し下げる
		for body in _supports:
			if body.has_method("add_velocity"):
				body.add_velocity(-dir * speed * Tuning.val("jump_reaction") * mass / body.mass)
		_coyote = 0.0
		_since_jump = 0.0
		_jump_cut_armed = true
	if _jump_cut_armed:
		if _since_jump > JUMP_CUT_WINDOW:
			_jump_cut_armed = false
		elif not jump_held:
			if lv.y < 0.0:
				lv.y *= Tuning.val("jump_cut")
			_jump_cut_armed = false

	# 左右移動：地上は転がり、空中は姿勢制御
	if x != 0.0:
		if has_contact:
			av = _push_toward(av, x * Tuning.val("roll_spin"), Tuning.val("roll_accel") * dt)
			if lv.x * x < Tuning.val("max_move_speed"):
				lv.x += x * Tuning.val("move_accel") * dt
		else:
			av = _push_toward(av, x * Tuning.val("max_air_spin"), Tuning.val("air_spin_accel") * dt)
			if lv.x * x < Tuning.val("max_move_speed"):
				lv.x += x * Tuning.val("air_control") * dt

	# 磁力と外部からの速度変化
	lv += magnet_force / mass * dt
	lv += _pending_velocity
	av += _pending_spin
	_pending_velocity = Vector2.ZERO
	_pending_spin = 0.0

	var max_speed := Tuning.val("max_speed")
	if lv.length() > max_speed:
		lv = lv.normalized() * max_speed
	state.linear_velocity = lv
	state.angular_velocity = av


func _read_contacts(state: PhysicsDirectBodyState2D) -> void:
	anchored = false
	has_contact = false
	touching_partner = false
	_contact_normal = Vector2.ZERO
	_supports.clear()
	for i in state.get_contact_count():
		var normal := state.get_contact_local_normal(i)
		var other := state.get_contact_collider_object(i)
		if other == partner:
			touching_partner = true
		var up := normal.dot(Vector2.UP)
		if up < -0.2:
			continue  # 天井からはジャンプできない
		has_contact = true
		_contact_normal += normal
		if up > 0.5 and other is StaticBody2D:
			anchored = true
		if other is RigidBody2D and not _supports.has(other):
			_supports.append(other as RigidBody2D)


## 目標の回転速度へ近づける。すでに同じ向きで目標より速い場合は減速させない。
static func _push_toward(current: float, target: float, step: float) -> float:
	if target > 0.0:
		return current if current >= target else minf(current + step, target)
	return current if current <= target else maxf(current - step, target)


func _draw() -> void:
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, pole_color())
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, OUTLINE_COLORS[index], 3.0, true)
	# 目：相方の方を見る
	var look := Vector2.ZERO
	if partner:
		var to_partner := to_local(partner.global_position)
		if to_partner.length() > 0.01:
			look = to_partner.normalized() * 2.2
	for eye in [Vector2(-7, -4), Vector2(7, -4)]:
		draw_circle(eye, 5.0, Color.WHITE)
		draw_circle(eye + look, 2.4, Color.BLACK)
