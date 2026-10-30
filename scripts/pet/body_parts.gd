class_name BodyParts
## Which part of her is under a point. Each region is a box fixed to a bone, so it
## follows the skeleton mid-animation (a raised hand is still a hand).
## spine-godot doesn't expose bounding-box attachment vertices to GDScript, so the boxes
## live here instead of in the skeleton file. They're in the bone's own space, Spine
## style (y up), matching the attachment offsets in waifu.spine-json.

## Checked in order, first hit wins: [part, bone, Rect2(x, bottom y, width, height)].
const REGIONS := [
	[&"hands", &"arm_l", Rect2(-10, -44, 20, 22)],
	[&"hands", &"arm_r", Rect2(-10, -44, 20, 22)],
	[&"face", &"head", Rect2(-28, -2, 56, 42)],
	[&"head", &"head", Rect2(-46, 40, 92, 56)],
	[&"chest", &"torso", Rect2(-22, 22, 44, 24)],
	[&"skirt", &"hip", Rect2(-36, -24, 72, 38)],
]

const BODY := &"body"


## The part of `sprite` at `point` (global coordinates), or &"body" for anything
## else. Callers check that the point is on her at all.
static func find(sprite: SpineSprite, point: Vector2) -> StringName:
	for region: Array in REGIONS:
		if Geometry2D.is_point_in_polygon(point, polygon(sprite, region[1], region[2])):
			return region[0]
	return BODY


## A region's box as a global polygon (also handy for drawing it while tuning).
static func polygon(sprite: SpineSprite, bone: StringName, box: Rect2) -> PackedVector2Array:
	var xform := sprite.get_global_bone_transform(bone)
	# Spine's y axis points up; the bone transform maps (x, -y) to the screen.
	return PackedVector2Array([
		xform * Vector2(box.position.x, -box.position.y),
		xform * Vector2(box.end.x, -box.position.y),
		xform * Vector2(box.end.x, -box.end.y),
		xform * Vector2(box.position.x, -box.end.y),
	])
