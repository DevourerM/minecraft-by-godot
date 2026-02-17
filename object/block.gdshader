shader_type spatial;

// 三张贴图
uniform sampler2D texture_top : filter_nearest;
uniform sampler2D texture_side : filter_nearest;
uniform sampler2D texture_bottom : filter_nearest;

// 定义变量，用于从 vertex 函数向 fragment 函数传递数据
// "v_" 前缀代表 varying (变化的)
varying vec3 v_local_vertex;
varying vec3 v_local_normal;

void vertex() {
	// 【核心改动】
	// 获取模型本身的局部坐标和法线。
	// 这些值是相对于模型中心的，无论模型在世界中怎么旋转，这些值对于模型自身来说是不变的。
	v_local_vertex = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	// 使用传递过来的局部法线
	vec3 normal = normalize(v_local_normal);
	vec3 abs_normal = abs(normal);
	vec4 color;
	
	// --- 基于局部法线的 Triplanar 映射 ---
	
	// 判断逻辑：现在是判断模型"自己认为"的头顶在哪里，而不是世界坐标的头顶
	if (normal.y > 0.5) {
		// --- 顶面 (Top) ---
		// 使用模型的局部 X 和 Z 坐标作为 UV
		color = texture(texture_top, v_local_vertex.xz + 0.5);
		
	} else if (normal.y < -0.5) {
		// --- 底面 (Bottom) ---
		color = texture(texture_bottom, v_local_vertex.xz + 0.5);
		
	} else {
		// --- 侧面 (Side) ---
		// V (垂直方向)：永远对应模型的局部 Y 轴高度
		float v = 0.5 - v_local_vertex.y;
		
		// U (水平方向)：根据侧面具体朝向选择 X 或 Z
		float u = 0.0;
		// 如果法线主要朝向模型的 X 轴方向 (左右面)
		if (abs_normal.x > 0.5) {
			u = v_local_vertex.z + 0.5;
		} else {
			// 如果法线主要朝向模型的 Z 轴方向 (前后面)
			u = v_local_vertex.x + 0.5;
		}
		
		color = texture(texture_side, vec2(u, v));
	}
	
	ALBEDO = color.rgb;
}