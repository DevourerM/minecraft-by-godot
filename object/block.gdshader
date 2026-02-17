shader_type spatial;

// 三张贴图
uniform sampler2D texture_top : filter_nearest;
uniform sampler2D texture_side : filter_nearest;
uniform sampler2D texture_bottom : filter_nearest;

// 新增：发光强度 (默认为0，不发光)
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;

// 传递变量
varying vec3 v_local_vertex;
varying vec3 v_local_normal;

void vertex() {
	// 获取模型本身的局部坐标和法线
	v_local_vertex = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec3 normal = normalize(v_local_normal);
	vec3 abs_normal = abs(normal);
	vec4 color;
	
	// --- 基于局部法线的 Triplanar 映射 ---
	
	if (normal.y > 0.5) {
		// Top
		color = texture(texture_top, v_local_vertex.xz + 0.5);
		
	} else if (normal.y < -0.5) {
		// Bottom
		color = texture(texture_bottom, v_local_vertex.xz + 0.5);
		
	} else {
		// Side
		float v = 0.5 - v_local_vertex.y;
		float u = 0.0;
		if (abs_normal.x > 0.5) {
			u = v_local_vertex.z + 0.5;
		} else {
			u = v_local_vertex.x + 0.5;
		}
		color = texture(texture_side, vec2(u, v));
	}
	
	// 设置基础颜色
	ALBEDO = color.rgb;
	
	// 设置自发光
	// 原理：纹理颜色 * 发光强度。这样纹理亮的地方更亮，暗的地方（如边框）发光也弱
	EMISSION = color.rgb * emission_energy;
}