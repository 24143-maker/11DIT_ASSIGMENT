extends RefCounted
class_name OppositionSet
# Simulates the opposition's set of six as a short sequence of text beats.
# Returns the narration lines plus where the ball ends up.

const METRE := 8.0

class Result:
	var lines: Array[String] = []
	var restart_x: float = 448.0     # where YOUR next set begins
	var they_scored: bool = false


static func simulate(start_x: float, team_name: String) -> Result:
	var r := Result.new()
	var x: float = start_x           # they attack toward the LEFT try line
	var tackle: int = 0

	r.lines.append("%s take over on the %dm line." % [team_name, _metres_out(x)])

	while tackle < 5:
		tackle += 1

		# Rare handling error hands it straight back
		if randf() < 0.07:
			r.lines.append("Tackle %d — they spill it! Knock on, your ball." % tackle)
			r.restart_x = x
			return r

		var gain: float = randf_range(3.0, 13.0) * METRE
		if randf() < 0.18:
			gain += randf_range(8.0, 20.0) * METRE
			r.lines.append("Tackle %d — they break the line and surge upfield." % tackle)
		else:
			r.lines.append("Tackle %d — hit up through the middle, a few metres." % tackle)

		x -= gain

		# Close enough to score?
		if x <= Field.FIELD_LEFT:
			r.lines.append("They crash over in the corner. Try to %s." % team_name)
			r.they_scored = true
			return r

	# Last tackle
	var roll: float = randf()
	if x < Field.FIELD_LEFT + 200.0 and roll < 0.30:
		if randf() < 0.4:
			r.lines.append("Last tackle — grubber into the in-goal, and they regather! Try.")
			r.they_scored = true
			return r
		r.lines.append("Last tackle — grubber through, but it rolls dead. Your ball.")
		r.restart_x = Field.FIELD_LEFT + 160.0
		return r

	if roll < 0.75:
		r.lines.append("Last tackle — they put up a bomb and your fullback takes it cleanly.")
		r.restart_x = clamp(x + randf_range(10.0, 25.0) * METRE, Field.FIELD_LEFT + 60.0, Field.FIELD_RIGHT - 60.0)
		return r

	r.lines.append("Last tackle — they kick long downfield.")
	r.restart_x = clamp(x + randf_range(25.0, 45.0) * METRE, Field.FIELD_LEFT + 60.0, Field.FIELD_RIGHT - 60.0)
	return r


static func _metres_out(x: float) -> int:
	# Distance from the left try line, rounded to the nearest 5
	var m: int = int((x - Field.FIELD_LEFT) / METRE)
	return int(round(float(m) / 5.0) * 5)
