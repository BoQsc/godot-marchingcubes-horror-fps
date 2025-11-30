#[compute]
#version 450

// Workgroup size (adjust based on your grid size, e.g., 32x32x32)
layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

// --- BUFFERS ---

// Output Vertices: 3 floats per vertex. We assume max 5 triangles (15 verts) per voxel is rare but possible.
// Size this buffer generously in the GDScript (e.g. max_voxels * 15 * 4 bytes).
layout(set = 0, binding = 0, std430) buffer OutputBuffer {
    float vertices[];
};

// Atomic Counter to track the number of vertices written
layout(set = 0, binding = 1, std430) buffer CounterBuffer {
    uint vertex_count;
};

// Configuration Uniforms
layout(set = 0, binding = 2, std140) uniform Config {
    vec4 chunk_offset; // Changed to vec4 to enforce 16-byte alignment
    int grid_size;
    float iso_level;
    float terrain_height;
    float scale_factor;
} config;

// --- LOOKUP TABLES ---
// (Minimal Marching Cubes Tables - Ported from standard implementations)
// These are typically constant. For a full implementation, you might pass these as Uniform Buffers
// if you want to reduce shader compile size, but for now, hardcoding is easier for a standalone file.

const int edgeTable[] = int[](
    0x0, 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c, 0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
    0x190, 0x99, 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c, 0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
    0x230, 0x339, 0x33, 0x13a, 0x636, 0x73f, 0x435, 0x53c, 0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30,
    0x3a0, 0x2a9, 0x1a3, 0xaa, 0x7a6, 0x6af, 0x5a5, 0x4ac, 0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0,
    0x460, 0x569, 0x663, 0x76a, 0x66, 0x16f, 0x265, 0x36c, 0xc6c, 0xd65, 0xe6f, 0xf66, 0x86a, 0x963, 0xa69, 0xb60,
    0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff, 0x3f5, 0x2fc, 0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
    0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55, 0x15c, 0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950,
    0x7c0, 0x6c9, 0x5c3, 0x4ca, 0x3c6, 0x2cf, 0x1c5, 0xcc, 0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0,
    0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc, 0xcc, 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0,
    0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c, 0x15c, 0x55, 0x35f, 0x256, 0x55a, 0x453, 0x759, 0x650,
    0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc, 0x2fc, 0x3f5, 0xff, 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
    0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c, 0x36c, 0x265, 0x16f, 0x66, 0x76a, 0x663, 0x569, 0x460,
    0xca0, 0xda9, 0xea3, 0xfaa, 0x8a6, 0x9af, 0xaa5, 0xbac, 0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa, 0x1a3, 0x2a9, 0x3a0,
    0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c, 0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33, 0x339, 0x230,
    0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c, 0x69c, 0x795, 0x49f, 0x596, 0x29a, 0x393, 0x99, 0x190,
    0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c, 0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0
);

const int triTable[] = int[](
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 1, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    1, 8, 3, 9, 8, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 2, 10, 0, 2, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    2, 8, 3, 2, 10, 8, 10, 9, 8, -1, -1, -1, -1, -1, -1, -1,
    3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 11, 2, 8, 11, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    1, 9, 0, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    1, 11, 2, 1, 9, 11, 9, 8, 11, -1, -1, -1, -1, -1, -1, -1,
    3, 10, 1, 11, 10, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 10, 1, 0, 8, 10, 8, 11, 10, -1, -1, -1, -1, -1, -1, -1,
    3, 9, 0, 3, 11, 9, 11, 10, 9, -1, -1, -1, -1, -1, -1, -1,
    9, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    4, 3, 0, 7, 3, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 1, 9, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    4, 1, 9, 4, 7, 1, 7, 3, 1, -1, -1, -1, -1, -1, -1, -1,
    1, 2, 10, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    3, 4, 7, 3, 0, 4, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1,
    9, 2, 10, 9, 0, 2, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1,
    2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, -1, -1, -1, -1,
    8, 4, 7, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    11, 4, 7, 11, 2, 4, 2, 0, 4, -1, -1, -1, -1, -1, -1, -1,
    9, 0, 1, 8, 4, 7, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1,
    4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, -1, -1, -1, -1,
    3, 10, 1, 3, 11, 10, 7, 8, 4, -1, -1, -1, -1, -1, -1, -1,
    1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, -1, -1, -1, -1,
    4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, -1, -1, -1, -1,
    4, 7, 11, 4, 11, 9, 9, 11, 10, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 4, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 1, 5, 4, 5, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    1, 8, 3, 9, 5, 4, 5, 9, 1, -1, -1, -1, -1, -1, -1, -1,
    1, 2, 10, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    3, 0, 8, 1, 2, 10, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1,
    5, 2, 10, 5, 4, 2, 4, 0, 2, -1, -1, -1, -1, -1, -1, -1,
    2, 8, 3, 2, 10, 8, 10, 9, 8, 9, 5, 4, -1, -1, -1, -1,
    9, 5, 4, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 11, 2, 8, 11, 0, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1,
    1, 5, 4, 1, 4, 0, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1,
    1, 11, 2, 1, 9, 11, 9, 8, 11, 8, 9, 5, 8, 5, 4, -1,
    3, 10, 1, 3, 11, 10, 7, 5, 4, -1, -1, -1, -1, -1, -1, -1,
    7, 5, 4, 10, 1, 0, 10, 0, 8, 10, 8, 11, -1, -1, -1, -1,
    3, 9, 0, 3, 11, 9, 11, 10, 9, 7, 5, 4, -1, -1, -1, -1,
    9, 8, 10, 10, 8, 11, 4, 7, 5, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 7, 9, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 7, 9, 7, 3, 9, 3, 0, -1, -1, -1, -1, -1, -1, -1,
    0, 1, 5, 0, 5, 7, 0, 7, 8, -1, -1, -1, -1, -1, -1, -1,
    1, 5, 7, 1, 7, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 7, 9, 7, 8, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1,
    3, 9, 5, 3, 5, 7, 3, 7, 0, 1, 2, 10, -1, -1, -1, -1,
    0, 2, 10, 0, 10, 8, 8, 10, 7, 10, 5, 7, -1, -1, -1, -1,
    2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 5, 9, -1, -1, -1, -1,
    9, 5, 7, 9, 7, 8, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1,
    11, 9, 5, 11, 5, 7, 11, 7, 2, 2, 7, 0, -1, -1, -1, -1,
    0, 1, 5, 0, 5, 7, 0, 7, 8, 2, 3, 11, -1, -1, -1, -1,
    5, 7, 11, 5, 11, 9, 9, 11, 2, 9, 2, 1, -1, -1, -1, -1,
    3, 10, 1, 3, 11, 10, 7, 5, 9, 7, 9, 8, -1, -1, -1, -1,
    11, 10, 1, 11, 1, 0, 11, 0, 7, 7, 0, 5, -1, -1, -1, -1,
    10, 11, 3, 10, 3, 0, 5, 7, 9, 5, 9, 8, -1, -1, -1, -1,
    5, 7, 9, 9, 7, 11, 9, 11, 10, -1, -1, -1, -1, -1, -1, -1,
    6, 10, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 6, 10, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 6, 10, 9, 10, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    10, 6, 1, 10, 1, 8, 8, 1, 3, 8, 3, 9, -1, -1, -1, -1,
    6, 10, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 6, 10, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 6, 10, 9, 10, 2, 9, 2, 0, -1, -1, -1, -1, -1, -1, -1,
    6, 10, 2, 6, 2, 9, 6, 9, 8, 8, 9, 3, -1, -1, -1, -1,
    6, 11, 2, 6, 2, 1, 1, 2, 3, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 11, 0, 11, 2, 2, 11, 6, 2, 6, 1, -1, -1, -1, -1,
    3, 11, 2, 3, 2, 6, 3, 6, 0, 0, 6, 9, -1, -1, -1, -1,
    6, 9, 0, 6, 0, 2, 6, 2, 11, 11, 2, 8, 11, 8, 9, -1,
    10, 1, 3, 10, 3, 11, 10, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 0, 3, 6, 0, 6, 10, 10, 6, 11, -1, -1, -1, -1,
    9, 0, 3, 9, 3, 6, 6, 3, 11, 6, 11, 10, -1, -1, -1, -1,
    6, 11, 10, 6, 10, 9, 9, 10, 8, -1, -1, -1, -1, -1, -1, -1,
    4, 7, 8, 6, 10, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    4, 3, 0, 7, 3, 4, 6, 10, 1, -1, -1, -1, -1, -1, -1, -1,
    1, 6, 10, 9, 8, 4, 9, 4, 7, -1, -1, -1, -1, -1, -1, -1,
    10, 1, 6, 7, 3, 1, 7, 1, 9, 9, 1, 4, -1, -1, -1, -1,
    6, 10, 2, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    4, 3, 0, 7, 3, 4, 6, 10, 2, -1, -1, -1, -1, -1, -1, -1,
    6, 10, 2, 9, 0, 2, 9, 2, 8, 8, 2, 4, 4, 2, 7, -1,
    7, 4, 2, 7, 2, 6, 7, 6, 9, 9, 6, 10, 9, 10, 2, -1,
    4, 7, 8, 6, 11, 2, 6, 2, 1, 1, 2, 3, -1, -1, -1, -1,
    1, 2, 3, 1, 3, 6, 6, 3, 11, 6, 11, 4, 6, 4, 2, 2, 4, 7, 2, 7, 0,
    4, 7, 8, 9, 0, 3, 9, 3, 6, 6, 3, 2, 6, 2, 11, -1,
    2, 1, 6, 2, 6, 11, 4, 7, 9, 4, 9, 11, 11, 9, 10, -1,
    4, 7, 8, 3, 11, 10, 3, 10, 1, 3, 1, 6, -1, -1, -1, -1,
    0, 8, 4, 0, 4, 6, 0, 6, 1, 1, 6, 10, 1, 10, 11, 1, 11, 7, 1, 7, 3,
    9, 0, 3, 9, 3, 11, 9, 11, 10, 10, 11, 6, 4, 7, 8, -1,
    6, 11, 10, 6, 10, 9, 9, 10, 8, 8, 10, 4, 4, 10, 7, -1,
    9, 5, 4, 6, 10, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 4, 3, 0, 8, 1, 6, 10, -1, -1, -1, -1, -1, -1, -1,
    5, 4, 1, 5, 1, 6, 5, 6, 9, 9, 6, 10, -1, -1, -1, -1,
    9, 5, 4, 9, 4, 8, 8, 4, 3, 3, 4, 1, 1, 4, 6, 6, 4, 5,
    6, 10, 2, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 2, 6, 10, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1,
    5, 4, 2, 5, 2, 9, 9, 2, 0, 9, 0, 6, 6, 0, 10, -1,
    5, 4, 8, 5, 8, 9, 9, 8, 10, 10, 8, 3, 3, 8, 2, 2, 8, 6,
    3, 11, 2, 9, 5, 4, 1, 6, 10, -1, -1, -1, -1, -1, -1, -1,
    0, 11, 2, 0, 2, 8, 8, 2, 1, 1, 2, 6, 6, 2, 10, 4, 9, 5,
    9, 5, 4, 2, 3, 11, 0, 1, 6, 0, 6, 10, -1, -1, -1, -1,
    11, 2, 8, 11, 8, 9, 9, 8, 5, 5, 8, 4, 1, 6, 10, -1,
    1, 6, 10, 3, 11, 10, 3, 10, 1, 7, 5, 4, -1, -1, -1, -1,
    7, 5, 4, 8, 11, 10, 8, 10, 0, 0, 10, 6, 0, 6, 1, -1,
    7, 5, 4, 9, 0, 3, 9, 3, 11, 9, 11, 10, 10, 11, 6, -1,
    7, 5, 4, 8, 11, 10, 8, 10, 9, 9, 10, 6, -1, -1, -1, -1,
    9, 5, 7, 9, 7, 8, 6, 10, 1, -1, -1, -1, -1, -1, -1, -1,
    9, 5, 7, 9, 7, 8, 9, 8, 3, 3, 8, 0, 1, 6, 10, -1,
    5, 7, 8, 5, 8, 0, 5, 0, 1, 1, 0, 6, 6, 0, 10, -1,
    7, 3, 1, 7, 1, 5, 5, 1, 6, -1, -1, -1, -1, -1, -1, -1,
    1, 2, 10, 9, 5, 7, 9, 7, 8, 9, 8, 6, 6, 8, 10, -1,
    3, 9, 5, 3, 5, 7, 3, 7, 0, 10, 2, 1, 10, 1, 6, -1,
    8, 0, 2, 8, 2, 10, 8, 10, 7, 7, 10, 5, 5, 10, 6, -1,
    2, 10, 9, 2, 9, 5, 2, 5, 6, 6, 5, 7, 7, 5, 3, -1,
    3, 11, 2, 9, 5, 7, 9, 7, 8, 1, 6, 10, -1, -1, -1, -1,
    0, 7, 5, 0, 5, 11, 11, 5, 2, 2, 5, 6, 6, 5, 10, 10, 5, 9,
    8, 0, 7, 8, 7, 5, 5, 7, 1, 1, 7, 3, 1, 3, 6, 6, 3, 2, 2, 3, 11,
    4, 11, 2, 4, 2, 9, 9, 2, 5, 5, 2, 6, 6, 2, 1, -1,
    3, 11, 10, 3, 10, 1, 3, 1, 8, 8, 1, 6, 8, 6, 7, 7, 6, 5, 5, 6, 9,
    11, 0, 1, 11, 1, 10, 10, 1, 6, 7, 5, 8, -1, -1, -1, -1,
    9, 8, 3, 9, 3, 0, 5, 7, 10, 5, 10, 6, 6, 10, 11, -1,
    11, 10, 6, 9, 8, 7, 9, 7, 5, -1, -1, -1, -1, -1, -1, -1,
    5, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    9, 0, 1, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    1, 8, 3, 9, 8, 1, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    1, 2, 10, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 1, 2, 10, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    9, 2, 10, 0, 2, 9, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    2, 8, 3, 2, 10, 8, 10, 9, 8, 5, 11, 6, -1, -1, -1, -1,
    2, 3, 5, 2, 5, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 2, 0, 2, 5, 5, 2, 6, -1, -1, -1, -1, -1, -1, -1,
    9, 0, 1, 5, 6, 2, 5, 2, 3, -1, -1, -1, -1, -1, -1, -1,
    1, 8, 5, 1, 5, 6, 6, 5, 2, 2, 5, 3, 3, 5, 9, -1,
    1, 5, 6, 1, 6, 10, 10, 6, 11, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 1, 5, 6, 1, 6, 10, 10, 6, 11, -1, -1, -1, -1,
    9, 0, 1, 1, 10, 11, 1, 11, 6, 6, 11, 5, -1, -1, -1, -1,
    6, 11, 5, 1, 8, 3, 1, 3, 10, 10, 3, 9, -1, -1, -1, -1,
    4, 7, 8, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    4, 3, 0, 7, 3, 4, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    0, 1, 9, 8, 4, 7, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    4, 1, 9, 4, 7, 1, 7, 3, 1, 5, 11, 6, -1, -1, -1, -1,
    1, 2, 10, 8, 4, 7, 5, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    3, 4, 7, 3, 0, 4, 1, 2, 10, 5, 11, 6, -1, -1, -1, -1,
    9, 2, 10, 9, 0, 2, 8, 4, 7, 5, 11, 6, -1, -1, -1, -1,
    2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, 5, 11, 6, -1,
    8, 4, 7, 5, 6, 2, 5, 2, 3, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 4, 0, 4, 7, 0, 7, 5, 5, 7, 6, 6, 7, 2, -1,
    9, 0, 1, 5, 6, 2, 5, 2, 3, 8, 4, 7, -1, -1, -1, -1,
    1, 5, 6, 1, 6, 2, 2, 6, 7, 7, 6, 4, 4, 6, 9, -1,
    1, 5, 6, 1, 6, 10, 10, 6, 11, 4, 7, 8, -1, -1, -1, -1,
    1, 5, 6, 1, 6, 10, 10, 6, 11, 4, 3, 0, 7, 3, 4, -1,
    0, 1, 9, 8, 4, 7, 10, 11, 5, 10, 5, 6, -1, -1, -1, -1,
    6, 11, 5, 7, 3, 1, 4, 3, 7, 1, 3, 10, 10, 3, 9, -1,
    9, 11, 6, 9, 6, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 4, 9, 11, 4, 11, 6, -1, -1, -1, -1, -1, -1, -1,
    0, 1, 11, 0, 11, 6, 6, 11, 4, 4, 11, 5, -1, -1, -1, -1,
    1, 8, 3, 9, 8, 1, 5, 4, 6, 6, 4, 11, -1, -1, -1, -1,
    1, 2, 10, 9, 11, 6, 9, 6, 4, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 1, 2, 10, 4, 9, 11, 4, 11, 6, -1, -1, -1, -1,
    2, 10, 0, 2, 0, 11, 11, 0, 6, 6, 0, 4, 4, 0, 5, -1,
    2, 8, 3, 2, 10, 8, 10, 9, 8, 4, 11, 6, 4, 6, 5, -1,
    2, 3, 11, 2, 11, 6, 6, 11, 9, 9, 11, 4, -1, -1, -1, -1,
    0, 8, 2, 0, 2, 11, 11, 2, 6, 4, 9, 6, 6, 9, 11, -1,
    0, 1, 4, 0, 4, 6, 6, 4, 11, 11, 4, 5, 5, 4, 2, 2, 4, 3,
    1, 8, 3, 1, 3, 2, 2, 3, 11, 11, 3, 6, 6, 3, 4, 4, 3, 5,
    1, 2, 10, 4, 6, 11, 4, 11, 9, -1, -1, -1, -1, -1, -1, -1,
    0, 8, 3, 1, 2, 10, 6, 4, 9, 6, 9, 11, -1, -1, -1, -1,
    10, 0, 1, 10, 1, 11, 11, 1, 4, 4, 1, 5, 5, 1, 6, -1,
    8, 3, 2, 8, 2, 10, 10, 2, 11, 11, 2, 6, 6, 2, 4, 4, 2, 5,
    5, 7, 8, 5, 8, 11, 11, 8, 6, 6, 8, 9, -1, -1, -1, -1,
    0, 5, 7, 0, 7, 3, 3, 7, 11, 11, 7, 6, -1, -1, -1, -1,
    0, 1, 9, 5, 7, 8, 5, 8, 11, 11, 8, 6, -1, -1, -1, -1,
    1, 9, 3, 1, 3, 5, 5, 3, 7, 7, 3, 6, 6, 3, 11, -1,
    1, 2, 10, 9, 5, 7, 9, 7, 8, 9, 8, 6, 6, 8, 11, -1,
    3, 5, 7, 3, 7, 10, 10, 7, 6, 6, 7, 11, 11, 7, 2, 2, 7, 1,
    8, 0, 2, 8, 2, 10, 8, 10, 9, 9, 10, 6, 6, 10, 11, 11, 10, 5,
    7, 2, 5, 7, 5, 6, 6, 5, 11, 11, 5, 9, 9, 5, 3, 3, 5, 1,
    5, 7, 8, 5, 8, 3, 3, 8, 2, 2, 8, 4, 4, 8, 9, -1,
    0, 2, 3, 0, 3, 5, 5, 3, 7, 7, 3, 4, -1, -1, -1, -1,
    0, 1, 9, 4, 9, 8, 5, 9, 4, 2, 3, 5, 5, 3, 7, -1,
    1, 5, 7, 1, 7, 4, 4, 7, 2, 2, 7, 3, -1, -1, -1, -1,
    1, 2, 10, 3, 2, 5, 5, 2, 7, 7, 2, 4, 4, 2, 8, 8, 2, 9,
    10, 3, 0, 10, 0, 4, 4, 0, 5, 5, 0, 2, 2, 0, 1, -1,
    0, 9, 8, 0, 8, 10, 10, 8, 5, 5, 8, 4, 4, 8, 2, 2, 8, 1,
    7, 5, 4, 10, 4, 5, 10, 5, 1, 1, 5, 2, 2, 5, 3, 3, 5, 9
);

// --- SIMPLEX NOISE 3D ---
// (Source: https://github.com/stegu/webgl-noise/blob/master/src/noise3D.glsl)
// Optimized slightly for this use case

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x*34.0)+1.0)*x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) { 
    const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
    const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

    // First corner
    vec3 i  = floor(v + dot(v, C.yyy) );
    vec3 x0 = v - i + dot(i, C.xxx) ;

    // Other corners
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min( g.xyz, l.zxy );
    vec3 i2 = max( g.xyz, l.zxy );

    //   x0 = x0 - 0.0 + 0.0 * C.xxx;
    //   x1 = x0 - i1  + 1.0 * C.xxx;
    //   x2 = x0 - i2  + 2.0 * C.xxx;
    //   x3 = x0 - 1.0 + 3.0 * C.xxx;
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
    vec3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

    // Permutations
    i = mod289(i); 
    vec4 p = permute( permute( permute( 
                 i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
               + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
               + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

    // Gradients: 7x7 points over a square, mapped onto an octahedron.
    // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
    float n_ = 0.142857142857; // 1.0/7.0
    vec3  ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

    vec4 x = x_ *ns.x + ns.yyyy;
    vec4 y = y_ *ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4( x.xy, y.xy );
    vec4 b1 = vec4( x.zw, y.zw );

    //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
    //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
    vec4 s0 = floor(b0)*2.0 + 1.0;
    vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
    vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

    vec3 p0 = vec3(a0.xy,h.x);
    vec3 p1 = vec3(a0.zw,h.y);
    vec3 p2 = vec3(a1.xy,h.z);
    vec3 p3 = vec3(a1.zw,h.w);

    //Normalise gradients
    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    // Mix final noise value
    vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
                                dot(p2,x2), dot(p3,x3) ) );
}

// --- HELPER FUNCTIONS ---

float get_density(vec3 pos) {
    vec3 global_pos = config.chunk_offset.xyz * config.grid_size + pos;
    
    // Smoother terrain
    float freq = 0.01; 
    float noise_val = snoise(global_pos * freq);
    
    // CPU Logic match: Ground is negative
    float density = pos.y - (noise_val * config.terrain_height) - (config.grid_size * 0.5);
    
    return density;
}

vec3 vertex_interp(vec3 p1, vec3 p2, float v1, float v2) {
    if (abs(config.iso_level - v1) < 0.00001) return p1;
    if (abs(config.iso_level - v2) < 0.00001) return p2;
    if (abs(v1 - v2) < 0.00001) return p1;
    float mu = (config.iso_level - v1) / (v2 - v1);
    return mix(p1, p2, mu);
}

// --- MAIN ---

void main() {
    // Current voxel coordinates
    uvec3 id = gl_GlobalInvocationID.xyz;
    
    // Ensure we are within bounds (grid_size - 1 because we need neighbors)
    if (id.x >= config.grid_size || id.y >= config.grid_size || id.z >= config.grid_size) {
        return;
    }
    
    vec3 pos = vec3(id);
    
    // 1. Calculate densities at corners
    float corners[8];
    corners[0] = get_density(pos + vec3(0, 0, 0));
    corners[1] = get_density(pos + vec3(1, 0, 0));
    corners[2] = get_density(pos + vec3(1, 0, 1));
    corners[3] = get_density(pos + vec3(0, 0, 1));
    corners[4] = get_density(pos + vec3(0, 1, 0));
    corners[5] = get_density(pos + vec3(1, 1, 0));
    corners[6] = get_density(pos + vec3(1, 1, 1));
    corners[7] = get_density(pos + vec3(0, 1, 1));
    
    // 2. Determine Cube Index
    int cube_index = 0;
    if (corners[0] < config.iso_level) cube_index |= 1;
    if (corners[1] < config.iso_level) cube_index |= 2;
    if (corners[2] < config.iso_level) cube_index |= 4;
    if (corners[3] < config.iso_level) cube_index |= 8;
    if (corners[4] < config.iso_level) cube_index |= 16;
    if (corners[5] < config.iso_level) cube_index |= 32;
    if (corners[6] < config.iso_level) cube_index |= 64;
    if (corners[7] < config.iso_level) cube_index |= 128;
    
    // 3. Lookup Edge Table
    int edge_flags = edgeTable[cube_index];
    if (edge_flags == 0) return; // Cube is entirely inside or outside
    
    // 4. Calculate vertices on edges
    vec3 edge_verts[12];
    // Initialize to prevent garbage data if lookup tables mismatch
    for(int i=0; i<12; i++) edge_verts[i] = vec3(0.0);
    
    vec3 p0 = pos + vec3(0, 0, 0);
    vec3 p1 = pos + vec3(1, 0, 0);
    vec3 p2 = pos + vec3(1, 0, 1);
    vec3 p3 = pos + vec3(0, 0, 1);
    vec3 p4 = pos + vec3(0, 1, 0);
    vec3 p5 = pos + vec3(1, 1, 0);
    vec3 p6 = pos + vec3(1, 1, 1);
    vec3 p7 = pos + vec3(0, 1, 1);
    
    if ((edge_flags & 1) != 0)    edge_verts[0] = vertex_interp(p0, p1, corners[0], corners[1]);
    if ((edge_flags & 2) != 0)    edge_verts[1] = vertex_interp(p1, p2, corners[1], corners[2]);
    if ((edge_flags & 4) != 0)    edge_verts[2] = vertex_interp(p2, p3, corners[2], corners[3]);
    if ((edge_flags & 8) != 0)    edge_verts[3] = vertex_interp(p3, p0, corners[3], corners[0]);
    if ((edge_flags & 16) != 0)   edge_verts[4] = vertex_interp(p4, p5, corners[4], corners[5]);
    if ((edge_flags & 32) != 0)   edge_verts[5] = vertex_interp(p5, p6, corners[5], corners[6]);
    if ((edge_flags & 64) != 0)   edge_verts[6] = vertex_interp(p6, p7, corners[6], corners[7]);
    if ((edge_flags & 128) != 0)  edge_verts[7] = vertex_interp(p7, p4, corners[7], corners[4]);
    if ((edge_flags & 256) != 0)  edge_verts[8] = vertex_interp(p0, p4, corners[0], corners[4]);
    if ((edge_flags & 512) != 0)  edge_verts[9] = vertex_interp(p1, p5, corners[1], corners[5]);
    if ((edge_flags & 1024) != 0) edge_verts[10] = vertex_interp(p2, p6, corners[2], corners[6]);
    if ((edge_flags & 2048) != 0) edge_verts[11] = vertex_interp(p3, p7, corners[3], corners[7]);
    
    // 5. Output Triangles
    // 16 because TriTable has -1 padding and max 5 triangles * 3 vertices = 15.
    for (int i = 0; i < 16; i += 3) {
        int v1_idx = triTable[cube_index * 16 + i];
        if (v1_idx == -1) break;
        
        int v2_idx = triTable[cube_index * 16 + i + 1];
        int v3_idx = triTable[cube_index * 16 + i + 2];
        
        vec3 tri_v1 = edge_verts[v1_idx] * config.scale_factor;
        vec3 tri_v2 = edge_verts[v2_idx] * config.scale_factor;
        vec3 tri_v3 = edge_verts[v3_idx] * config.scale_factor;
        
        // Atomic add to get write position
        uint index = atomicAdd(vertex_count, 3u);
        
        // Write to buffer (Output is flat float array)
        // CPU Winding Order (v1, v3, v2) - Swapped v2/v3 from standard
        vertices[index * 3 + 0] = tri_v1.x;
        vertices[index * 3 + 1] = tri_v1.y;
        vertices[index * 3 + 2] = tri_v1.z;
        
        vertices[index * 3 + 3] = tri_v3.x;
        vertices[index * 3 + 4] = tri_v3.y;
        vertices[index * 3 + 5] = tri_v3.z;
        
        vertices[index * 3 + 6] = tri_v2.x;
        vertices[index * 3 + 7] = tri_v2.y;
        vertices[index * 3 + 8] = tri_v2.z;
    }
}