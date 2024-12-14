#[compute]
#version 450

// Constants (adjust as needed)
#define MAX_DISTANCE 200
#define MIN_DISTANCE 0.01
// a lower max_steps and outline_min_steps results in a thicker outline
#define MAX_STEPS 40
// outline_min_steps is for outline to be slightly blurred
#define OUTLINE_MIN_STEPS 25
#define DRAW_OUTLINE true

// Structs
struct Ray {
    vec3 origin;
    vec3 direction;
};
struct Sphere {
	vec3 position;
	float radius;
	vec3 color;
	// float paddingByte;
};

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) writeonly uniform image2D output_texture;

// NOTE: output_resolution should be the same as gl_GlobalInvocationID
layout(set = 1, binding = 1) uniform OutputResolution {
	vec2 vector;
	// float paddingByte1;
	// float paddingByte2;
} output_resolution;

layout(set = 2, binding = 2) uniform CameraToWorld {
	mat4 matrix;
} camera_to_world;
layout(set = 3, binding = 3) uniform CameraInverseProjection {
	mat4 matrix;
} camera_inverse_projection;

layout(set = 4, binding = 4, std430) readonly buffer SphereBuffer {
	Sphere spheres[];
} sphere_buffer;


// Helper functions (most from https://github.com/SebLague/Ray-Marching/blob/master/Assets/Scripts/SDF/Raymarching.compute)
float sphereDistance(vec3 eye, vec3 centre, float radius) {
    return distance(eye, centre) - radius;
}
// polynomial smooth min (k = 0.1);
// from https://www.iquilezles.org/www/articles/smin/smin.htm
vec4 blend(float a, float b, vec3 colA, vec3 colB, float k ) {
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    float blendDst = mix( b, a, h ) - k*h*(1.0-h);
    vec3 blendCol = mix(colB,colA,h);
    return vec4(blendCol, blendDst);
}
// returns color, distance
vec4 getSceneInfo(vec3 eye) {
	if (sphere_buffer.spheres.length() == 0) { return vec4(0, 0, 0, MAX_DISTANCE); }

	// blend all spheres
	Sphere sphere = sphere_buffer.spheres[0];
	vec4 currentBlend = vec4(sphere.color, sphereDistance(eye, sphere.position, sphere.radius));
	for (int i = 1; i < sphere_buffer.spheres.length(); i++) {
		Sphere sphere = sphere_buffer.spheres[i];
		float distance = sphereDistance(eye, sphere.position, sphere.radius);
		currentBlend = blend(currentBlend.w, distance, currentBlend.rgb, sphere.color, 0.5);
	}
	return currentBlend;
}
Ray createRay(vec3 origin, vec3 direction) {
    Ray ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}
Ray createCameraRay(vec2 uv) {
    vec3 origin = (camera_to_world.matrix * vec4(0,0,0,1)).xyz;
    vec3 direction = (camera_inverse_projection.matrix * vec4(uv,0,1)).xyz;
    direction = (camera_to_world.matrix * vec4(direction,0)).xyz;
    direction = normalize(direction);
    return createRay(origin,direction);
}


// The code we want to execute in each invocation
void main() {
	// normalize the uv coordinates to be between -1 and 1
	vec2 uv = gl_GlobalInvocationID.xy / vec2(output_resolution.vector) * 2 - 1;

	Ray ray = createCameraRay(uv);
	vec4 sceneInfo = getSceneInfo(ray.origin);
	float rayDistance = sceneInfo.w;
	int numSteps = 0;
	// ray march
	while (rayDistance <= MAX_DISTANCE && numSteps < MAX_STEPS && abs(sceneInfo.a) >= MIN_DISTANCE) {
		sceneInfo = getSceneInfo(ray.origin);
		ray.origin += ray.direction * sceneInfo.w;
		rayDistance += sceneInfo.w;
		numSteps++;
	}

	// if we have hit something, write the color to the output texture
	if (sceneInfo.a < MIN_DISTANCE) {
		imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4(sceneInfo.rgb, 1));
	}
	// if we have hit the maximum number of steps, write white (outlines the object)
	else if (numSteps >= OUTLINE_MIN_STEPS && DRAW_OUTLINE) {
		imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4(0, 1, 0, 1.0 * (numSteps - OUTLINE_MIN_STEPS) / (MAX_STEPS - OUTLINE_MIN_STEPS)));
	}
	// if we have not hit anything, write transparent to the output texture
	else {
		imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4(0, 0, 0, 0));
	}
}
