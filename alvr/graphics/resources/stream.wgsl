// todo: use expression directly when supported in naga
const DIV12: f32 = 0.0773993808;// 1.0 / 12.92
const DIV1: f32 = 0.94786729857; // 1.0 / 1.055
const THRESHOLD: f32 = 0.04045;
const GAMMA: vec3f = vec3f(2.4);

// LUT constants - 64x64x64 3D LUT stored as 512x512 2D texture (8x8 grid of 64x64 slices)
const LUT_SIZE: f32 = 64.0;
const LUT_GRID_SIZE: f32 = 8.0;  // sqrt(64) = 8 slices per row/column
const LUT_TEXEL_SIZE: f32 = 1.0 / 512.0;  // 1 / (64 * 8)
const LUT_SLICE_SIZE: f32 = 64.0 / 512.0;  // Size of one slice in UV space

override ENABLE_SRGB_CORRECTION: bool;
override ENCODING_GAMMA: f32;

override ENABLE_FFE: bool = false;

override VIEW_WIDTH_RATIO: f32 = 0.;
override VIEW_HEIGHT_RATIO: f32 = 0.;
override EDGE_X_RATIO: f32 = 0.;
override EDGE_Y_RATIO: f32 = 0.;

override C1_X: f32 = 0.;
override C1_Y: f32 = 0.;
override C2_X: f32 = 0.;
override C2_Y: f32 = 0.;
override LO_BOUND_X: f32 = 0.;
override LO_BOUND_Y: f32 = 0.;
override HI_BOUND_X: f32 = 0.;
override HI_BOUND_Y: f32 = 0.;

override A_LEFT_X: f32 = 0.;
override A_LEFT_Y: f32 = 0.;
override B_LEFT_X: f32 = 0.;
override B_LEFT_Y: f32 = 0.;

override A_RIGHT_X: f32 = 0.;
override A_RIGHT_Y: f32 = 0.;
override B_RIGHT_X: f32 = 0.;
override B_RIGHT_Y: f32 = 0.;
override C_RIGHT_X: f32 = 0.;
override C_RIGHT_Y: f32 = 0.;

override COLOR_ALPHA: f32 = 1.0;

// Enable LUT-based chroma keying for Blend passthrough mode
override ENABLE_LUT_CHROMA_KEY: bool = false;

struct PushConstant {
    reprojection_transform: mat4x4f,
    view_idx: u32,
}
var<push_constant> pc: PushConstant;

@group(0) @binding(0) var stream_texture: texture_2d<f32>;
@group(0) @binding(1) var stream_sampler: sampler;
@group(0) @binding(2) var lut_texture: texture_2d<f32>;
@group(0) @binding(3) var lut_sampler: sampler;

// Sample 3D LUT stored as 2D texture
// The LUT is a 64x64x64 cube stored as 8x8 grid of 64x64 slices
// Blue channel determines which slice, Red/Green determine position within slice
fn sample_lut(color: vec3f) -> vec4f {
    // Clamp input to valid range
    let c = clamp(color, vec3f(0.0), vec3f(1.0));
    
    // Scale to LUT coordinates (0 to 63)
    let scaled = c * (LUT_SIZE - 1.0);
    
    // Get the two blue slices to interpolate between
    let blue_low = floor(scaled.b);
    let blue_high = min(blue_low + 1.0, LUT_SIZE - 1.0);
    let blue_fract = scaled.b - blue_low;
    
    // Calculate slice positions in the 8x8 grid
    let slice_low_x = blue_low % LUT_GRID_SIZE;
    let slice_low_y = floor(blue_low / LUT_GRID_SIZE);
    let slice_high_x = blue_high % LUT_GRID_SIZE;
    let slice_high_y = floor(blue_high / LUT_GRID_SIZE);
    
    // Calculate UV coordinates within each slice (with half-texel offset for proper sampling)
    let uv_within_slice = (scaled.rg + 0.5) / LUT_SIZE;
    
    // Calculate final UV coordinates for both slices
    let uv_low = vec2f(
        (slice_low_x + uv_within_slice.r) * LUT_SLICE_SIZE,
        (slice_low_y + uv_within_slice.g) * LUT_SLICE_SIZE
    );
    let uv_high = vec2f(
        (slice_high_x + uv_within_slice.r) * LUT_SLICE_SIZE,
        (slice_high_y + uv_within_slice.g) * LUT_SLICE_SIZE
    );
    
    // Sample both slices and interpolate
    let sample_low = textureSample(lut_texture, lut_sampler, uv_low);
    let sample_high = textureSample(lut_texture, lut_sampler, uv_high);
    
    return mix(sample_low, sample_high, blue_fract);
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vertex_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var result: VertexOutput;

    result.uv = vec2f(f32(vertex_index & 1), f32(vertex_index >> 1));
    result.position = pc.reprojection_transform * vec4f(result.uv.x - 0.5, 0.5 - result.uv.y, 0.0, 1.0);

    return result;
}

@fragment
fn fragment_main(@location(0) uv: vec2f) -> @location(0) vec4f {
    var corrected_uv = uv;
    if ENABLE_FFE {
        let view_size_ratio = vec2f(VIEW_WIDTH_RATIO, VIEW_HEIGHT_RATIO);
        let edge_ratio = vec2f(EDGE_X_RATIO, EDGE_Y_RATIO);

        let c1 = vec2f(C1_X, C1_Y);
        let c2 = vec2f(C2_X, C2_Y);
        let lo_bound = vec2f(LO_BOUND_X, LO_BOUND_Y);
        let hi_bound = vec2f(HI_BOUND_X, HI_BOUND_Y);

        let a_left = vec2f(A_LEFT_X, A_LEFT_Y);
        let b_left = vec2f(B_LEFT_X, B_LEFT_Y);

        let a_right = vec2f(A_RIGHT_X, A_RIGHT_Y);
        let b_right = vec2f(B_RIGHT_X, B_RIGHT_Y);
        let c_right = vec2f(C_RIGHT_X, C_RIGHT_Y);

        if pc.view_idx == 1 {
            corrected_uv.x = 1.0 - corrected_uv.x;
        }

        let center = (corrected_uv - c1) * edge_ratio / c2;
        let left_edge = (-b_left + sqrt(b_left * b_left + 4.0 * a_left * corrected_uv)) / (2.0 * a_left);
        let right_edge = (-b_right + sqrt(b_right * b_right - 4.0 * (c_right - a_right * corrected_uv))) / (2.0 * a_right);

        if corrected_uv.x < lo_bound.x {
            corrected_uv.x = left_edge.x;
        } else if corrected_uv.x > hi_bound.x {
            corrected_uv.x = right_edge.x;
        } else {
            corrected_uv.x = center.x;
        }

        if corrected_uv.y < lo_bound.y {
            corrected_uv.y = left_edge.y;
        } else if corrected_uv.y > hi_bound.y {
            corrected_uv.y = right_edge.y;
        } else {
            corrected_uv.y = center.y;
        }

        corrected_uv = corrected_uv * view_size_ratio;

        if pc.view_idx == 1 {
            corrected_uv.x = 1.0 - corrected_uv.x;
        }
    }

    var color = textureSample(stream_texture, stream_sampler, corrected_uv).rgb;

    if ENABLE_SRGB_CORRECTION {
        let condition = vec3f(f32(color.r < THRESHOLD), f32(color.g < THRESHOLD), f32(color.b < THRESHOLD));
        let lowValues = color * DIV12;
        let highValues = pow((color + vec3f(0.055)) * DIV1, GAMMA);
        color = condition * lowValues + (1.0 - condition) * highValues;
    }

    if ENCODING_GAMMA != 0.0 {
        let enc_condition = vec3f(f32(color.r < 0.0), f32(color.g < 0.0), f32(color.b < 0.0));
        let enc_lowValues = color;
        let enc_highValues = pow(color, vec3f(ENCODING_GAMMA));
        color = enc_condition * enc_lowValues + (1.0 - enc_condition) * enc_highValues;
    }

    // Apply LUT-based chroma keying when in Blend passthrough mode
    // The LUT alpha channel controls visibility: 0 = show PC stream, 1 = show passthrough
    var final_alpha = COLOR_ALPHA;
    if ENABLE_LUT_CHROMA_KEY {
        let lut_result = sample_lut(color);
        // LUT alpha: 0 = fully opaque (show stream), 1 = fully transparent (show passthrough)
        // Invert the alpha so that matching colors (high LUT alpha) become transparent
        final_alpha = 1.0 - lut_result.a;
    }

    return vec4f(color, final_alpha);
}
