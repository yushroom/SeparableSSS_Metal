/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 lighting shader for Basic Metal 3D
 */
#define IN_METAL_FILE
#include <metal_stdlib>
#include <simd/simd.h>
#include "AAPLSharedTypes.h"

using namespace metal;

// variables in constant address space
constant float3 light_position = float3(10.0, 10.0, 10.0);

struct ColorInOut {
    float4 position [[position]];
    half4 color;
};

// vertex shader function
vertex ColorInOut lighting_vertex(constant AAPL::constants_t& constants [[ buffer(0) ]],
                                  device packed_float3* position [[ buffer(1) ]],
                                  device packed_float3* normal [[ buffer(2) ]],
                                  uint vid [[ vertex_id ]])
{
    ColorInOut out;
    
	float4 in_position = float4(float3(position[vid]), 1.0);
    out.position = constants.MVP * in_position;
    
    float3 n = normal[vid];
    float4 eye_normal = normalize(constants.normal_matrix * float4(n, 0.0));
    float n_dot_l = dot(eye_normal.rgb, normalize(light_position));
    n_dot_l = fmax(0.0, n_dot_l);
    
    out.color = half4(n_dot_l);
    //out.color = half4(1, 0.5, 0.3, 1);
    
    return out;
}

// fragment shader function
fragment half4 lighting_fragment(ColorInOut in [[stage_in]])
{
    return in.color;
};

#define N_LIGHTS 3

//typedef float3x3 mat3;
//typedef float4x4 mat4;
//typedef float2 vec2;
//typedef float3 vec3;
//typedef float4 vec4;

// texture sampler
//***********************************************************************
constexpr sampler linear_sampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler point_sampler(address::clamp_to_edge, filter::nearest);

struct v2f_position {
    float4 position [[ position ]];
};

struct v2f_position_normal {
    float4 position [[ position ]];
    float3 normal;
};

struct v2f_position_uv {
    float4 position [[ position ]];
    float2 uv;
};

// screen alinged quad pass (draw texutre to screen)
//***********************************************************************
vertex v2f_position_uv quad_vert(device packed_float3* positions [[ buffer(1) ]],
                                 uint vid [[ vertex_id ]])
{
    v2f_position_uv output;
    float3 pos = positions[vid];
    output.position = float4(pos.xy, 0, 1.0);
    //output.uv = pos.xy + float2(1, 1) / 2.0f;
    output.uv = (float2(pos.x, -pos.y) + float2(1, 1)) / 2.0f;
    return output;
}

fragment float4 quad_frag(v2f_position_uv input [[ stage_in ]],
                        texture2d<float> tex [[ texture(0) ]])
{
    return float4(tex.sample(point_sampler, input.uv).rgb, 1.0f);
}



// shadow pass
//***********************************************************************
vertex v2f_position shadow_pass_vert(constant AAPL::constants_mvp& constants [[ buffer(0) ]],
                                                 device packed_float3* positions [[ buffer(1) ]],
                                                 uint vid [[ vertex_id ]])
{
    v2f_position output;
    output.position = constants.MVP * float4(positions[vid], 1.0);
    return output;
}

//fragment float4 shadow_pass_frag(v2f_position input)
//{
//    return float4(1.0);
//}


// Skydome pass
//***********************************************************************
vertex v2f_position_normal skydome_pass_vert(constant AAPL::constants_mvp& constants [[ buffer(0) ]],
                                              device packed_float3* positions [[ buffer(1) ]],
                                              uint vid [[ vertex_id ]])
{
    v2f_position_normal output;
    output.position = constants.MVP * float4(positions[vid], 1.0);
    output.normal = output.position.xyz;
    output.normal.z = -output.normal.z;
    return output;
}


fragment float4 skydome_pass_frag(v2f_position_normal input [[ stage_in ]],
                                  texturecube<float> tex_sky [[ texture(0) ]])
{
    return tex_sky.sample(linear_sampler, input.normal);
    //return texture(tex_sky, normalize(input.uv).rgb);
}


// main pass
//***********************************************************************
struct v2f_main_pass {
    float4 position [[position]];
    float2 uv;
    float3 world_position;
    float3 view;
    float3 normal;
    float3 tangent;
};

vertex v2f_main_pass main_pass_vert(constant AAPL::constant_main_pass& constants [[ buffer(0) ]],
                                             device packed_float3* positions [[ buffer(1) ]],
                                             device packed_float3* normals [[ buffer(2) ]],
                                             device packed_float3* tangents [[ buffer(3) ]],
                                             device packed_float2* uvs [[ buffer(4) ]],
                                             uint vid [[ vertex_id ]])
{
    v2f_main_pass out;
    float4 pos(positions[vid], 1.0);
    out.position = constants.MVP * pos;
    out.uv = uvs[vid];
    out.world_position = (constants.Model * pos).xyz;
    out.view = constants.camera_position - out.world_position;
    constant auto& mit = constants.ModelInverseTranspose;
    out.normal = mit * float3(normals[vid]);
    out.tangent = mit * float3(tangents[vid]);
    
    return out;
}

fragment float4 main_pass_frag(v2f_main_pass input [[stage_in]],
                               texture2d<float> diffuse_tex [[ texture(0) ]],
                               texture2d<float> specularAO_tex [[ texture(1) ]],
                               texture2d<float> normal_map_tex [[ texture(2) ]],
                               texture2d<float> beckmann_tex [[ texture(3) ]],
                               texture2d<float> irradiance_tex [[ texture(4) ]]
                               //texture2d<float> shadow_maps_1 [[ texture(5) ]],
                               //texture2d<float> shadow_maps_2 [[ texture(6) ]],
                               //texture2d<float> shadow_maps_3 [[ texture(7) ]],
                               //texture2d<float> depth_textures_0 [[ texture(8) ]],
                               //texture2d<float> depth_textures_1 [[ texture(9) ]],
                               //texture2d<float> depth_textures_2 [[ texture(10) ]]
                               )
{ 
    return diffuse_tex.sample(linear_sampler, input.uv);
}

/********** main pass END **********/