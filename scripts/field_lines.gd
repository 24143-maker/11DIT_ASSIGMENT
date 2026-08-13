extends Node2D

const LINE_COLOUR := Color(0.95, 0.95, 0.95, 0.9)

func _ready() -> void:
	# Sidelines, inset 2px from the edge
	_rect(Vector2(0, 2), Vector2(896, 2))
	_rect(Vector2(0, 540), Vector2(896, 2))

	# 10m markers
	for m in range(10, 100, 10):
		if m == 50:
			continue
		_vline(48.0 + m * 8.0, 2.0)

	# Try lines and halfway, thicker
	_vline(48.0, 4.0)
	_vline(448.0, 4.0)
	_vline(848.0, 4.0)


func _vline(centre_x: float, w: float) -> void:
	# Inset top and bottom so verticals don't overlap the sidelines
	_rect(Vector2(centre_x - w / 2.0, 4.0), Vector2(w, 536.0))


func _rect(pos: Vector2, size: Vector2) -> void:
	var r := ColorRect.new()
	r.color = LINE_COLOUR
	r.position = pos
	r.size = size
	r.z_index = -9
	add_child(r)
