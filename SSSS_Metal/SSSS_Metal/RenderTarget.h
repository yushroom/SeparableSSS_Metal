//
//  RenderTarget.h
//  SSSS_Metal
//
//  Created by yushroom on 9/9/15.
//  Copyright (c) 2015 Apple Inc. All rights reserved.
//

#ifndef SSSS_Metal_RenderTarget_h
#define SSSS_Metal_RenderTarget_h

#import <Metal/Metal.h>

#include "RenderContex.h"

// A macro to disallow the copy constructor and operator= functions
// This should be used in the private: declarations for a class
#define    DISALLOW_COPY_AND_ASSIGN(TypeName) \
TypeName(const TypeName&);                \
TypeName& operator=(const TypeName&);


class RenderTexture
{
protected:
    DISALLOW_COPY_AND_ASSIGN(RenderTexture)
    
    int _width;
    int _height;
    id <MTLTexture> _texture;
    //id <MTLTexture> _msaa_texture;
    MTLPixelFormat _format;
    
    
public:
    RenderTexture() {}
    virtual ~RenderTexture() {}
    
    int width() const { return _width; }
    int height() const { return _height; }
    
    MTLPixelFormat pixel_format() const { return _format; }
    id <MTLTexture> texture() const { return _texture; }
    //id <MTLTexture> msaa_texture() { return _msaa_texture; };
    
    virtual void init(id <MTLDevice> device, MTLPixelFormat format = MTLPixelFormatRGBA8Unorm, int width = 0, int height = 0)
    {
        _width = width;
        _height = height;
        if (_width == 0) _width = RenderContex::window_width;
        if (_height == 0) _height = RenderContex::window_height;
        _format = format;
        
        auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _format
                                                                       width: _width
                                                                      height: _height
                                                                   mipmapped: NO];
        _texture = [device newTextureWithDescriptor: desc];
        
        //auto msaa_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _format
        //                                                                    width: _width
        //                                                                   height: _height
        //                                                                mipmapped: NO];
        //msaa_desc.textureType = MTLTextureType2DMultisample;
        //msaa_desc.sampleCount = 4;
        //_msaa_texture = [device newTextureWithDescriptor: msaa_desc];
    }
};

class DepthStencil
{
protected:
    DISALLOW_COPY_AND_ASSIGN(DepthStencil)
    
    int _width;
    int _height;
    id <MTLTexture> _depth_texture;
    
    MTLPixelFormat _format = MTLPixelFormatDepth32Float;
    
public:
    
    DepthStencil() {}
    virtual ~DepthStencil() {}
    
    void render_to_screen() const;
    
    id <MTLTexture> get_depth_stencil_texture() const
    {
        return _depth_texture;
    }
    
    MTLPixelFormat pixel_format() const { return _format; }
    
    virtual void init(id <MTLDevice> device, int width = 0, int height = 0)
    {
        _width = width; _height = height;
        if (_width == 0) _width = RenderContex::window_width;
        if (_height == 0) _height = RenderContex::window_height;
        
        auto texture_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _format
                                                                               width: _width
                                                                              height: _height
                                                                           mipmapped: NO];
        _depth_texture = [device newTextureWithDescriptor: texture_desc];

    }
    
    void resize(const int width, const int height);
};


class ShadowMap : DepthStencil
{
protected:
    DISALLOW_COPY_AND_ASSIGN(ShadowMap)
    //id <MTLTexture> _shadow_texture;
    MTLRenderPassDescriptor* _render_pass_desc;
    
public:
    
    static const int SHADOW_MAP_SIZE = 1024;
    
    ShadowMap() {}
    virtual ~ShadowMap() {}
    
    
    MTLPixelFormat pixelFormat() const
    {
        return _depth_texture.pixelFormat;
    }
    
    MTLRenderPassDescriptor* renderPassDescriptor() const
    {
        return _render_pass_desc;
    }
    
    virtual void init(id <MTLDevice> device, int width = 0, int height = 0) override
    {
        DepthStencil::init(device, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE);
        
        _render_pass_desc = [MTLRenderPassDescriptor new];
        auto attachment = _render_pass_desc.depthAttachment;
        attachment.texture = _depth_texture;
        attachment.loadAction = MTLLoadActionClear;
        attachment.storeAction = MTLStoreActionStore;
        attachment.clearDepth = 1.0;
    }
};

#endif
