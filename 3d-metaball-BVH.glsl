#[compute]
#version 450

// Constants (adjust as needed)
#define NOISE_MULTIPLIER 0

// used for stopping ray march
#define MAX_DISTANCE 100
#define MIN_DISTANCE 0.001

// Shadow offset is how far to move the shadow ray origin from surface to avoid self-shadowing
#define SHADOW_OFFSET_MULTIPLIER 50
#define AMBIENT_LIGHT 0.15 // 0 to 1

#define DRAW_OUTLINE true
#define OUTLINE_COLOR vec3(1, 1, 0.8)
// a lower max_steps and outline_min_steps results in a thicker outline
// outline is blurred between outline_min_steps and max_steps
#define MAX_STEPS 45
#define OUTLINE_MIN_STEPS 25
// how many steps to offset if overlay is over existing object
#define OUTLINE_OVERLAY_STEP_OFFSET (-10)
// outline falloff is how quickly the outline fades out (higher is faster)
#define OUTLINE_FALLOFF 2

// Maximum number of possible recursions for BVH tree
#define MAX_RECURSION_DEPTH 128
// how much to expand BVH bounds by, to account for object blending
#define BVH_BOUNDS_OFFSET 1
// maximum number of intersecting spheres to check
#define MAX_INTERSECT_SPHERES 128


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
struct RectangularPrism {
	vec3 position;
	// float paddingByte1;
	vec3 size;
	// float paddingByte2;
};
struct Light {
	vec3 position;
	float intensity;
};
struct BVHNode {
	RectangularPrism bounds;
	// if objectIndex is not -1, then leftNodeIndex and rightNodeIndex are ignored
	float objectIndex;
	float leftNodeIndex;
	float rightNodeIndex;
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

layout(set = 4, binding = 4, std430) readonly buffer LightBuffer {
	Light lights[];
} light_buffer;

layout(set = 5, binding = 5, std430) readonly buffer SphereBuffer {
	Sphere spheres[];
} sphere_buffer;

// base BVHNode should be at index 0
layout(set = 6, binding = 6, std430) readonly buffer BVHNodeBuffer {
	BVHNode nodes[];
} bvh_node_buffer;


// Helper functions (most from https://github.com/SebLague/Ray-Marching/blob/master/Assets/Scripts/SDF/Raymarching.compute)
float rand(vec2 co){
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}
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
// copilot code
bool doesIntersect(Ray ray, RectangularPrism prism, float offset) {
	vec3 invDir = 1.0 / ray.direction;
	vec3 t0s = ((prism.position - offset) - ray.origin) * invDir;
	vec3 t1s = ((prism.position - offset) + (prism.size + 2 * offset) - ray.origin) * invDir;
	vec3 tsmall = min(t0s, t1s);
	vec3 tbig = max(t0s, t1s);
	float tmin = max(max(tsmall.x, tsmall.y), tsmall.z);
	float tmax = min(min(tbig.x, tbig.y), tbig.z);
	return tmax >= tmin;
}
bool doesIntersect(vec3 point, RectangularPrism prism, float offset) {
	return point.x >= prism.position.x - offset && point.x <= prism.position.x + prism.size.x + offset &&
		point.y >= prism.position.y - offset && point.y <= prism.position.y + prism.size.y + offset &&
		point.z >= prism.position.z - offset && point.z <= prism.position.z + prism.size.z + offset;
}
void getIntersectSpheres(Ray ray, out int sphereIndexes[MAX_INTERSECT_SPHERES], out int sphereCount) {
	int stack[MAX_RECURSION_DEPTH];
	int stackIndex = 0;
	stack[stackIndex] = 0;
	sphereCount = 0;

	while (stackIndex >= 0 && stackIndex < MAX_RECURSION_DEPTH && sphereCount < sphereIndexes.length()) {
		BVHNode currentNode = bvh_node_buffer.nodes[stack[stackIndex]];
		stackIndex--;
		if (doesIntersect(ray, currentNode.bounds, BVH_BOUNDS_OFFSET)) {
			if (currentNode.objectIndex >= 0) {
				sphereIndexes[sphereCount] = int(round(currentNode.objectIndex));
				sphereCount++;
			}
			else {
				if (currentNode.leftNodeIndex >= 0) { stack[++stackIndex] = int(round(currentNode.leftNodeIndex)); }
				if (currentNode.rightNodeIndex >= 0) { stack[++stackIndex] = int(round(currentNode.rightNodeIndex)); }
			}
		}
	}
}
void getIntersectSpheres(vec3 point, out int sphereIndexes[MAX_INTERSECT_SPHERES], out int sphereCount) {
	int stack[MAX_RECURSION_DEPTH];
	int stackIndex = 0;
	stack[stackIndex] = 0;
	sphereCount = 0;

	while (stackIndex >= 0 && stackIndex < MAX_RECURSION_DEPTH && sphereCount < sphereIndexes.length()) {
		BVHNode currentNode = bvh_node_buffer.nodes[stack[stackIndex]];
		stackIndex--;
		if (doesIntersect(point, currentNode.bounds, BVH_BOUNDS_OFFSET)) {
			if (currentNode.objectIndex >= 0) {
				sphereIndexes[sphereCount] = int(round(currentNode.objectIndex));
				sphereCount++;
			}
			else {
				if (currentNode.leftNodeIndex >= 0) { stack[++stackIndex] = int(round(currentNode.leftNodeIndex)); }
				if (currentNode.rightNodeIndex >= 0) { stack[++stackIndex] = int(round(currentNode.rightNodeIndex)); }
			}
		}
	}
}
// returns color, distance
vec4 getSceneInfo(vec3 eye, int sphereIndexes[MAX_INTERSECT_SPHERES], int sphereCount) {
	if (sphereCount == 0) { return vec4(0, 0, 0, MAX_DISTANCE); }

	// blend all spheres
	Sphere sphere = sphere_buffer.spheres[sphereIndexes[0]];
	vec4 currentBlend = vec4(sphere.color, sphereDistance(eye, sphere.position, sphere.radius));
	for (int i = 1; i < sphereCount; i++) {
		Sphere sphere = sphere_buffer.spheres[sphereIndexes[i]];
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
	origin += rand(uv + origin.xy + origin.yz + direction.xy + direction.yz) * 0.001 * NOISE_MULTIPLIER;
    return createRay(origin,direction);
}
vec3 estimateNormal(vec3 p) {
	int sphereIndexes[MAX_INTERSECT_SPHERES];
	int sphereCount = 0;
	getIntersectSpheres(p, sphereIndexes, sphereCount);

	float epsilon = SHADOW_OFFSET_MULTIPLIER * MIN_DISTANCE;
    float x = getSceneInfo(vec3(p.x+epsilon,p.y,p.z), sphereIndexes, sphereCount).w - getSceneInfo(vec3(p.x-epsilon,p.y,p.z), sphereIndexes, sphereCount).w;
    float y = getSceneInfo(vec3(p.x,p.y+epsilon,p.z), sphereIndexes, sphereCount).w - getSceneInfo(vec3(p.x,p.y-epsilon,p.z), sphereIndexes, sphereCount).w;
    float z = getSceneInfo(vec3(p.x,p.y,p.z+epsilon), sphereIndexes, sphereCount).w - getSceneInfo(vec3(p.x,p.y,p.z-epsilon), sphereIndexes, sphereCount).w;
    return normalize(vec3(x,y,z));
}
float calculateBrightness(vec3 origin) {
	vec3 normal = estimateNormal(origin);
	origin += normal * MIN_DISTANCE * SHADOW_OFFSET_MULTIPLIER;

	float shadow = 1 - AMBIENT_LIGHT;
	for (int i = 0; i < light_buffer.lights.length(); i ++) {
		Light light = light_buffer.lights[i];
		vec3 lightDirection = normalize(light.position - origin);
		float lightDistance = distance(origin, light.position);
		Ray shadowRay = createRay(origin, lightDirection);
		int sphereIndexes[MAX_INTERSECT_SPHERES];
		int sphereCount = 0;
		getIntersectSpheres(shadowRay, sphereIndexes, sphereCount);

		// ray march towards light
		vec4 sceneInfo = getSceneInfo(shadowRay.origin, sphereIndexes, sphereCount);
		float rayDistance = sceneInfo.w;
		// brightness multiplier is used to add shadow blur
		float brightnessMultiplier = min(1, sceneInfo.w / (MIN_DISTANCE * SHADOW_OFFSET_MULTIPLIER));
		while (sceneInfo.w >= MIN_DISTANCE && rayDistance < lightDistance) {
			shadowRay.origin += shadowRay.direction * sceneInfo.w;
			sceneInfo = getSceneInfo(shadowRay.origin, sphereIndexes, sphereCount);
			brightnessMultiplier = min(brightnessMultiplier, sceneInfo.w / (MIN_DISTANCE * SHADOW_OFFSET_MULTIPLIER));
			rayDistance += sceneInfo.w;
		}
		if (rayDistance >= lightDistance) {
			shadow *= max(1 - (max(dot(normal, lightDirection), 0) * brightnessMultiplier * light.intensity), 0);
		}
	}
	return 1 - shadow;
}


// The code we want to execute in each invocation
void main() {
	// normalize the uv coordinates to be between -1 and 1
	vec2 uv = gl_GlobalInvocationID.xy / vec2(output_resolution.vector) * 2 - 1;

	// imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4((round(bvh_node_buffer.nodes[1].leftNodeIndex) + 11.0) / 2.0, 0, 0, 1));
	// return;

	Ray ray = createCameraRay(uv);
	int sphereIndexes[MAX_INTERSECT_SPHERES];
	int sphereCount = 0;
	getIntersectSpheres(ray, sphereIndexes, sphereCount);

	vec4 sceneInfo = getSceneInfo(ray.origin, sphereIndexes, sphereCount);
	float rayDistance = sceneInfo.w;
	int numSteps = 0;
	// ray march
	while (rayDistance <= MAX_DISTANCE && numSteps < MAX_STEPS && abs(sceneInfo.w) >= MIN_DISTANCE) {
		ray.origin += ray.direction * sceneInfo.w;
		sceneInfo = getSceneInfo(ray.origin, sphereIndexes, sphereCount);
		rayDistance += sceneInfo.w;
		numSteps++;
	}

	// default to transparent black
	imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4(0, 0, 0, 0));
	// if we have hit something, write the color to the output texture
	if (sceneInfo.a < MIN_DISTANCE) {
		float brightness = calculateBrightness(ray.origin);
		imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4(brightness * sceneInfo.rgb, 1));

		// draw outline over the object
		if (numSteps >= OUTLINE_MIN_STEPS + OUTLINE_OVERLAY_STEP_OFFSET && DRAW_OUTLINE) {
			vec4 newColor = vec4(OUTLINE_COLOR, pow(1.0 * (numSteps - (OUTLINE_MIN_STEPS + OUTLINE_OVERLAY_STEP_OFFSET)) / (MAX_STEPS - OUTLINE_MIN_STEPS), OUTLINE_FALLOFF));
			newColor = mix(newColor, vec4(brightness * sceneInfo.rgb, 1), 1 - newColor.a);
			imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), newColor);
		}
	}
	// if we have hit the maximum number of steps, draw object outline
	else if (numSteps >= OUTLINE_MIN_STEPS && DRAW_OUTLINE) {
		imageStore(output_texture, ivec2(gl_GlobalInvocationID.xy), vec4(OUTLINE_COLOR, pow(1.0 * (numSteps - OUTLINE_MIN_STEPS) / (MAX_STEPS - OUTLINE_MIN_STEPS), OUTLINE_FALLOFF)));
	}
}
