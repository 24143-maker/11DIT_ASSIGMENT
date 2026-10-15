extends Node2D
class_name Stadium
# Builds the stadium surround, the night tint and four corner floodlights.
#
# The lights are real Light2D nodes with shadows switched on, and every player
# carries a LightOccluder2D, so each one throws four shadows that fan out from
# the middle of the pitch — the look you get under real floodlights.

const FIELD_W: float = 896.0
const FIELD_H: float = 544.0
const PAD: float = 96.0            # stadium band width, matches stadium.png

const STADIUM_TEX := "res://art/field/stadium.png"
const TOWER_TEX := "res://art/props/floodlight.png"

@export var lights_on: bool = true
## How dark the pitch is before the floodlights hit it.
@export var night_tint: Color = Color(0.46, 0.50, 0.62)
## Brightness of each of the four towers.
@export var light_energy: float = 0.55
## How far each light reaches. 1.0 ≈ 256px radius.
@export var light_spread: float = 6.0
## Warmth of the floodlights.
@export var light_colour: Color = Color(1.0, 0.97, 0.88)
## 0 = no shadow, 1 = pitch black. Four overlapping shadows stack up, so keep it low.
@export var shadow_darkness: float = 0.38
@export var show_stadium: bool = true

var _lights: Array[PointLight2D] = []


func _ready() -> void:
	z_index = -20
	if show_stadium:
		_build_stadium()
	if lights_on:
		_build_night()
	_build_towers()
	_build_post_occluders()
	# Players are added to their groups in their own _ready, so wait a frame
	await get_tree().process_frame
	_fit_occluders()


# ---------------------------------------------------------------- stadium

func _build_stadium() -> void:
	if not ResourceLoader.exists(STADIUM_TEX):
		push_warning("Stadium texture missing: " + STADIUM_TEX)
		return
	var s := Sprite2D.new()
	s.name = "StadiumRing"
	s.texture = load(STADIUM_TEX)
	s.centered = false
	s.position = Vector2(-PAD, -PAD)
	s.z_as_relative = false
	s.z_index = -30
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)


func _build_night() -> void:
	var cm := CanvasModulate.new()
	cm.name = "NightTint"
	cm.color = night_tint
	add_child(cm)


# ---------------------------------------------------------------- lights

func _corner_positions() -> Array:
	# Just inside the stands, at the four corners of the pitch
	var m: float = 54.0
	return [
		Vector2(-m, -m),
		Vector2(FIELD_W + m, -m),
		Vector2(FIELD_W + m, FIELD_H + m),
		Vector2(-m, FIELD_H + m),
	]


func _light_texture() -> Texture2D:
	# A soft radial falloff, built in code so there's no extra asset to manage
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.42),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _build_towers() -> void:
	var centre := Vector2(FIELD_W * 0.5, FIELD_H * 0.5)
	var tex: Texture2D = load(TOWER_TEX) if ResourceLoader.exists(TOWER_TEX) else null
	var lt := _light_texture()

	for i in range(4):
		var pos: Vector2 = _corner_positions()[i]

		var tower := Node2D.new()
		tower.name = "Floodlight%d" % (i + 1)
		tower.position = pos
		add_child(tower)

		# The mast leans away from the middle of the pitch, as it would look
		# from a camera above the centre circle.
		if tex:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.rotation = (pos - centre).angle()
			spr.z_as_relative = false
			spr.z_index = -5
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tower.add_child(spr)

		if not lights_on:
			continue

		var light := PointLight2D.new()
		light.name = "Light"
		light.texture = lt
		light.texture_scale = light_spread
		light.energy = light_energy
		light.color = light_colour
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.shadow_enabled = true
		light.shadow_color = Color(0, 0, 0, shadow_darkness)
		light.shadow_filter = Light2D.SHADOW_FILTER_PCF13
		light.shadow_filter_smooth = 6.0
		# Sit the light out at the lamp head rather than the mast base
		light.position = (pos - centre).normalized() * 26.0
		tower.add_child(light)
		_lights.append(light)


# The goal posts throw shadows too — four small round feet on the try lines.
func _build_post_occluders() -> void:
	var spread: float = 20.0
	for x in [48.0, FIELD_W - 48.0]:
		for dy in [-spread, spread]:
			var occ := make_occluder(4.5)
			occ.name = "PostOccluder"
			occ.position = Vector2(x, FIELD_H * 0.5 + dy)
			add_child(occ)


# ---------------------------------------------------------------- occluders

# Give every player an occluder if their own script hasn't already.
func _fit_occluders() -> void:
	for grp in ["attackers", "defenders"]:
		for p in get_tree().get_nodes_in_group(grp):
			if p.get_node_or_null("Occluder") == null:
				p.add_child(make_occluder())


static func make_occluder(radius: float = 7.0) -> LightOccluder2D:
	var occ := LightOccluder2D.new()
	occ.name = "Occluder"
	var poly := OccluderPolygon2D.new()
	poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	var pts := PackedVector2Array()
	var r: float = radius
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		pts.append(Vector2(cos(a) * r, sin(a) * r * 0.85))
	poly.polygon = pts
	occ.occluder = poly
	return occ


# ---------------------------------------------------------------- runtime

## Switch the floodlights off/on (handy for a day match, or a title screen).
func set_lights(on: bool) -> void:
	lights_on = on
	for l in _lights:
		l.visible = on
	var cm := get_node_or_null("NightTint")
	if cm:
		cm.color = night_tint if on else Color.WHITE
