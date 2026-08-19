extends Node2D

const WHITE := Color(0.95, 0.95, 0.95, 0.9)
const RED   := Color(0.84, 0.21, 0.19, 0.9)

func _ready() -> void:
	# Sidelines, inset 2px from the edge
	_rect(Vector2(0, 2), Vector2(896, 2), WHITE)
	_rect(Vector2(0, 540), Vector2(896, 2), WHITE)

	# 10m markers. The 20m and 40m lines (both ends) are red.
	for m in range(10, 100, 10):
		if m == 50:
			continue
		var is_red: bool = m in [20, 40, 60, 80]
		_vline(48.0 + m * 8.0, 2.0, RED if is_red else WHITE)

	# Try lines and halfway, thicker
	_vline(48.0, 4.0, WHITE)
	_vline(448.0, 4.0, WHITE)
	_vline(848.0, 4.0, WHITE)


func _vline(centre_x: float, w: float, col: Color) -> void:
	_rect(Vector2(centre_x - w / 2.0, 4.0), Vector2(w, 536.0), col)


func _rect(pos: Vector2, size: Vector2, col: Color) -> void:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = size
	r.z_index = -9
	add_child(r)
