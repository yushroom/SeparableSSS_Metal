/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Shared data types between CPU code and metal shader code
 */

#ifndef _AAPL_SHARED_TYPES_H_
#define _AAPL_SHARED_TYPES_H_

#include <simd/simd.h>
using namespace simd;

#ifdef IN_METAL_FILE
#include <simd/simd.h>
typedef simd::float3x3 mat3;
typedef simd::float4x4 mat4;
typedef simd::float2 vec2;
typedef simd::float3 vec3;
typedef simd::float4 vec4;
#else
//#include <glm/glm.hpp>
//typedef glm::mat3 float3x3;
//typedef glm::mat4 float4x4;
//typedef glm::vec2 float2;
//typedef glm::vec3 float3;
//typedef glm::vec4 float4;
//using glm::mat3;
//using glm::mat4;
//using glm::vec4;
//using glm::vec3;
#endif

#ifdef __cplusplus

namespace AAPL
{
    typedef struct
    {
        float4x4 MVP;
        float4x4 normal_matrix;
    } constants_t;
    
    // for Shdow pass
    struct constants_mvp
    {
        float4x4 MVP;
    };
    
    struct SLight {
        float4x4 viewProjection;
        float3 position;
        float3 direction;
        float3 color;
        float falloffStart;
        float falloffWidth;
        float attenuation;
        float farPlane;
        float bias;
    };
    
    struct constant_main_pass
    {
        float4x4 MVP;
        float4x4 Model;
        float4x4 ModelInverseTranspose;
        float4 camera_position;
        // vec2 jitter;
        
        float bumpiness;	// for normal map
        float specularIntensity;
        float specularRoughness;
        float specularFresnel;
        float translucency;
        float sssWidth;
        float ambient;
        
        bool sssEnabled;
        bool sssTranslucencyEnabled;
        bool separate_speculars;
        
        SLight lights[3];
    };
}


#endif

#endif