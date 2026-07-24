extends Node2D
class_name Field

const METRE: float = 8.0          # 1 metre = 8 pixels
const FIELD_LEFT: float = 48.0    # left try line
const FIELD_RIGHT: float = 848.0  # right try line
const FIELD_TOP: float = 0.0
const FIELD_BOTTOM: float = 544.0
const INGOAL_DEPTH: float = 48.0  # 6 metres

static func metres_to_pixels(m: float) -> float:
	return m * METRE

# How many metres from the right try line is this position?
static func metres_out(pos: Vector2) -> float:
	return (FIELD_RIGHT - pos.x) / METRE
