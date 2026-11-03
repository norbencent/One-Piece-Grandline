class_name NeonBackdrop
extends Control
## Animated retro-futuristic ocean backdrop drawn procedurally (no texture memory):
## banded night sky, twinkling stars, striped neon sun, perspective sea grid and rolling waves.
## Everything is snapped to whole pixels so it stays crisp under nearest-neighbor scaling.

@export var sky_top := Color("060a18")
@export var sky_bottom := Color("1a1f52")
@export var sun_color := Color("ff3b5c")
@export var sun_glow := Color("ffc847")
@export var grid_color := Color("29d8ff")
@export_range(0.3, 0.9) var horizon_ratio := 0.62
@export var animate := true

const STAR_COUNT := 80
const SKY_BANDS := 14

var _t := 0.0
var _stars: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in STAR_COUNT:
		_stars.append(Vector3(rng.randf(), rng.randf_range(0.0, 0.85), rng.randf() * TAU))


func _process(delta: float) -> void:
	if animate and is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var hy := floorf(h * horizon_ratio)

	# Banded sky gradient.
	var band_h := ceilf(hy / SKY_BANDS)
	for i in SKY_BANDS:
		var c := sky_top.lerp(sky_bottom, float(i) / (SKY_BANDS - 1))
		draw_rect(Rect2(0, i * band_h, w, band_h + 1), c)

	# Stars.
	for s in _stars:
		var a := 0.35 + 0.65 * absf(sin(_t * 1.3 + s.z))
		draw_rect(Rect2(floorf(s.x * w), floorf(s.y * hy), 1, 1), Color(0.85, 0.93, 1.0, a))

	# Neon sun with retro stripes, sitting on the horizon.
	var r := floorf(minf(w, h) * 0.16)
	var sun_c := Vector2(floorf(w * 0.5), hy - floorf(r * 0.35))
	draw_circle(sun_c, r + 3, Color(sun_glow, 0.18))
	draw_circle(sun_c, r, sun_color)
	draw_circle(sun_c + Vector2(0, -r * 0.3), r * 0.7, Color(sun_glow, 0.18))
	for k in 5:
		var sy := sun_c.y + floorf(r * 0.1) + k * floorf(r * 0.17)
		draw_rect(Rect2(sun_c.x - r - 1, sy, r * 2 + 2, 1 + k), sky_bottom)

	# Sea.
	draw_rect(Rect2(0, hy, w, h - hy), Color("040814"))
	draw_rect(Rect2(0, hy, w, 1), Color(sun_glow, 0.9))

	# Perspective grid: horizontal lines scroll toward the viewer.
	var lines := 9
	var scroll := fmod(_t * 0.25, 1.0)
	for i in lines:
		var p := (float(i) + scroll) / lines
		var y := floorf(hy + (h - hy) * p * p)
		draw_rect(Rect2(0, y, w, 1), Color(grid_color, 0.15 + 0.45 * p))
	var vx := w * 0.5
	for j in range(-10, 11):
		var bx := vx + j * w * 0.12
		draw_line(Vector2(vx + j * 6, hy), Vector2(bx, h), Color(grid_color, 0.22), 1.0)

	# Rolling wave crests.
	for row in 3:
		var base_y := hy + 6 + row * 14
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= w + 4:
			pts.append(Vector2(x, floorf(base_y + sin(x * 0.045 + _t * (1.6 + row * 0.4) + row) * (1.5 + row))))
			x += 4.0
		draw_polyline(pts, Color(grid_color.lightened(0.3), 0.35 - row * 0.08), 1.0)
