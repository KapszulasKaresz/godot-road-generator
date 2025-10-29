@tool
class_name RoadIntersectionProcedural
extends Node3D

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

@export var incoming_roads : Array[RoadPoint]:
		get:
			return incoming_roads
		set(value):
			incoming_roads = value
			_generate_mesh()
var incoming_roads_ordered : Array[RoadPoint]

@export var material : Material:
		get:
			return material
		set(value):
			material = value
			mesh_instance.material_override = material
	
@export var enable_smoothing : bool = false:
		get:
			return enable_smoothing
		set(value):
			enable_smoothing = value
			_generate_mesh()
	
@export var smoothing_resolution : float = 1:
		get:
			return smoothing_resolution
		set(value):
			smoothing_resolution = value
			_generate_mesh()
			
@export var manager :RoadManager = null 

var outline_points: PackedVector3Array = []
var final_outline_points: PackedVector3Array = []
var center_point : Vector3
var mesh_instance := MeshInstance3D.new()


func _ready() -> void:
	if manager == null:
		manager = get_parent()
	manager.on_road_updated.connect(_on_road_updated)
	add_child(mesh_instance)
	mesh_instance.material_override = material

func _generate_mesh() -> void:
	outline_points.clear()
	final_outline_points.clear()
	incoming_roads_ordered.clear()
	center_point = Vector3(0,0,0)
	if incoming_roads.size() >= 2:
		for road in incoming_roads:
			center_point = center_point + road.position
		center_point = center_point / incoming_roads.size()
		incoming_roads_ordered = sort_road_points_clockwise(incoming_roads, center_point)
		self.position = center_point
		
		for road in incoming_roads_ordered:
			var pos = road.position - center_point
			var right :Vector3 = road.basis.x
			var left :Vector3 = -road.basis.x
			var point_left :Vector3 = pos + left * (road.lane_width * road.lanes.size() / 2.0 + road.shoulder_width_l)
			var point_right :Vector3 = pos + right * (road.lane_width * road.lanes.size() / 2.0 + road.shoulder_width_r)
			var angle_left := atan2(point_left.z, point_left.x)
			var angle_right := atan2(point_right.z, point_right.x)
			if angle_left > angle_right:
				outline_points.append(point_left)
				outline_points.append(point_right)
			else:
				outline_points.append(point_right)
				outline_points.append(point_left)
		if enable_smoothing:
			for i in range(incoming_roads_ordered.size()):
				var index_a = 2 * i + 1
				var index_b = (2 * i + 2) % outline_points.size()
				var a = outline_points[index_a]
				var b = outline_points[index_b]
				var c = a.lerp(b, 0.5).lerp(Vector3(0,0,0), 0.3)
				var point_count : int = a.distance_to(b) * smoothing_resolution
				var smoothened_points = bezier_quadratic(a, c, b, point_count + 1)
				final_outline_points.append_array(smoothened_points)
		else:
			final_outline_points = outline_points.duplicate()
		mesh_instance.mesh = create_triangle_fan_mesh(final_outline_points, Vector3(0,0,0))
	pass

func create_triangle_fan_mesh(outline_points: PackedVector3Array, center_point: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var num_points := outline_points.size()
	if num_points < 3:
		push_error("Need at least 3 outline points to make a fan.")
		return null

	# Build triangles around the center
	for i in range(num_points):
		var p1 := outline_points[i]
		var p2 := outline_points[(i + 1) % num_points] # wrap around

		# Triangle: center -> p1 -> p2
		st.add_vertex(center_point)
		st.add_vertex(p2)
		st.add_vertex(p1)
	
	st.index()
	var mesh := st.commit()
	return mesh


func sort_road_points_clockwise(points: Array[RoadPoint], center : Vector3) -> Array[RoadPoint]:
	if points.size() < 3:
		return points

	var points_with_angles := []

	for p in points:
		var angle := atan2(p.position.z - center.z, p.position.x - center.x)
		points_with_angles.append({"point": p, "angle": angle})

	# Sort by angle in descending order for clockwise (ascending for CCW)
	points_with_angles.sort_custom(func(a, b):
		return a["angle"] > b["angle"]
	)

	var sorted_points : Array[RoadPoint]
	for item in points_with_angles:
		sorted_points.append(item["point"])

	return sorted_points

func bezier_quadratic(a: Vector3, c: Vector3, b: Vector3, segments: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(c, t).lerp(c.lerp(b, t), t)
		result.append(p)
	return result

func _on_road_updated(updated_segments: Array):
	for segment in updated_segments:
		if incoming_roads.has(segment.start_point) or incoming_roads.has(segment.end_point):
			_generate_mesh()
