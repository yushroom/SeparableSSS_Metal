//
//  Utilities.m
//  SSSS_Metal
//
//  Created by yushroom on 9/11/15.
//  Copyright (c) 2015 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <Utilities.h>

// TextureLoader
#include <Metal/Metal.h>
#include <gli/gli.hpp>

//@implementation TextureLoader
//
//+ (id <MTLTexture>)loadCubeTextureWithName: (const char*)name device: (id <MTLDevice>) device
//{
//    ImageInfo tex_info;
//    CreateImageInfo(name, tex_info);
//    
//    if (tex_info.bitmapData == NULL) return nil;
//    
//    if (tex_info.hasAlpha == 0)
//    {
//        RGB8ImageToRGBA8(&tex_info);
//    }
//    
//    unsigned Npixels = tex_info.width * tex_info.width;
//    id<MTLTexture> texture = [device newTextureWithDescriptor: [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat: MTLPixelFormatRGBA8Unorm size: tex_info.width mipmapped: NO]];
//    
////    for (int i = 0; i < 6; i++)
////    {
////        [texture replaceRegion:MTLRegionMake2D(0, 0, tex_info.width, tex_info.width)
////                   mipmapLevel:0
////                         slice:i
////                     withBytes:(uint8_t *)(tex_info.bitmapData) + (i * Npixels * 4)
////                   bytesPerRow:4 * tex_info.width
////                 bytesPerImage:Npixels * 4];
////    }
//    for (int i = 0; i < 6; i++)
//    {
//        [texture replaceRegion:MTLRegionMake2D(0, 0, tex_info.width, tex_info.width)
//                   mipmapLevel:0
//                         slice:i
//                     withBytes:(uint8_t *)(tex_info.bitmapData) + (i * Npixels * 4)
//                   bytesPerRow:4 * tex_info.width
//                 bytesPerImage:Npixels * 4];
//    }
//    
//    free(tex_info.bitmapData);
//    
//    return texture;
//}
//
//+ (id <MTLTexture>)loadDDSCubeTextureWithName: (const char*)name device: (id <MTLDevice>) device
//{
//    gli::textureCube texture(gli::load_dds(name));
//    assert(!texture.empty());
//    //printf("%d %d\n", texture.levels(), texture.layers());
//    gli::gl GL;
//    gli::gl::format const format = GL.translate(texture.format());
//    printf("%s\n\t%X %X %X\n", name, format.Internal, format.External, format.Type);
//    
//    assert(!gli::is_compressed(texture.format()));
//    
//    unsigned long w = texture[0][0].dimensions().x;
//    unsigned long h = texture[0][0].dimensions().y;
//    
//    id<MTLTexture> mtltexture = [device newTextureWithDescriptor: [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat: MTLPixelFormatRGBA16Float size: w mipmapped: NO]];
//    
//    for (int face = 0; face < 6; face++)
//    {
//        auto t = texture[face][0];
//        //unsigned long w = t.dimensions().x;
//        //unsigned long h = t.dimensions().y;
//        [mtltexture replaceRegion: MTLRegionMake2D(0, 0, w, h)
//                   mipmapLevel: 0
//                         slice: face
//                     withBytes: t.data()
//                   bytesPerRow: 4 * 2 * w
//                 bytesPerImage: w * h * 4 * 2];
//    }
//    return mtltexture;
//}
//
//@end