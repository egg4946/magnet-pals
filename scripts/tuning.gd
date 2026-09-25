extends Node
## 調整パラメータの一元管理。F1 パネルから変更し、user://tuning.cfg に保存する。
## 意味と初期値の一覧は docs/prototype-spec.md の「調整パラメータ」を参照。

signal changed(key: String)

const SAVE_PATH := "user://tuning.cfg"

const DEFS: Array = [
	{"key": "magnet_strength", "group": "磁力", "label": "磁力の強さ", "min": 0.0, "max": 8000.0, "step": 50.0, "default": 4000.0, "tip": "距離0のときの力（質量1あたり px/s²）"},
	{"key": "magnet_range", "group": "磁力", "label": "作用範囲", "min": 40.0, "max": 600.0, "step": 5.0, "default": 260.0, "tip": "この距離より離れると磁力は0"},
	{"key": "falloff_power", "group": "磁力", "label": "減衰の鋭さ", "min": 0.2, "max": 3.0, "step": 0.05, "default": 0.6, "tip": "1=線形。1より小さいと中距離でも力が残る。大きいほど近距離に力が集中する"},
	{"key": "ramp_time", "group": "磁力", "label": "立ち上がり時間", "min": 0.0, "max": 0.5, "step": 0.01, "default": 0.1, "tip": "引力⇔反発が切り替わってから最大の力になるまでの秒数"},
	{"key": "anchor_factor", "group": "磁力", "label": "接地アンカー", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.2, "tip": "地形の上に立っている側が受ける力の倍率（1=アンカーなし）"},
	{"key": "burst_speed", "group": "磁力", "label": "くっつき反転の速度", "min": 0.0, "max": 1500.0, "step": 10.0, "default": 650.0, "tip": "接触中に引力→反発へ切り替えた瞬間に加わる速度（0=無効）"},
	{"key": "burst_spin", "group": "磁力", "label": "くっつき反転の回転", "min": 0.0, "max": 30.0, "step": 0.5, "default": 8.0, "tip": "弾けたときにランダムに加わる回転（rad/s）"},
	{"key": "burst_cooldown", "group": "磁力", "label": "くっつき反転の待ち", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.4, "tip": "くっつき反転の再使用待ち（秒）"},
	{"key": "max_speed", "group": "磁力", "label": "速度上限", "min": 200.0, "max": 3000.0, "step": 50.0, "default": 1400.0, "tip": "どんな理由でもこれ以上速くならない"},
	{"key": "move_accel", "group": "移動", "label": "地上の横加速", "min": 0.0, "max": 3000.0, "step": 50.0, "default": 900.0, "tip": "左右入力で加わる横方向の加速度"},
	{"key": "max_move_speed", "group": "移動", "label": "自力の横速度上限", "min": 50.0, "max": 800.0, "step": 10.0, "default": 260.0, "tip": "左右入力だけで出せる横速度の上限"},
	{"key": "roll_spin", "group": "移動", "label": "転がりの回転速度", "min": 0.0, "max": 30.0, "step": 0.5, "default": 10.0, "tip": "地上で左右入力したときの目標回転速度（rad/s）"},
	{"key": "roll_accel", "group": "移動", "label": "転がりの強さ", "min": 0.0, "max": 200.0, "step": 1.0, "default": 40.0, "tip": "目標回転速度へ近づける強さ"},
	{"key": "air_control", "group": "移動", "label": "空中の横加速", "min": 0.0, "max": 2000.0, "step": 10.0, "default": 350.0, "tip": "空中で左右入力したときの横加速度"},
	{"key": "air_spin_accel", "group": "移動", "label": "空中姿勢制御", "min": 0.0, "max": 100.0, "step": 1.0, "default": 25.0, "tip": "空中で左右入力したときに回転を加える強さ"},
	{"key": "max_air_spin", "group": "移動", "label": "空中回転の上限", "min": 0.0, "max": 40.0, "step": 0.5, "default": 14.0, "tip": "空中姿勢制御で出せる回転速度の上限（rad/s）"},
	{"key": "jump_speed", "group": "ジャンプ", "label": "ジャンプ初速", "min": 0.0, "max": 1200.0, "step": 10.0, "default": 520.0, "tip": "ジャンプした瞬間に加わる速度"},
	{"key": "jump_normal_blend", "group": "ジャンプ", "label": "面の向きに跳ぶ割合", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.6, "tip": "0=常に真上、1=接している面から離れる向き（壁を蹴ると真横に跳ぶ）。小さくすると壁キックだけで1人で壁を登れてしまう"},
	{"key": "jump_cut", "group": "ジャンプ", "label": "小ジャンプ倍率", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.5, "tip": "ボタンを早く離したときに上昇速度に掛ける倍率（1=無効）"},
	{"key": "coyote_time", "group": "ジャンプ", "label": "ジャンプ猶予", "min": 0.0, "max": 0.3, "step": 0.01, "default": 0.1, "tip": "足場を離れた後もジャンプできる秒数"},
	{"key": "jump_reaction", "group": "ジャンプ", "label": "踏み台の反作用", "min": 0.0, "max": 2.0, "step": 0.05, "default": 1.0, "tip": "相方を踏み台にしたとき相方を押し下げる強さ"},
	{"key": "gravity_scale", "group": "物理", "label": "重力倍率", "min": 0.2, "max": 3.0, "step": 0.05, "default": 1.0, "tip": "重力の倍率"},
	{"key": "friction", "group": "物理", "label": "摩擦", "min": 0.0, "max": 1.5, "step": 0.05, "default": 0.8, "tip": "キャラの摩擦"},
	{"key": "bounce", "group": "物理", "label": "反発係数", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.15, "tip": "キャラの跳ね返りやすさ"},
	{"key": "angular_damp", "group": "物理", "label": "回転の減衰", "min": 0.0, "max": 5.0, "step": 0.05, "default": 0.3, "tip": "大きいほど回転がすぐ止まる"},
]

var values: Dictionary = {}


func _ready() -> void:
	reset()
	load_saved()


func val(key: String) -> float:
	return values[key]


func set_value(key: String, value: float) -> void:
	values[key] = value
	changed.emit(key)


func reset() -> void:
	for def in DEFS:
		values[def["key"]] = float(def["default"])


func save() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("tuning", key, values[key])
	cfg.save(SAVE_PATH)


func load_saved() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	for def in DEFS:
		var key: String = def["key"]
		if cfg.has_section_key("tuning", key):
			values[key] = float(cfg.get_value("tuning", key))
	return true
