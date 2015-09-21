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

#define N_LIGHTS 3

typedef float3x3 mat3;
typedef float4x4 mat4;
typedef float2 vec2;
typedef float3 vec3;
typedef float4 vec4;

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
    //output.position.z *= output.position.w; // We want linear positions
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

struct frag_out_main_pass {
    float4 color    [[color(0)]];
    float depth     [[color(1)]];
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

// get original z [(mvp * v).z] from z in shadowMap
float to_frag_z(float z)
{
    float far = 10.0f;
    float near = 0.1f;
    float frag_z = far*near / (far-z*(far-near));
    return (frag_z-near)*far / (far-near);
}

//-----------------------------------------------------------------------------
// Separable SSS Transmittance Function

vec3 SSSSTransmittance(float translucency, float sssWidth, vec3 worldPosition, vec3 worldNormal, vec3 light, depth2d<float> shadowMap, mat4 lightViewProjection, float lightFarPlane) {
    /**
     * Calculate the scale of the effect.
     */
    float scale = 8.25 * (1.0 - translucency) / sssWidth;
    
    /**
     * First we shrink the position inwards the surface to avoid artifacts:
     * (Note that this can be done once for all the lights)
     */
    vec4 shrinkedPos = vec4(worldPosition - 0.005 * worldNormal, 1.0);
    
    /**
     * Now we calculate the thickness from the light point of view:
     */
    vec4 shadowPosition = lightViewProjection * shrinkedPos;
    
    
    
    shadowPosition.xyz /= shadowPosition.w;
    //float d1 = texture(shadowMap, shadowPosition.xy).r;
    float d1 = shadowMap.sample(point_sampler, shadowPosition.xy);
    //d1 = to_frag_z(d1);
    float d2 = shadowPosition.z;
    //d2 = 0.5 * d2 + 0.5;
    float d = scale * abs(d1 - d2);
    
    /**
     * Armed with the thickness, we can now calculate the color by means of the
     * precalculated transmittance profile.
     * (It can be precomputed into a texture, for maximum performance):
     */
    float dd = -d * d;
    //vec3 profile = texture(shadowMap, frag_uv).rgb;
    vec3 profile = vec3(0.233, 0.455, 0.649) * exp(dd / 0.0064) +
    vec3(0.1,   0.336, 0.344) * exp(dd / 0.0484) +
    vec3(0.118, 0.198, 0.0)   * exp(dd / 0.187)  +
    vec3(0.113, 0.007, 0.007) * exp(dd / 0.567)  +
    vec3(0.358, 0.004, 0.0)   * exp(dd / 1.99)   +
    vec3(0.078, 0.0,   0.0)   * exp(dd / 7.41);
    //vec3 profile = vec3(0);
    
    /**
     * Using the profile, we finally approximate the transmitted lighting from
     * the back of the object:
     */
    return profile * saturate(0.3 + dot(light, -worldNormal));
    //return vec3(1);
    //return vec3(textureProj(shadowMap, shadowPosition));
}

fragment frag_out_main_pass main_pass_frag(constant AAPL::constant_main_pass& constants [[ buffer(0) ]],
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
    float3 specularAO = specularAO_tex.sample( linear_sampler, uv_for_dds).rgb;
    
    float occlusion = specularAO.b;
    float intensity = specularAO.r * constants.specularIntensity;
    float roughness = (specularAO.g / 0.3) * constants.specularRoughness;
    
    float4 out_color = float4(0, 0, 0, 0);
    
    float shadow[4];
    float4 shadow_pos[N_LIGHTS];
    for (int i = 0; i < N_LIGHTS; i++)
    {
        shadow_pos[i] = constants.lights[i].viewProjection * float4(input.world_position, 1);
        shadow_pos[i].xyz /= shadow_pos[i].w;
        //shadow_pos[i].z /= constants.lights[i].farPlane;
    }
    shadow[0] = shadow_maps_1.sample_compare(shadow_sampler, shadow_pos[0].xy, shadow_pos[0].z );
    shadow[1] = shadow_maps_2.sample_compare(shadow_sampler, shadow_pos[1].xy, shadow_pos[1].z);
    shadow[2] = shadow_maps_3.sample_compare(shadow_sampler, shadow_pos[2].xy, shadow_pos[2].z);
    //shadow[0] = Sh
    
    //float4 out_color = vec4(0);
    //float4 out_specular_color = vec4(0);
    
    float3 tL[N_LIGHTS];
    float tSpot[N_LIGHTS];
    //float3 tf1[N_LIGHTS];
    float3 tf2[N_LIGHTS];
    float3 tColor[N_LIGHTS];
    
    for (int i = 0; i < N_LIGHTS; i++)
    {
        constant auto& light = constants.lights[i];
        float3 L = light.position - input.world_position;
        float dist = length(L);
        L /= dist;
        tL[i] = L;
        
        float spot = dot(light.direction, -L);
        tSpot[i] = spot;
        
        //if (spot > light.falloffStart) // DO NOT USE [if], IT'S VERY SLOW !!!!
        {
            float curve = min(pow(dist / light.farPlane, 6.0), 1.0);
            float attenuation = mix(1.0 / (1.0 + light.attenuation * dist * dist), 0.0, curve);
            
            spot = saturate((spot - light.falloffStart) / light.falloffWidth);
            
            float3 f1 = light.color * attenuation * spot;
            float3 f2 = albedo.rgb * f1;
            tf2[i] = f2;
            
            float3 diffuse = saturate(dot(L, normal));
            float specular = intensity * SpecularKSK(beckmann_tex, normal, L, view, roughness, constants.specularFresnel);
            
            //out_color.rgb += shadow[i] * (f2 * diffuse + f1 * specular);
            tColor[i] = shadow[i] * (f2 * diffuse + f1 * specular);
        }
    }
    
    //if (tSpot[0] > constants.lights[0].falloffStart)
        tColor[0] += tf2[0] * SSSSTransmittance(constants.translucency, constants.sssWidth, input.world_position.xyz,
                                                normalize(input.normal), tL[0], shadow_maps_1, constants.lights[0].viewProjection, constants.lights[0].farPlane);
//    if (tSpot[1] > constants.lights[1].falloffStart)
        tColor[1] += tf2[1] * SSSSTransmittance(constants.translucency, constants.sssWidth, input.world_position.xyz,
                                                normalize(input.normal), tL[1], shadow_maps_2, constants.lights[1].viewProjection, constants.lights[1].farPlane);
//    if (tSpot[2] > constants.lights[2].falloffStart)
        tColor[2] += tf2[2] * SSSSTransmittance(constants.translucency, constants.sssWidth, input.world_position.xyz,
                                                normalize(input.normal), tL[2], shadow_maps_3, constants.lights[2].viewProjection, constants.lights[2].farPlane);
    for (int i = 0; i < N_LIGHTS; i++)
        out_color.rgb += tColor[i] * bool(saturate(tSpot[i] - constants.lights[i].falloffStart));
    out_color.rgb += occlusion * constants.ambient * albedo.rgb * irradiance_tex.sample(linear_sampler, normal).rgb;
    
    frag_out_main_pass out;
    out.color = out_color;
    out.depth = input.position.w;
    
    return out;
    //return float4(input.normal, 1.0);
}


// ssss passconstant_ssss_pass
//***********************************************************************
#define SSSS_FOVY 20.0
#define SSSS_STREGTH_SOURCE (colorTex.sample(point_sampler, texcoord).a)
#define SSSSSamplePoint(tex, coord) tex.sample(point_sampler, coord)
#define SSSSSample(tex, coord) tex.sample(linear_sampler, coord)

#define SSSS_QUALITY 0
#if SSSS_QUALITY == 0
#define SSSS_N_SAMPLES 11
constant float4 ssss_kernel[] = {
    float4(0.560479, 0.669086, 0.784728, 0),
    float4(0.00471691, 0.000184771, 5.07566e-005, -2),
    float4(0.0192831, 0.00282018, 0.00084214, -1.28),
    float4(0.03639, 0.0130999, 0.00643685, -0.72),
    float4(0.0821904, 0.0358608, 0.0209261, -0.32),
    float4(0.0771802, 0.113491, 0.0793803, -0.08),
    float4(0.0771802, 0.113491, 0.0793803, 0.08),
    float4(0.0821904, 0.0358608, 0.0209261, 0.32),
    float4(0.03639, 0.0130999, 0.00643685, 0.72),
    float4(0.0192831, 0.00282018, 0.00084214, 1.28),
    float4(0.00471691, 0.000184771, 5.07565e-005, 2)
};
#else
#endif

#define PI 3.1415926536
//constant float INV_PI  = 1.0 / PI;
constant float TO_RADIANS = 1.0 / 180.0 * PI;
#define radians(d) (d * TO_RADIANS)


fragment float4 ssss_pass_frag(constant AAPL::constant_ssss_pass& constants [[ buffer(0) ]],
                               v2f_position_uv input [[stage_in]],
                               texture2d<float> colorTex [[ texture(0) ]],
                               depth2d<float> depthTex [[ texture(1) ]]
                               //texture2d<float> strengthTex [[ texture(2) ]]
                               )
{
    //out_color = SSSSBlurPS(uv, colorTex, depthTex, sssWidth, dir, initStencil);
    float2 texcoord = input.uv;
    
    // Fetch color of current pixel:
    float4 colorM = SSSSSamplePoint(colorTex, texcoord);
    //float4 colorM = colorTex.sample(point_sampler, texcoord);
    
    // Initialize the stencil buffer in case it was not already available:
    //if (constants.initStencil) // (Checked in compile time, it's optimized away)
    //    if (SSSS_STREGTH_SOURCE == 0.0) discard_fragment();
    
    // Fetch linear depth of current pixel:
    //float depthM = SSSSSamplePoint(depthTex, texcoord).r;
    float depthM = 1.0 / SSSSSamplePoint(depthTex, texcoord);
    
    // Calculate the sssWidth scale (1.0 for a unit plane sitting on the
    // projection window):
    float distanceToProjectionWindow = 1.0 / tan(0.5 * radians(SSSS_FOVY));
    float scale = distanceToProjectionWindow / depthM;
    
    // Calculate the final step to fetch the surrounding pixels:
    float2 finalStep = constants.sssWidth * scale * constants.dir;
    finalStep *= SSSS_STREGTH_SOURCE; // Modulate it using the alpha channel.
    finalStep *= 1.0 / 3.0; // Divide by 3 as the kernels range from -3 to 3.
    
    // Accumulate the center sample:
    float4 colorBlurred = colorM;
    colorBlurred.rgb *= ssss_kernel[0].rgb;
    
    // Accumulate the other samples:
    //SSSS_UNROLL
    for (int i = 1; i < SSSS_N_SAMPLES; i++) {
        // Fetch color and d    epth for current sample:
        float2 offset = texcoord + ssss_kernel[i].a * finalStep;
        float4 color = SSSSSample(colorTex, offset);
        
//#if SSSS_FOLLOW_SURFACE == 1
//        // If the difference in depth is huge, we lerp color back to "colorM":
//        float depth = SSSSSample(depthTex, offset).r;
//        float s = SSSSSaturate(300.0f * distanceToProjectionWindow *
//                               sssWidth * abs(depthM - depth));
//        color.rgb = SSSSLerp(color.rgb, colorM.rgb, s);
//#endif
        
        // Accumulate:
        colorBlurred.rgb += ssss_kernel[i].rgb * color.rgb;
    }
    
    return colorBlurred;
}