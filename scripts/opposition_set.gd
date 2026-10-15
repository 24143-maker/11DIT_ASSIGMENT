extends RefCounted
class_name OppositionSet
# Pre-simulates the opposition's whole set BEFORE anything is shown.
# Returns a list of beats; each beat is one tackle with the resulting
# ball position. The match then plays them out one at a time.

const METRE := 8.0

# kind: "run", "break", "error", "kick", "try"
static func simulate(start_x: float, team: String) -> Array:
	var beats: Array = []
	var x: float = start_x            # they attack toward the LEFT try line
	var y: float = Field.FIELD_BOTTOM * 0.5

	beats.append({
		"text": "%s take over %dm out." % [team, _metres(x)],
		"ball_x": x, "ball_y": y, "kind": "start"
	})

	for tackle in range(1, 6):
		# Handling error hands it straight back
		if randf() < 0.07:
			beats.append({
				"text": "Tackle %d — spilled it! Knock on, your ball." % tackle,
				"ball_x": x, "ball_y": y, "kind": "error"
			})
			return beats

		var gain: float
		var kind: String
		var text: String

		if randf() < 0.18:
			gain = randf_range(14.0, 30.0) * METRE
			kind = "break"
			text = "Tackle %d — %s break the line and surge %dm upfield." % [
				tackle, team, int(gain / METRE)
			]
		else:
			gain = randf_range(3.0, 12.0) * METRE
			kind = "run"
			text = "Tackle %d — hit up for %dm." % [tackle, int(gain / METRE)]

		x -= gain
		y = clamp(y + randf_range(-70.0, 70.0), 90.0, Field.FIELD_BOTTOM - 90.0)

		if x <= Field.FIELD_LEFT + 4.0:
			x = Field.FIELD_LEFT
			beats.append({
				"text": "%s crash over. Try to %s." % [team, team],
				"ball_x": x, "ball_y": y, "kind": "try"
			})
			return beats

		beats.append({"text": text, "ball_x": x, "ball_y": y, "kind": kind})

	# Last tackle
	var roll: float = randf()
	if x < Field.FIELD_LEFT + 200.0 and roll < 0.30:
		if randf() < 0.4:
			beats.append({
				"text": "Last tackle — grubber in behind, and they regather! Try.",
				"ball_x": Field.FIELD_LEFT, "ball_y": y, "kind": "try"
			})
		else:
			beats.append({
				"text": "Last tackle — grubber through, but it rolls dead. Your ball.",
				"ball_x": Field.FIELD_LEFT + 160.0, "ball_y": y, "kind": "kick"
			})
		return beats

	# They attack toward the LEFT try line, so a kick travels to a SMALLER x.
	# This used to add the distance instead of subtracting it, which sent the
	# ball backwards into their own half and handed over good field position.
	var land: float
	if roll < 0.75:
		land = clamp(x - randf_range(12.0, 24.0) * METRE,
					 Field.FIELD_LEFT + 60.0, Field.FIELD_RIGHT - 70.0)
		beats.append({
			"text": "Last tackle — a bomb hangs up, and your fullback takes it cleanly.",
			"ball_x": land, "ball_y": y, "kind": "kick"
		})
	else:
		land = clamp(x - randf_range(24.0, 42.0) * METRE,
					 Field.FIELD_LEFT + 40.0, Field.FIELD_RIGHT - 70.0)
		beats.append({
			"text": "Last tackle — they kick long and pin you deep.",
			"ball_x": land, "ball_y": y, "kind": "kick"
		})
	return beats


static func _metres(x: float) -> int:
	var m: int = int((x - Field.FIELD_LEFT) / METRE)
	return int(round(float(m) / 5.0) * 5)
