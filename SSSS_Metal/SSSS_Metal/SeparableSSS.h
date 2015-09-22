//
//  SeparableSSS.h
//  SSSS_Metal
//
//  Created by yushroom on 9/18/15.
//  Copyright (c) 2015 Apple Inc. All rights reserved.
//

#ifndef __SSSS_Metal__SeparableSSS__
#define __SSSS_Metal__SeparableSSS__

#import <Metal/Metal.h>
#include <glm/glm.hpp>

#include "Model.h"
#include "RenderTarget.h"
#include "Utilities.h"
#include "AAPLSharedTypes.h"

#define SSS_N_SAMPLES 17

class SeparableSSS
{
public:
    SeparableSSS() {};
    
    void init(
              //int width, int height,
              id<MTLDevice> device,
              float fovy, float sssWidth, int nSamples = 17, bool stencilInitialized = true,
              bool followShape = true, bool separateStrengthSource = false)
    {
        //_width = width;
        //_height = height;
        this->sssWidth = sssWidth;
        this->nSamples = nSamples;
        this->stencilInitialized = stencilInitialized;
        this->strength = glm::vec3(0.48f, 0.41f, 0.28f);
        this->falloff = glm::vec3(1.0f, 0.37f, 0.3f);
        
        _rt_temp.init(device, MTLPixelFormatRGBA8Unorm, RenderContext::window_width, RenderContext::window_height);
        //calculate_kernel();
        
        for (int i = 0; i < 2; i++)
        {
            _constants_buffer[i] = [device newBufferWithLength: sizeof(AAPL::constant_ssss_pass) options:0];
            _constants_buffer[i].label = [NSString stringWithFormat: @"ssss_pass_constant_buffer%i", i];
            auto buffer = (AAPL::constant_ssss_pass*)[_constants_buffer[i] contents];
            buffer->sssWidth = this->sssWidth;
            //buffer->dir = {1.0f, 0.0f};
            buffer->initStencil = false;
        }
        auto buffer = (AAPL::constant_ssss_pass*)[_constants_buffer[0] contents];
        buffer->dir = {1.0f, 0.0f};
        buffer = (AAPL::constant_ssss_pass*)[_constants_buffer[1] contents];
        buffer->dir = {0.0f, 1.0f};
        
    }
    
    void resize(int width, int height)
    {
        // TODO
        //_tmpRT.resize(width, height);
    }
    
    static void static_init()
    {
        //shader.init(IOS_PATH("shader", "Quad", "vert"), IOS_PATH("shader", "SSSS", "frag"));
    }
    
    void render(id <MTLCommandBuffer> commandBuffer, RenderTexture & colorTex, RenderTexture & depthTex, DepthStencil & depthStencilRT) const
    {
        {
            auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc[0]];
            [encoder pushDebugGroup:@"SSSSPass0"];
            encoder.label = @"ssss pass0";
            [encoder setDepthStencilState: _depth_state];
            [encoder setRenderPipelineState: _pipeline_state];
            [encoder setCullMode: MTLCullModeNone];
            
            [encoder setFragmentBuffer:_constants_buffer[0] offset:0 atIndex:0];
            [encoder setFragmentTexture: colorTex.texture() atIndex:0];
            [encoder setFragmentTexture: depthTex.texture() atIndex:1];
            ModelManager::screen_aligned_quad.render(encoder);
            
            [encoder popDebugGroup];
            [encoder endEncoding];
        }
        {
            auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc[1]];
            [encoder pushDebugGroup:@"SSSSPass1"];
            encoder.label = @"ssss pass1";
            [encoder setDepthStencilState: _depth_state];
            [encoder setRenderPipelineState: _pipeline_state];
            [encoder setCullMode: MTLCullModeNone];
            
            [encoder setFragmentBuffer:_constants_buffer[1] offset:0 atIndex:0];
            [encoder setFragmentTexture: _rt_temp.texture() atIndex:0];
            [encoder setFragmentTexture: depthTex.texture() atIndex:1];
            ModelManager::screen_aligned_quad.render(encoder);
            
            [encoder popDebugGroup];
            [encoder endEncoding];
        }
        
    }
    
    /**
     * This parameter specifies the global level of subsurface scattering,
     * or in other words, the width of the filter.
     */
    void setWidth(float width)
    {
        this->sssWidth = width;
        auto buffer = (AAPL::constant_ssss_pass*)[_constants_buffer[0] contents];
        buffer->sssWidth = this->sssWidth;
        buffer = (AAPL::constant_ssss_pass*)[_constants_buffer[1] contents];
        buffer->sssWidth = this->sssWidth;

    }
    float getWidth() const { return sssWidth; }
    
    /**
     * @STRENGTH
     *
     * This parameter specifies the how much of the diffuse light gets into
     * the skin, and thus gets modified by the SSS mechanism.
     *
     * It can be seen as a per-channel mix factor between the original
     * image, and the SSS-filtered image.
     */
    void setStrength(vec3 strength)
    {
        if (glm::distance(strength, this->strength) > 0.1f)
        {
            this->strength = strength;
            //calculate_kernel();
        }
        
    }
    vec3 getStrength() const { return strength; }
    
    /**
     * This parameter defines the per-channel falloff of the gradients
     * produced by the subsurface scattering events.
     *
     * It can be used to fine tune the color of the gradients.
     */
    void setFalloff(vec3 falloff)
    {
        if (glm::distance(falloff, this->falloff) > 0.1f)
        {
            this->falloff = falloff;
            //calculate_kernel();
        }
        
    }
    vec3 getFalloff() const { return falloff; }
    
    bool prepare_pipeline_state(id <MTLDevice> _device, id <MTLLibrary> _defaultLibrary, RenderTexture& _rt_main)
    {
        {
            MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
            desc.depthWriteEnabled = NO;
            desc.depthCompareFunction = MTLCompareFunctionAlways;
            _depth_state = [_device newDepthStencilStateWithDescriptor: desc];
        }
        
        auto vert      = _newFunctionFromLibrary(_defaultLibrary, @"quad_vert");
        auto frag      = _newFunctionFromLibrary(_defaultLibrary, @"ssss_pass_frag");
        
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        NSError *err = nil;
        desc.label = @"SSSS Pass";
        desc.vertexFunction = vert;
        desc.fragmentFunction = frag;
        desc.colorAttachments[0].pixelFormat = _rt_main.pixel_format();
        //desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        _pipeline_state = [_device newRenderPipelineStateWithDescriptor: desc error: &err];
        CheckPipelineError(_pipeline_state, err);
        
        //Render Pass Desc
        //*********************************************************************
        {
            _render_pass_desc[0] = [MTLRenderPassDescriptor renderPassDescriptor];
            auto color_attachment = _render_pass_desc[0].colorAttachments[0];
            color_attachment.texture = _rt_temp.texture();
            color_attachment.loadAction = MTLLoadActionClear;
            color_attachment.storeAction = MTLStoreActionStore;
            color_attachment.clearColor = MTLClearColorMake(1, 0, 0, 1);
        }
        {
            _render_pass_desc[1] = [MTLRenderPassDescriptor renderPassDescriptor];
            auto color_attachment = _render_pass_desc[1].colorAttachments[0];
            color_attachment.texture = _rt_main.texture();
            color_attachment.loadAction = MTLLoadActionClear;
            color_attachment.storeAction = MTLStoreActionStore;
            color_attachment.clearColor = MTLClearColorMake(1, 0, 0, 1);
        }
        
        return true;
    }
    
    
    
private:
    
    float sssWidth;
    int nSamples;
    bool stencilInitialized;
    glm::vec3 strength;
    glm::vec3 falloff;
    
    RenderTexture _rt_temp;
    
    id <MTLRenderPipelineState> _pipeline_state;
    MTLRenderPassDescriptor*    _render_pass_desc[2];
    
    id <MTLDepthStencilState>   _depth_state;
    
    id <MTLBuffer>              _constants_buffer[2];
    
};

#endif /* defined(__SSSS_Metal__SeparableSSS__) */
