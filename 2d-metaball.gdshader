shader_type canvas_item;

void fragment() {
	// Called for every pixel the material is visible on.
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(1, a > 0.7? 1.0: 0.0, a > 0.8? 1.0: 0.0, a > 0.5? 1.0: 0.0);
}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
