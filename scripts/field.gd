extends Node2D
class_name Field
# Field constants. 1 metre = 8 pixels.

const METRE: float = 8.0
const FIELD_LEFT: float = 48.0      # left try line
const FIELD_RIGHT: float = 848.0    # right try line
const FIELD_TOP: float = 0.0
const FIELD_BOTTOM: float = 544.0
const INGOAL_DEPTH: float = 48.0    # 6 metres
const DEAD_LEFT: float = 0.0
const DEAD_RIGHT: float = 896.0

static func metres_to_pixels(m: float) -> float:
	return m * METRE

static func metres_out(pos: Vector2) -> float:
	return (FIELD_RIGHT - pos.x) / METRE

static func centre() -> Vector2:
	return Vector2((FIELD_LEFT + FIELD_RIGHT) * 0.5, FIELD_BOTTOM * 0.5)
