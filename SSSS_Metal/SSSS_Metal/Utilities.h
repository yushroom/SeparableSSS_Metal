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





///////////////////////////////////////////////////////////
//// Texture loading and conversion
//static void RGB8ImageToRGBA8(ImageInfo *tex_info)
//{
//    
//    assert(tex_info != NULL);
//    assert(tex_info->bitsPerPixel == 24);
//    
//    NSUInteger stride = tex_info->width * 4;
//    void *newPixels = malloc(stride * tex_info->height);
//    
//    uint32_t *dstPixel = static_cast<uint32_t *>(newPixels);
//    uint8_t r, g, b, a;
//    a = 255;
//    
//    NSUInteger sourceStride = tex_info->width * tex_info->bitsPerPixel / 8;
//    
//    for (int j = 0; j < tex_info->height; j++)
//    {
//        for (int i = 0; i < sourceStride; i += 3)
//        {
//            uint8_t *srcPixel = (uint8_t *)(tex_info->bitmapData) + i + (sourceStride * j);
//            r = *srcPixel;
//            srcPixel++;
//            g = *srcPixel;
//            srcPixel++;
//            b = *srcPixel;
//            srcPixel++;
//            
//            *dstPixel = (static_cast<uint32_t>(a) << 24 | static_cast<uint32_t>(b) << 16 | static_cast<uint32_t>(g) << 8 | static_cast<uint32_t>(r));
//            dstPixel++;
//            
//        }
//    }
//    
//    free(tex_info->bitmapData);
//    tex_info->bitmapData = static_cast<unsigned char *>(newPixels);
//    tex_info->hasAlpha = true;
//    tex_info->bitsPerPixel = 32;
//}
//
//static void CreateImageInfo(const char *name, ImageInfo &tex_info)
//{
//    tex_info.bitmapData = NULL;
//    
//    UIImage* baseImage = [UIImage imageWithContentsOfFile: [NSString stringWithUTF8String: name]];
//    CGImageRef image = baseImage.CGImage;
//    
//    if (!image)
//    {
//        return;
//    }
//    
//    tex_info.width = (uint)CGImageGetWidth(image);
//    tex_info.height = (uint)CGImageGetHeight(image);
//    tex_info.bitsPerPixel = (uint)CGImageGetBitsPerPixel(image);
//    tex_info.hasAlpha = CGImageGetAlphaInfo(image) != kCGImageAlphaNone;
//    uint sizeInBytes = tex_info.width * tex_info.height * tex_info.bitsPerPixel / 8;
//    uint bytesPerRow = tex_info.width * tex_info.bitsPerPixel / 8;
//    
//    tex_info.bitmapData = malloc(sizeInBytes);
//    CGContextRef context = CGBitmapContextCreate(tex_info.bitmapData, tex_info.width, tex_info.height, 8, bytesPerRow, CGImageGetColorSpace(image), CGImageGetBitmapInfo(image));
//    
//    CGContextDrawImage(context, CGRectMake(0, 0, tex_info.width, tex_info.height), image);
//    
//    CGContextRelease(context);
//    
//}

// Texture Loader
//***************************************************************
//@interface TextureLoader : NSObject
//
//+ (id <MTLTexture>)loadCubeTextureWithName: (const char*)name device: (id <MTLDevice>) device;
//
//+ (id <MTLTexture>)loadDDSCubeTextureWithName: (const char*)name device: (id <MTLDevice>) device;
//
//@end

#endif
