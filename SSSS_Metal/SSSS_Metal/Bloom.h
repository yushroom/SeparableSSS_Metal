//
//  Bloom.h
//  SSSS_Metal
//
//  Created by yushroom on 9/23/15.
//  Copyright © 2015 Apple Inc. All rights reserved.
//

#ifndef Bloom_h
#define Bloom_h

#include "RenderTarget.h"
#include "RenderContext.h"
#include "Utilities.h"

class Bloom
{
public:
    Bloom() {}
    
    enum ToneMapOperator {
        TONEMAP_LINEAR = 0,
        TONEMAP_EXPONENTIAL = 1,
        TONEMAP_EXPONENTIAL_HSV = 2,
        TONEMAP_REINHARD = 3,
        TONEMAP_FILMIC = 4
    };
    static void static_init()
    {
    }
    
    void init(id<MTLDevice> device,
              ToneMapOperator toneMapOperator, float exposure,
              float bloomThreshold, float bloomWidth, float bloomIntensity,
              float defocus);
    
    void resize(id<MTLDevice> device, int width, int height);
    
    ToneMapOperator getToneMapOperator() const { return toneMapOperator; }
    
    void setExposure(float exposure) { this->exposure = exposure; }
    float getExposure() const { return exposure; }
    
    void setBurnout(float burnout) { this->burnout = burnout; }
    float getBurnout() const { return burnout; }
    
    void setBloomThreshold(float bloomThreshold) { this->bloomThreshold = bloomThreshold; }
    float getBloomThreshold() const { return bloomThreshold; }
    
    void setBloomWidth(float bloomWidth) { this->bloomWidth = bloomWidth; }
    float getBloomWidth() const { return bloomWidth; }
    
    void setBlooomIntensity(float bloomIntensity) { this->bloomIntensity = bloomIntensity; }
    float getBloomIntensity() const { return bloomIntensity; }
    
    void setDefocus(float defocus) { this->defocus = defocus; }
    float getDefocus() const { return defocus; }
    
    bool prepare_pipeline_state(id <MTLDevice> _device, id <MTLLibrary> _defaultLibrary)
    {
        {
            MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
            desc.depthWriteEnabled = NO;
            desc.depthCompareFunction = MTLCompareFunctionAlways;
            _depth_state = [_device newDepthStencilStateWithDescriptor: desc];
        }
        
        auto vert      = _newFunctionFromLibrary(_defaultLibrary, @"quad_vert");
        auto blur_frag    = _newFunctionFromLibrary(_defaultLibrary, @"bloom_blur_frag");
        auto combine_frag = _newFunctionFromLibrary(_defaultLibrary, @"bloom_combine_frag");
        auto glare_detection_frag = _newFunctionFromLibrary(_defaultLibrary, @"bloom_glare_detection_frag");
        
        {
            MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
            NSError *err = nil;
            desc.label = @"Bloom Blur Pass";
            desc.vertexFunction = vert;
            desc.fragmentFunction = blur_frag;
            desc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
            //desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
            _pipeline_state[0] = [_device newRenderPipelineStateWithDescriptor: desc error: &err];
            CheckPipelineError(_pipeline_state[0], err);
            err = nil;

            desc.label = @"Bloom Combine Pass";
            //desc.vertexFunction = vert;
            desc.fragmentFunction = combine_frag;
            //desc.colorAttachments[0].pixelFormat = glareRT.pixel_format();
            _pipeline_state[1] = [_device newRenderPipelineStateWithDescriptor: desc error: &err];
            CheckPipelineError(_pipeline_state[1], err);
            err = nil;

            desc.label = @"Bloom Glare Detection Pass";
            //desc.vertexFunction = vert;
            desc.fragmentFunction = glare_detection_frag;
            //desc.colorAttachments[0].pixelFormat = glareRT.pixel_format();
            _pipeline_state[2] = [_device newRenderPipelineStateWithDescriptor: desc error: &err];
            CheckPipelineError(_pipeline_state[2], err);
        }
        
            
        //Render Pass Desc
        //*********************************************************************
        {
            _render_pass_desc = [MTLRenderPassDescriptor renderPassDescriptor];
            auto color_attachment = _render_pass_desc.colorAttachments[0];
            //color_attachment.texture = _rt_temp.texture();
            color_attachment.loadAction = MTLLoadActionClear;
            color_attachment.storeAction = MTLStoreActionStore;
            color_attachment.clearColor = MTLClearColorMake(1, 0, 0, 1);
        }
        
        return true;
    }
    
    void render(id <MTLCommandBuffer> commandBuffer, RenderTexture *src, RenderTexture *dst);
    
private:

    static const int N_PASSES = 6;
    
    void glareDetection(id <MTLCommandBuffer> commandBuffer, RenderTexture & src);
    void blur(id <MTLCommandBuffer> commandBuffer, RenderTexture * src, RenderTexture * dst, glm::vec2 direction, int i, int j);
    //void toneMap(RenderTexture * src, RenderTexture *dst);
    void combine(id <MTLCommandBuffer> commandBuffer, RenderTexture * src, RenderTexture * dst);
    
    
    ToneMapOperator toneMapOperator;
    float exposure, burnout;
    float bloomThreshold, bloomWidth, bloomIntensity;
    float defocus;
    
    RenderTexture glareRT;
    RenderTexture tmpRT[N_PASSES][2];
    
    id <MTLRenderPipelineState> _pipeline_state[3];
    MTLRenderPassDescriptor*    _render_pass_desc;
    
    id <MTLDepthStencilState>   _depth_state;
    
    //id <MTLBuffer>              _constants_buffer;
    id <MTLBuffer> _constants_buffer_glare;
    id <MTLBuffer> _constants_buffer_blur[N_PASSES][2];
    id <MTLBuffer> _constants_buffer_combine;
};


#endif /* Bloom_h */
