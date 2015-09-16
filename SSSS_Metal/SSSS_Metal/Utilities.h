//
//  Utilities.h
//  SSSS_Metal
//
//  Created by yushroom on 9/9/15.
//  Copyright (c) 2015 Apple Inc. All rights reserved.
//

#ifndef SSSS_Metal_Utilities_h
#define SSSS_Metal_Utilities_h

#include <Metal/Metal.h>
#include <string>
#include <CoreFoundation/CoreFoundation.h>
#include <glm/glm.hpp>
#include <simd/simd.h>

#import <UIKit/UIKit.h>

// typedef
//******************************************************************
struct ImageInfo
{
    uint    width;
    uint    height;
    uint    bitsPerPixel;
    bool    hasAlpha;
    void    *bitmapData;
};

// Path Helper
//******************************************************************
static std::string IOS_bundle_path( CFStringRef subDir, CFStringRef name, CFStringRef ext)
{
    CFURLRef url = CFBundleCopyResourceURL(CFBundleGetMainBundle(), name, ext, subDir);
    UInt8 path[1024];
    CFURLGetFileSystemRepresentation(url, true, path, sizeof(path));
    CFRelease(url);
    return std::string((const char*)path);
}
#define IOS_PATH(subDir, name, ext) IOS_bundle_path(CFSTR(subDir), CFSTR(name), CFSTR(ext))


// Pipeline Error Handling
//******************************************************************
static void CheckPipelineError(id<MTLRenderPipelineState> pipeline, NSError *error)
{
    if (pipeline == nil)
    {
        NSLog(@"Failed to create pipeline. error is %@", [error description]);
        assert(0);
    }
}

//Shader Loading
//***************************************************************
static id<MTLFunction> _newFunctionFromLibrary(id<MTLLibrary> library, NSString *name)
{
    id<MTLFunction> func = [library newFunctionWithName: name];
    if (!func)
    {
        NSLog(@"failed to find function %@ in the library", name);
        assert(0);
    }
    return func;
}


// T: simd type
// U: glm type
template<typename T, typename U>
static T to_simd_type(const U& u)
{
    return reinterpret_cast<T>(u);
}

static simd::float3x3 to_simd_type(const glm::mat3& m)
{
    return simd::float3x3{
        simd::float3{m[0][0], m[0][1], m[0][2]},
        simd::float3{m[1][0], m[1][1], m[1][2]},
        simd::float3{m[2][0], m[2][1], m[2][2]} };
    //return simd::float3x3{ to_simd_type(m[0]), to_simd_type(m[1]), to_simd_type(m[2]) };
}
static simd::float4x4 to_simd_type(const glm::mat4& m)
{
    return simd::float4x4{
        simd::float4{m[0][0], m[0][1], m[0][2], m[0][3] },
        simd::float4{m[1][0], m[1][1], m[1][2], m[1][3] },
        simd::float4{m[2][0], m[2][1], m[2][2], m[2][3] },
        simd::float4{m[3][0], m[3][1], m[3][2], m[3][3] } };
}
static simd::float2 to_simd_type(const glm::vec2& v)
{
    return simd::float2{v.x, v.y};
}
static simd::float3 to_simd_type(const glm::vec3& v)
{
    return simd::float3{v.x, v.y, v.z};
}
static simd::float4 to_simd_type(const glm::vec4& v)
{
    return simd::float4{v.x, v.y, v.z, v.w};
}


#endif
