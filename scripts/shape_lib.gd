extends RefCounted
## キャラの形（多角形データ）を作る。プリセット形状と、手描きの線からの変換。
## どの形も重心を原点に移し、面積を TARGET_AREA にそろえる。

const NAMES: Array[String] = ["四角", "丸", "三角", "星", "棒", "C字", "L字"]
## 形の一覧で「そのプレイヤーが描いた形」を表す名前
const DRAWN := "描いた形"
const TARGET_AREA := 2400.0
## 重心から一番遠い点までの距離の上限。長い棒で奈落に橋を架けられないようにする
const MAX_RADIUS := 70.0
## 物理に使う多角形の頂点数の上限
const MAX_VERTS := 40
## 線として描かれたときの太さ（描画欄の座標で）。長い線ほど太くして、極端に細い形を防ぐ
const LINE_MIN_THICKNESS := 14.0
const LINE_MAX_ASPECT := 8.0


## 手描きの一筆（描画欄の座標の点列）を、物理に使える多角形にする。失敗したら空を返す。
## 書き始めの近くで終わっていれば閉じた形、そうでなければ線に太さを付けた形にする。
## 線が交差していても、外周をたどった1つの形にまとめる（穴は埋まる）。
static func from_stroke(stroke: PackedVector2Array) -> PackedVector2Array:
	if stroke.size() < 3:
		return PackedVector2Array()
	var length := polyline_length(stroke)
	if length < 40.0:
		return PackedVector2Array()
	var bounds := _bounds(stroke)
	var line := _simplify_polyline(stroke, 1.5)
	var outline := PackedVector2Array()

	var closed := stroke[0].distance_to(stroke[stroke.size() - 1]) < maxf(30.0, bounds.size.length() * 0.25)
	if closed:
		# 線を輪として太らせて一番外側の輪郭を取る。8の字のように交差していても両方の輪が入る
		outline = _largest(Geometry2D.offset_polyline(line, 2.0, Geometry2D.JOIN_MITER, Geometry2D.END_JOINED))
		# ほとんど面積のない閉じた形（行って戻っただけの線など）は線として扱う
		if outline.size() < 3 or absf(signed_area(outline)) < 300.0:
			closed = false
	if not closed:
		var thickness := maxf(LINE_MIN_THICKNESS, length / LINE_MAX_ASPECT)
		outline = _largest(Geometry2D.offset_polyline(line, thickness * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	if outline.size() < 3:
		return PackedVector2Array()

	# 頂点を減らしてから、もう一度外周を取り直して自己交差をなくす
	outline = _simplify_closed(outline, 1.0)
	outline = _reduce_vertices(outline, MAX_VERTS)
	outline = _largest(Geometry2D.offset_polygon(outline, 0.5, Geometry2D.JOIN_MITER))
	if outline.size() > MAX_VERTS:
		outline = _reduce_vertices(outline, MAX_VERTS)
	var result := clamp_radius(normalize(outline), MAX_RADIUS)
	return result if is_valid(result) else PackedVector2Array()


## 物理と描画に使えるか（三角形分割と凸分解ができるか）
static func is_valid(poly: PackedVector2Array) -> bool:
	if poly.size() < 3 or absf(signed_area(poly)) < 1.0:
		return false
	return Geometry2D.triangulate_polygon(poly).size() > 0 and Geometry2D.decompose_polygon_in_convex(poly).size() > 0


## 重心（原点）から一番遠い点が max_radius を超えていたら、全体を縮める
static func clamp_radius(poly: PackedVector2Array, max_radius: float) -> PackedVector2Array:
	var radius := bounding_radius(poly)
	if radius <= max_radius:
		return poly
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * (max_radius / radius))
	return out


static func bounding_radius(poly: PackedVector2Array) -> float:
	var radius := 0.0
	for p in poly:
		radius = maxf(radius, p.length())
	return radius


static func polyline_length(pts: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	return length


static func make(shape_name: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape_name:
		"四角":
			pts = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
		"丸":
			pts = _arc(1.0, 0.0, TAU, 24, false)
		"三角":
			pts = PackedVector2Array([Vector2(0, -1.15), Vector2(1, 0.58), Vector2(-1, 0.58)])
		"星":
			for i in 10:
				var angle := -PI / 2.0 + i * PI / 5.0
				var radius := 1.0 if i % 2 == 0 else 0.45
				pts.append(Vector2(cos(angle), sin(angle)) * radius)
		"棒":
			pts = PackedVector2Array([Vector2(-2, -0.5), Vector2(2, -0.5), Vector2(2, 0.5), Vector2(-2, 0.5)])
		"C字":
			pts = _arc(1.0, deg_to_rad(40.0), deg_to_rad(320.0), 16, true)
			pts.append_array(_arc(0.55, deg_to_rad(320.0), deg_to_rad(40.0), 12, true))
		"L字":
			pts = PackedVector2Array([
				Vector2(-1, -1.5), Vector2(-0.3, -1.5), Vector2(-0.3, 0.8),
				Vector2(1, 0.8), Vector2(1, 1.5), Vector2(-1, 1.5),
			])
		_:
			push_warning("未知の形: %s" % shape_name)
			return make("四角")
	return normalize(pts)


## 重心を原点へ移し、面積を TARGET_AREA にそろえる。
static func normalize(pts: PackedVector2Array) -> PackedVector2Array:
	var area := signed_area(pts)
	if absf(area) < 0.0001:
		return pts
	var center := centroid(pts, area)
	var scale := sqrt(TARGET_AREA / absf(area))
	var out := PackedVector2Array()
	for p in pts:
		out.append((p - center) * scale)
	return out


static func signed_area(pts: PackedVector2Array) -> float:
	var sum := 0.0
	for i in pts.size():
		sum += pts[i].cross(pts[(i + 1) % pts.size()])
	return sum * 0.5


static func centroid(pts: PackedVector2Array, area: float) -> Vector2:
	var c := Vector2.ZERO
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		c += (p + q) * p.cross(q)
	return c / (6.0 * area)


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	return rect


## 複数の多角形から面積が一番大きいもの（＝外周）を選ぶ
static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for poly in polys:
		var area := absf(signed_area(poly))
		if area > best_area:
			best_area = area
			best = poly
	return best


## 折れ線の頂点を減らす（Ramer–Douglas–Peucker）
static func _simplify_polyline(pts: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep: Array[bool] = []
	keep.resize(pts.size())
	keep.fill(false)
	keep[0] = true
	keep[pts.size() - 1] = true
	var stack: Array[Vector2i] = [Vector2i(0, pts.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var max_dist := 0.0
		var max_index := -1
		for i in range(span.x + 1, span.y):
			var d := _distance_to_segment(pts[i], pts[span.x], pts[span.y])
			if d > max_dist:
				max_dist = d
				max_index = i
		if max_index >= 0 and max_dist > epsilon:
			keep[max_index] = true
			stack.append(Vector2i(span.x, max_index))
			stack.append(Vector2i(max_index, span.y))
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i]:
			out.append(pts[i])
	return out


## 閉じた多角形に RDP をかける（始点で切り開いて折れ線として扱う）
static func _simplify_closed(poly: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if poly.size() <= 4:
		return poly
	var ring := poly.duplicate()
	ring.append(poly[0])
	var out := _simplify_polyline(ring, epsilon)
	out.remove_at(out.size() - 1)
	return out if out.size() >= 3 else poly


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## 閉じた多角形の頂点を、形への影響が小さいもの（前後と作る三角形が小さいもの）から削る
static func _reduce_vertices(poly: PackedVector2Array, max_verts: int) -> PackedVector2Array:
	var pts := Array(poly)
	while pts.size() > 3:
		var min_area := INF
		var min_index := -1
		for i in pts.size():
			var a: Vector2 = pts[(i - 1 + pts.size()) % pts.size()]
			var b: Vector2 = pts[i]
			var c: Vector2 = pts[(i + 1) % pts.size()]
			var area := absf((b - a).cross(c - a)) * 0.5
			if area < min_area:
				min_area = area
				min_index = i
		# 頂点数が上限以下で、削れる頂点がほぼ一直線上のものでなければ終わり
		if pts.size() <= max_verts and min_area > 2.0:
			break
		pts.remove_at(min_index)
	return PackedVector2Array(pts)


static func _arc(radius: float, from: float, to: float, count: int, include_end: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var divisions := count - 1 if include_end else count
	for i in count:
		var angle := from + (to - from) * float(i) / float(divisions)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts
