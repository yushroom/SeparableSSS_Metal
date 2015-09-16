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

// texture samplers
//***********************************************************************
constexpr sampler linear_sampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler point_sampler(address::clamp_to_edge, filter::nearest);
constexpr sampler shadow_sampler(compare_func::less, filter::nearest);

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
    out.view = constants.camera_position.xyz - out.world_position;
    constant auto& mit = constants.ModelInverseTranspose;
    out.normal = (mit * float4(normals[vid], 0)).xyz;
    out.tangent = (mit * float4(tangents[vid], 0)).xyz;
    
    return out;
}

float3 BumpMap(texture2d<float> normal_tex, float2 uv)
{
    float3 bump;
    bump.xy = -1.0 + 2.0 * normal_tex.sample(linear_sampler, uv).gr;
    bump.z = sqrt(1.0 - bump.x * bump.x - bump.y * bump.y);
    return normalize(bump);
}

// H: half
float Fresnel(float3 H, float3 view, float f0) {
    float base = 1.0 - dot(view, H);
    float exponential = pow(base, 5.0);
    return exponential + f0 * (1.0 - exponential);
}


float SpecularKSK(texture2d<float> beckmann_tex, float3 normal, float3 light, float3 view, float roughness, float specularFresnel)
{
    float3 H = view + light;
    float3 HN = normalize(H);
    
    float NdotL = max(dot(normal, light), 0.0);
    float NdotH = max(dot(normal, HN), 0.0);
    
    float ph = pow(2.0 * beckmann_tex.sample(linear_sampler, float2(NdotH, roughness)).r, 10.0f);
    float f = mix(0.25, Fresnel(HN, view, 0.028), specularFresnel);
    float ksk = max(ph * f / dot(H, H), 0.0);
    
    return NdotL * ksk;
}

//float shadowPCF(float3 world_pos, depth2d<float> shadow_texture)
//{
//    shadow_texture.sample_compare(shadow_sampler, lights[i])
//}


//void process(constant AAPL::SLight& light, float3 world_position,  texture2d<float> depth_texture,
//             texture2d<float> beckmann_tex, float4 albedo, float shadow, float3 normal, float3 view,
//             float intensity, float roughness, float specularFresnel, device float4& out_specular_color, device float4& out_color)
//{
//    float3 L = light.position - world_position.xyz;
//    float dist = length(L);
//    L /= dist;
//    
//    float spot = dot(light.direction, -L);
//    if (spot > light.falloffStart)
//    {
//        float curve = min(pow(dist / light.farPlane, 6.0), 1.0);
//        float attenuation = mix(1.0 / (1.0 + light.attenuation * dist * dist), 0, curve);
//        
//        spot = saturate( (spot - light.falloffStart) / light.falloffStart );
//        
//        float3 f1 = light.color * attenuation * spot;
//        float3 f2 = albedo.rgb * f1;
//        
//        float3 diffuse = float3(saturate(dot(L, normal)));
//        float specular = intensity * SpecularKSK(beckmann_tex, normal, L, view, roughness, specularFresnel);
//        
//        out_specular_color.rgb += f1 * specular;
//        out_color.rgb += f2 * diffuse;
//        out_color.rgb += f1 * specular;
//    }
//}

fragment float4 main_pass_frag(constant AAPL::constant_main_pass& constants [[ buffer(0) ]],
                               v2f_main_pass input [[stage_in]],
                               texture2d<float> diffuse_tex [[ texture(0) ]],
                               texture2d<float> specularAO_tex [[ texture(1) ]],
                               texture2d<float> normal_map_tex [[ texture(2) ]],
                               texture2d<float> beckmann_tex [[ texture(3) ]],
                               texturecube<float> irradiance_tex [[ texture(4) ]],
                               depth2d<float> shadow_maps_1 [[ texture(5) ]],
                               depth2d<float> shadow_maps_2 [[ texture(6) ]],
                               depth2d<float> shadow_maps_3 [[ texture(7) ]]
                               )
{
    float3 in_normal = normalize(input.normal);
    float3 tangent = normalize(input.tangent);
    float3 bitangent = normalize(cross(tangent, in_normal));
    float3x3 tbn = mat3(tangent, bitangent, in_normal);
    
    float2 uv_for_dds = float2(input.uv.x, 1.0 - input.uv.y);
    float3 bump_normal = BumpMap(normal_map_tex, uv_for_dds);
    float3 tangent_normal = mix(float3(0, 0, 1), bump_normal, constants.bumpiness);
    float3 normal = tbn * tangent_normal;
    float3 view = normalize(input.view);
    
    float4 albedo = diffuse_tex.sample(linear_sampler, input.uv);
    float3 specularAO = specularAO_tex.sample( linear_sampler, uv_for_dds).bgr;
    
    float occlusion = specularAO.b;
    float intensity = specularAO.r * constants.specularIntensity;
    float roughness = (specularAO.g / 0.3) * constants.specularRoughness;
    
    float4 out_color = float4(0, 0, 0, 0);
    
    float shadow_1, shadow_2, shadow_3;
    float4 shadow_pos[N_LIGHTS];
    for (int i = 0; i < N_LIGHTS; i++)
    {
        shadow_pos[i] = constants.lights[i].viewProjection * float4(input.world_position, 1);
    }
    shadow_1 = shadow_maps_1.sample_compare(shadow_sampler, input.uv, shadow_pos[0].z);
    shadow_2 = shadow_maps_1.sample_compare(shadow_sampler, input.uv, shadow_pos[1].z);
    shadow_3 = shadow_maps_1.sample_compare(shadow_sampler, input.uv, shadow_pos[2].z);
    //shadow[0] = Sh
    
    //float4 out_color = vec4(0);
    float4 out_specular_color = vec4(0);
    
//    void process(constant AAPL::SLight& light, float3 world_position,  depth2d<float> depth_texture,
//                 texture2d<float> beckmann_tex, float4 albedo, float shadow, float3 normal, float3 view,
//                 float intensity, float roughness, float specularFresnel, device float4& out_specular_color, device float4& out_color)
//    process(constants.lights[0], input.world_position, shadow_maps_1,
//            beckmann_tex, albedo, shadow_1, normal, view,
//            intensity, roughness, constants.specularFresnel, out_specular_color, out_color);

    for (int i = 0; i < N_LIGHTS; i++)
    {
        constant auto& light = constants.lights[i];
        float3 L = light.position - input.world_position;
        float dist = length(L);
        L /= dist;
        
        float spot = dot(light.direction, -L);
        if (spot > light.falloffStart)
        {
            float curve = min(pow(dist / light.farPlane, 6.0), 1.0);
            float attenuation = mix(1.0 / (1.0 + light.attenuation * dist * dist), 0.0, curve);
            
            spot = saturate((spot - light.falloffStart) / light.falloffWidth);
            
            float3 f1 = light.color * attenuation * spot;
            float3 f2 = albedo.rgb * f1;
            
            float3 diffuse = saturate(dot(L, normal));
            float specular = intensity * SpecularKSK(beckmann_tex, normal, L, view, roughness, constants.specularFresnel);
            
            float shadow = 1.0f;
            
            //out_color += shadow * f2 * diffuse;
            out_color.rgb += shadow * (f2 * diffuse + f1 * specular);
        }
    }
    
    
    out_color.rgb += occlusion * constants.ambient * albedo.rgb * irradiance_tex.sample(linear_sampler, normal).rgb;
    
    return out_color;
    //return float4(input.normal, 1.0);
}
