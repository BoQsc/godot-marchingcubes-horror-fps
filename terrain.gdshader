shader_type spatial;

uniform sampler2D grass_texture : source_color;
uniform sampler2D road_texture : source_color;
uniform float texture_scale = 0.1;

varying float road_weight;
varying vec3 uv1_power_normal;
varying vec3 uv1_triplanar_pos;

void vertex() {
    road_weight = COLOR.r;
    
    // Triplanar mapping setup
    vec3 normal = normalize(NORMAL);
    uv1_power_normal = pow(abs(normal), vec3(1.0)); // Sharpness
    uv1_power_normal /= dot(uv1_power_normal, vec3(1.0));
    uv1_triplanar_pos = VERTEX * texture_scale; // World position scale
}

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
    vec4 samp = vec4(0.0);
    samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
    samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
    samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
    return samp;
}

void fragment() {
    vec4 grass = triplanar_texture(grass_texture, uv1_power_normal, uv1_triplanar_pos);
    vec4 road = triplanar_texture(road_texture, uv1_power_normal, uv1_triplanar_pos);
    
    ALBEDO = mix(grass.rgb, road.rgb, road_weight);
    ROUGHNESS = 0.8;
}
