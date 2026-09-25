extends RefCounted
## 1人分の入力を「左右・ジャンプ・極切り替え」の4入力に変換する。
## ゲーム側はデバイスを意識せず、axis / jump_pressed / jump_held / toggle_pressed だけを見る。

enum Device { WASD, ARROWS, MOUSE, PAD1, PAD2 }

const DEVICE_NAMES: Array[String] = ["キーボード WASD", "キーボード 矢印", "マウス", "パッド1", "パッド2"]
const STICK_DEADZONE := 0.35
## ホイールは押しっぱなしができないので、ジャンプを押した扱いにする秒数
const WHEEL_JUMP_HOLD := 0.25

var device: int = Device.WASD
var enabled := true
var swap_side_buttons := false

var axis := 0.0
var jump_held := false
var jump_pressed := false
var toggle_pressed := false

var _prev_jump := false
var _prev_toggle := false
var _wheel_jump := false
var _wheel_toggle := false
var _wheel_hold := 0.0


## ホイールはイベントでしか取れないので、ここで受け取って次の update で反映する。
func handle_event(event: InputEvent) -> void:
	if device != Device.MOUSE or not enabled:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wheel_jump = true
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel_toggle = true


func update(delta: float) -> void:
	var left := false
	var right := false
	var jump := false
	var toggle := false
	match device:
		Device.WASD:
			left = Input.is_physical_key_pressed(KEY_A)
			right = Input.is_physical_key_pressed(KEY_D)
			jump = Input.is_physical_key_pressed(KEY_W)
			toggle = Input.is_physical_key_pressed(KEY_S)
		Device.ARROWS:
			left = Input.is_physical_key_pressed(KEY_LEFT)
			right = Input.is_physical_key_pressed(KEY_RIGHT)
			jump = Input.is_physical_key_pressed(KEY_UP)
			toggle = Input.is_physical_key_pressed(KEY_DOWN)
		Device.MOUSE:
			# XBUTTON2 = 進む（上側）、XBUTTON1 = 戻る（下側）が一般的
			var upper: MouseButton = MOUSE_BUTTON_XBUTTON1 if swap_side_buttons else MOUSE_BUTTON_XBUTTON2
			var lower: MouseButton = MOUSE_BUTTON_XBUTTON2 if swap_side_buttons else MOUSE_BUTTON_XBUTTON1
			left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			right = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			jump = Input.is_mouse_button_pressed(upper)
			toggle = Input.is_mouse_button_pressed(lower)
		Device.PAD1, Device.PAD2:
			var id := 0 if device == Device.PAD1 else 1
			var stick_x := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
			left = stick_x < -STICK_DEADZONE or Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT)
			right = stick_x > STICK_DEADZONE or Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT)
			jump = Input.is_joy_button_pressed(id, JOY_BUTTON_A)
			toggle = (
				Input.is_joy_button_pressed(id, JOY_BUTTON_B)
				or Input.is_joy_button_pressed(id, JOY_BUTTON_X)
				or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
			)

	if not enabled:
		left = false
		right = false
		jump = false
		toggle = false
		_wheel_jump = false
		_wheel_toggle = false

	axis = float(right) - float(left)
	jump_pressed = jump and not _prev_jump
	toggle_pressed = toggle and not _prev_toggle
	_prev_jump = jump
	_prev_toggle = toggle

	if _wheel_jump:
		jump_pressed = true
		_wheel_hold = WHEEL_JUMP_HOLD
		_wheel_jump = false
	if _wheel_toggle:
		toggle_pressed = true
		_wheel_toggle = false
	_wheel_hold = maxf(_wheel_hold - delta, 0.0)
	jump_held = jump or _wheel_hold > 0.0
