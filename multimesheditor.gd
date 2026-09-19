@tool
extends EditorPlugin

const MULTI_MESH_EDITOR = preload("./assets/multi_mesh_editor.tscn")
const MULTI_MESH_PREVIEW = preload("./assets/preview.tscn")
const SPHERE_MAT = preload("./assets/preview.material")

var ui_container: Control
var selected_multimesh_instance: MultiMeshInstance3D
var selected_multimesh: MultiMesh
var last_buffer: PackedFloat32Array
var last_instance_count: int

var preview_mesh: MeshInstance3D

var remove_active: bool = false
var s_key_pressed: bool = false
var left_click_pressed: bool = false
var remove_radius: float = 2

func _enable_plugin() -> void:
	pass


func _disable_plugin() -> void:
	pass


func _handles(object: Object) -> bool:
	return object is MultiMeshInstance3D


func _edit(object: Object) -> void:
	if object == null or object.multimesh == null:
		stop_edit()
		return
	
	selected_multimesh_instance = object
	selected_multimesh = object.multimesh
	start_edit()

func start_edit() -> void:
	ui_container.show()

func lock_multimesh_node() -> void:
	selected_multimesh_instance.set_meta("_edit_lock_", true)
	selected_multimesh_instance.update_gizmos()
	selected_multimesh_instance.clear_gizmos()
	selected_multimesh_instance.clear_subgizmo_selection()
	selected_multimesh_instance.update_gizmos()

func unlock_multimesh_node() -> void:
	selected_multimesh_instance.remove_meta("_edit_lock_")
	selected_multimesh_instance.update_gizmos()
	selected_multimesh_instance.clear_gizmos()
	selected_multimesh_instance.clear_subgizmo_selection()
	selected_multimesh_instance.update_gizmos()

func start_edit_action() -> void:
	remove_active = !remove_active
	ui_container.get_node("%EditButton").flat = !remove_active
	if remove_active:
		last_buffer = selected_multimesh.buffer
		last_instance_count = selected_multimesh.instance_count
		lock_multimesh_node()
	else:
		preview_mesh.hide()
		unlock_multimesh_node()

func apply_remove_action(target_position: Vector3) -> void:
	var _buffer: PackedFloat32Array = selected_multimesh.buffer
	var indexes_to_remove: Array[int] = []
	var data_size = _buffer.size() / selected_multimesh.instance_count
	for i in selected_multimesh.instance_count:
		var t = selected_multimesh.get_instance_transform(i)
		var d = selected_multimesh_instance.to_global(t.origin).distance_to(target_position)
		if d > remove_radius / 2:
			continue
		
		#selected_multimesh.set_instance_transform(i, t.scaled(Vector3(1, 20, 1)))
		#print(t.origin, ' - ', d)
		var instance_buffer_start = i * data_size
		indexes_to_remove.push_back(instance_buffer_start)
	
	indexes_to_remove.sort()
	var removed_offset = 0
	for start_i in indexes_to_remove:
		var instance_buffer_end = start_i + data_size
		for j in range(data_size):
			_buffer.remove_at(start_i - removed_offset)
		removed_offset += data_size
	
	var m_rid = selected_multimesh.get_rid()
	var new_instance_count = _buffer.size() / data_size
	
	#print("removed %d instances from multimesh." % [indexes_to_remove.size()])
	#print("%d - %d - %d - %d" % [_buffer.size(), new_instance_count, data_size, remove_radius])
	
	RenderingServer.multimesh_allocate_data(
		m_rid,
		new_instance_count,
		RenderingServer.MULTIMESH_TRANSFORM_3D,
		false, false)

	RenderingServer.multimesh_set_buffer(m_rid, _buffer)
	selected_multimesh.instance_count = new_instance_count
	selected_multimesh.buffer = _buffer


func _get_basis_from_normal(normal : Vector3) -> Basis:
	var basis = Basis.IDENTITY
	basis.y = normal
	if normal.abs() != basis.z.abs(): basis.x = -basis.z.cross(normal)
	else: basis.z = basis.x.cross(normal)
	return basis.orthonormalized()


func process_scroll_event(event: InputEventMouseButton) -> int:
	if event.shift_pressed and s_key_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			remove_radius = min(remove_radius + .1, 30)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			remove_radius = max(.2, remove_radius - .1)
		preview_mesh.scale = Vector3.ONE * remove_radius
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	var is_left_click : bool = event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT && event.pressed
	
	if event is InputEventKey and event.keycode == KEY_S:
		s_key_pressed = event.pressed
	
	if not event is InputEventMouse:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	if event is InputEventMouseButton:
		left_click_pressed = is_left_click
		
	if not is_left_click and event is InputEventMouseButton:
		return process_scroll_event(event)
	
	if not remove_active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	var ray_cast_start : Vector3 = viewport_camera.global_position
	var ray_cast_end : Vector3 = viewport_camera.global_position + viewport_camera.project_ray_normal(event.position) * 100.0
	var space_state : PhysicsDirectSpaceState3D = selected_multimesh_instance.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_cast_start, ray_cast_end, 1)
	var ray_cast_result = space_state.intersect_ray(query)
	preview_mesh.visible = ray_cast_result != {}
	if !ray_cast_result: 
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var target_transform : Transform3D = Transform3D(_get_basis_from_normal(ray_cast_result.normal), ray_cast_result.position)

	preview_mesh.transform = target_transform
	preview_mesh.scale = Vector3.ONE * remove_radius
	target_transform = selected_multimesh_instance.global_transform.inverse() * target_transform
	
	if !left_click_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
		
	apply_remove_action(preview_mesh.global_position)

	return EditorPlugin.AFTER_GUI_INPUT_STOP

func start_revert_action() -> void:
	var m_rid = selected_multimesh.get_rid()
	var data_size = last_buffer.size() / last_instance_count
	var new_instance_count = last_buffer.size() / data_size
	
	RenderingServer.multimesh_allocate_data(
		m_rid,
		new_instance_count,
		RenderingServer.MULTIMESH_TRANSFORM_3D,
		false, false)

	RenderingServer.multimesh_set_buffer(m_rid, last_buffer)
	selected_multimesh.instance_count = new_instance_count
	selected_multimesh.buffer = last_buffer

func stop_edit() -> void:
	if ui_container == null:
		return
	
	ui_container.hide()
	pass

func _enter_tree() -> void:
	ui_container = MULTI_MESH_EDITOR.instantiate()
	ui_container.get_node("%EditButton").pressed.connect(start_edit_action)
	ui_container.get_node("%RevertButton").pressed.connect(start_revert_action)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, ui_container)
	ui_container.hide()
	
	preview_mesh = MeshInstance3D.new()
	get_tree().root.call_deferred("add_child", preview_mesh)
	preview_mesh.mesh = SphereMesh.new()
	preview_mesh.mesh.radial_segments = 32
	preview_mesh.mesh.rings = 16
	preview_mesh.material_override = SPHERE_MAT
	preview_mesh.scale = Vector3.ONE * remove_radius
	preview_mesh.hide()
	
	pass


func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, ui_container)
	ui_container.queue_free()
	preview_mesh.queue_free()
	pass
