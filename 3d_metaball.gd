extends Node2D

signal gpu_sync(texture: ImageTexture)

@export var camera: Camera3D
@export var shader_file: Resource
# Spheres: [<x, y, z>, radius, <r, g, b>]
@export var sphere_arrays: Array[Array] = [
	#[Vector3(-1, -1, -5), 0.5, Vector3(1, 0, 0.5)],
	#[Vector3(-1, 0, -5), 0.5, Vector3(1, 0.5, 0.5)],
	#[Vector3(-1, 1, -5), 0.5, Vector3(1, 1, 0.5)],
	#[Vector3(0, -1, -5), 0.5, Vector3(0.5, 0, 0.5)],
	#[Vector3(0, 0, -5), 0.5, Vector3(0.5, 0.5, 0.5)],
	#[Vector3(0, 1, -5), 0.5, Vector3(0.5, 1, 0.5)],
	#[Vector3(1, -1, -5), 0.5, Vector3(0, 0, 0.5)],
	#[Vector3(1, 0, -5), 0.5, Vector3(0, 0.5, 0.5)],
	#[Vector3(1, 1, -5), 0.5, Vector3(0, 1, 0.5)],
]
# Each node: [<x, y, z>, <sizeX, sizeY, sizeZ>, sphereIndex, leftNodeIndex, rightNodeIndex]
@export var bvh_tree: Array[Array] = [
	#[Vector3(-1.5, -1.5, -5.5), Vector3(3, 3, 1), -1, 1, 6],
	#[Vector3(-1.5, -1.5, -5.5), Vector3(1, 3, 1), -1, 2, 3],
	#[Vector3(-1.5, -1.5, -5.5), Vector3(1, 1, 1), 0, -1, -1],
	#[Vector3(-1.5, -0.5, -5.5), Vector3(1, 2, 1), -1, 4, 5],
	#[Vector3(-1.5, -0.5, -5.5), Vector3(1, 1, 1), 1, -1, -1],
	#[Vector3(-1.5, 0.5, -5.5), Vector3(1, 1, 1), 2, -1, -1],
	#[Vector3(-0.5, -1.5, -5.5), Vector3(2, 3, 1), -1, 7, 12],
	#[Vector3(-0.5, -1.5, -5.5), Vector3(1, 3, 1), -1, 8, 9],
	#[Vector3(-0.5, -1.5, -5.5), Vector3(1, 1, 1), 3, -1, -1],
	#[Vector3(-0.5, -0.5, -5.5), Vector3(1, 2, 1), -1, 10, 11],
	#[Vector3(-0.5, -0.5, -5.5), Vector3(1, 1, 1), 4, -1, -1],
	#[Vector3(-0.5, 0.5, -5.5), Vector3(1, 1, 1), 5, -1, -1],
	#[Vector3(0.5, -1.5, -5.5), Vector3(1, 3, 1), -1, 13, 14],
	#[Vector3(0.5, -1.5, -5.5), Vector3(1, 1, 1), 6, -1, -1],
	#[Vector3(0.5, -0.5, -5.5), Vector3(1, 2, 1), -1, 15, 16],
	#[Vector3(0.5, -0.5, -5.5), Vector3(1, 1, 1), 7, -1, -1],
	#[Vector3(0.5, 0.5, -5.5), Vector3(1, 1, 1), 8, -1, -1],
]
@export var grid_size: Vector3 = Vector3(4, 4, 1)
# Lights: [<x, y, z>, brigtness]
@export var light_arrays: Array[Array] = [
	[Vector3(0, 0, 0), 4],
]
@export var image_size: Vector2i = Vector2i(1000, 1000)

# How many frames to wait before sync
const GPU_SYNC_WAIT = 0

# GPU Stuff
@onready var _tree: SceneTree = get_tree()
var _shader_spirv: RDShaderSPIRV
var rd: RenderingDevice

# Modifies bvh_tree
# Returns a bvh index
func generate_bvh_grid(size: Vector3, base_pos: Vector3, sphere_indices: Array[int]) -> int:
	if size.x == 1 and size.y == 1 and size.z == 1:
		bvh_tree.append([base_pos - Vector3(0.5, 0.5, 0.5), size, sphere_indices[0], -1, -1])
		return bvh_tree.size() - 1
	else:
		var index: int = bvh_tree.size()
		bvh_tree.append([base_pos - Vector3(0.5, 0.5, 0.5), size, -1, -1, -1])
		
		var left_size: Vector3
		var left_position: Vector3 = base_pos
		var right_size: Vector3
		var right_position: Vector3
		if size.z >= size.y and size.z >= size.x:
			left_size = Vector3(size.x, size.y, floor(size.z/2))
			right_size = Vector3(size.x, size.y, ceil(size.z/2))
			right_position = base_pos + Vector3(0, 0, floor(size.z/2))
		elif size.y >= size.x:
			left_size = Vector3(size.x, floor(size.y/2), size.z)
			right_size = Vector3(size.x, ceil(size.y/2), size.z)
			right_position = base_pos + Vector3(0, floor(size.y/2), 0)
		else:
			left_size = Vector3(floor(size.x/2), size.y, size.z)
			right_size = Vector3(ceil(size.x/2), size.y, size.z)
			right_position = base_pos + Vector3(floor(size.x/2), 0, 0)
		
		var left_sphere_indices: Array[int]
		var right_sphere_indices: Array[int]
		for sphere_index in sphere_indices:
			var sphere_array = sphere_arrays[sphere_index]
			if sphere_array[0].x >= left_position.x and sphere_array[0].x < left_position.x + left_size.x \
					and sphere_array[0].y >= left_position.y and sphere_array[0].y < left_position.y + left_size.y \
					and sphere_array[0].z >= left_position.z and sphere_array[0].z < left_position.z + left_size.z:
				left_sphere_indices.append(sphere_index)
			else:
				right_sphere_indices.append(sphere_index)
		
		bvh_tree[index][3] = generate_bvh_grid(left_size, left_position, left_sphere_indices)
		bvh_tree[index][4] = generate_bvh_grid(right_size, right_position, right_sphere_indices)
		
		return index
func generate_sphere_grid(size: Vector3, position: Vector3) -> Array[int]:
	var sphere_indices: Array[int] = []
	for i in range(size.x):
		for j in range(size.y):
			for k in range(size.z):
				sphere_indices.append(sphere_arrays.size())
				sphere_arrays.append([Vector3(position.x + i, position.y + j, position.z + k), 
					0.5, Vector3(float(i)/size.x, float(j)/size.y, float(k)/size.z)])
	return sphere_indices
var image_buffer: RID
var image_size_buffer: RID
var camera_to_world_buffer: RID
var camera_inverse_projection_buffer: RID
var lights_buffer: RID
var spheres_buffer: RID
var bvh_nodes_buffer: RID
func get_camera_to_world_data() -> PackedFloat32Array:
	var matrix_data = PackedFloat32Array()
	
	matrix_data.resize(16)
	# Fill basis (3x3 part)
	matrix_data[0] = camera.global_basis.x.x
	matrix_data[1] = camera.global_basis.x.y
	matrix_data[2] = camera.global_basis.x.z
	matrix_data[3] = 0.0

	matrix_data[4] = camera.global_basis.y.x
	matrix_data[5] = camera.global_basis.y.y
	matrix_data[6] = camera.global_basis.y.z
	matrix_data[7] = 0.0

	matrix_data[8] = camera.global_basis.z.x
	matrix_data[9] = camera.global_basis.z.y
	matrix_data[10] = camera.global_basis.z.z
	matrix_data[11] = 0.0

	# Fill origin (translation part)
	matrix_data[12] = camera.global_position.x
	matrix_data[13] = camera.global_position.y
	matrix_data[14] = camera.global_position.z
	matrix_data[15] = 1.0
	
	return matrix_data
func get_camera_inverse_projection_data(projection_matrix: Projection) -> PackedFloat32Array:
	var inverse_projection_matrix = projection_matrix.inverse()
	
	var matrix_data = PackedFloat32Array()
	matrix_data.resize(16)
	
	matrix_data[0] = inverse_projection_matrix.x.x
	matrix_data[1] = inverse_projection_matrix.x.y
	matrix_data[2] = inverse_projection_matrix.x.z
	matrix_data[3] = inverse_projection_matrix.x.w
	
	matrix_data[4] = inverse_projection_matrix.y.x
	matrix_data[5] = inverse_projection_matrix.y.y
	matrix_data[6] = inverse_projection_matrix.y.z
	matrix_data[7] = inverse_projection_matrix.y.w
	
	matrix_data[8] = inverse_projection_matrix.z.x
	matrix_data[9] = inverse_projection_matrix.z.y
	matrix_data[10] = inverse_projection_matrix.z.z
	matrix_data[11] = inverse_projection_matrix.z.w
	
	matrix_data[12] = inverse_projection_matrix.w.x
	matrix_data[13] = inverse_projection_matrix.w.y
	matrix_data[14] = inverse_projection_matrix.w.z
	matrix_data[15] = inverse_projection_matrix.w.w
	
	return matrix_data
func init_buffer_data():
	var rd_texture_format = RDTextureFormat.new()
	rd_texture_format.width = image_size.x
	rd_texture_format.height = image_size.y
	rd_texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	rd_texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	image_buffer = rd.texture_create(rd_texture_format, RDTextureView.new())
	
	var image_size_byte_array = PackedFloat32Array([image_size.x, image_size.y, 0, 0]).to_byte_array()
	image_size_buffer = rd.uniform_buffer_create(image_size_byte_array.size(), image_size_byte_array)
	
	var camera_to_world_data = get_camera_to_world_data().to_byte_array()
	camera_to_world_buffer = rd.uniform_buffer_create(camera_to_world_data.size(), camera_to_world_data)
	
	var camera_inverse_projection_data = get_camera_inverse_projection_data(camera.get_camera_projection()).to_byte_array()
	camera_inverse_projection_buffer = rd.uniform_buffer_create(camera_inverse_projection_data.size(), camera_inverse_projection_data)
	
	var packed_lights_arrays = PackedFloat32Array()
	for light_array in light_arrays:
		for val in light_array:
			if val is float or val is int:
				packed_lights_arrays.append(val)
			elif val is Vector3:
				packed_lights_arrays.append_array(PackedFloat32Array([val.x, val.y, val.z]))
	var lights_data = packed_lights_arrays.to_byte_array()
	lights_buffer = rd.storage_buffer_create(lights_data.size(), lights_data)
	
	var packed_sphere_arrays = PackedFloat32Array()
	for sphere_array in sphere_arrays:
		for val in sphere_array:
			if val is float or val is int:
				packed_sphere_arrays.append(val)
			elif val is Vector3:
				packed_sphere_arrays.append_array(PackedFloat32Array([val.x, val.y, val.z]))
		# Add padding byte
		packed_sphere_arrays.append(0)
	var spheres_data = packed_sphere_arrays.to_byte_array()
	spheres_buffer = rd.storage_buffer_create(spheres_data.size(), spheres_data)
	
	var packed_bvh_tree = PackedFloat32Array()
	for bvh_node in bvh_tree:
		packed_bvh_tree.append_array(PackedFloat32Array([bvh_node[0].x, bvh_node[0].y, bvh_node[0].z]))
		packed_bvh_tree.append(0)
		packed_bvh_tree.append_array(PackedFloat32Array([bvh_node[1].x, bvh_node[1].y, bvh_node[1].z]))
		packed_bvh_tree.append(0)
		packed_bvh_tree.append_array(PackedFloat32Array([bvh_node[2], bvh_node[3], bvh_node[4]]))
		packed_bvh_tree.append(0)
	var bvh_tree_data = packed_bvh_tree.to_byte_array()
	bvh_nodes_buffer = rd.storage_buffer_create(bvh_tree_data.size(), bvh_tree_data)

func _ready() -> void:
	if sphere_arrays.size() == 0:
		generate_bvh_grid(Vector3(grid_size), Vector3(-1, -1, -5), \
			generate_sphere_grid(Vector3(grid_size), Vector3(-1, -1, -5)))
	print(bvh_tree)
	
	_shader_spirv = shader_file.get_spirv()
	rd = RenderingServer.create_local_rendering_device()
	init_buffer_data()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var camera_to_world_data = get_camera_to_world_data().to_byte_array()
	camera_to_world_buffer = rd.uniform_buffer_create(camera_to_world_data.size(), camera_to_world_data)
	
	var camera_inverse_projection_data = get_camera_inverse_projection_data(camera.get_camera_projection()).to_byte_array()
	camera_inverse_projection_buffer = rd.uniform_buffer_create(camera_inverse_projection_data.size(), camera_inverse_projection_data)
	run_shader()


# Emits a signal 
func run_shader() -> void:
	# Create a local rendering device.
	var shader = rd.shader_create_from_spirv(_shader_spirv)
	
	# Create a compute pipeline
	var pipeline := rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Add buffer data
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_IMAGE, image_buffer, 0)
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, image_size_buffer, 1)
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, camera_to_world_buffer, 2)
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, camera_inverse_projection_buffer, 3)
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, lights_buffer, 4)
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, spheres_buffer, 5)
	add_buffer(compute_list, shader, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, bvh_nodes_buffer, 6)
	
	rd.compute_list_dispatch(compute_list, image_size.x, image_size.y, 1)
	rd.compute_list_end()
	
	# Submit to GPU
	rd.submit()
	# Wait GPU_SYNC_WAIT frames
	for i in range(GPU_SYNC_WAIT):
		await _tree.process_frame
	rd.sync()
	
	# Read back the data from the buffer
	var image_data = rd.texture_get_data(image_buffer, 0)
	var new_image = Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBAF, image_data)
	gpu_sync.emit(ImageTexture.create_from_image(new_image))
	

func add_buffer(compute_list: int, shader: RID, uniform_type: RenderingDevice.UniformType, rid: RID, binding: int) -> void:
	# Create a uniform to assign the buffer to the rendering device
	var uniform := RDUniform.new()
	uniform.uniform_type = uniform_type
	uniform.binding = binding # this needs to match the "binding" in our shader file
	uniform.add_id(rid)
	var uniform_set := rd.uniform_set_create([uniform], shader, binding) # the last parameter (the 0) needs to match the "set" in our shader file
	
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, binding)
