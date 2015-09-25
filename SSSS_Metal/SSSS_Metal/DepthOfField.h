//
//  DepthOfField.hpp
//  SSSS_Metal
//
//  Created by yushroom on 9/24/15.
//  Copyright © 2015 Apple Inc. All rights reserved.
//

#ifndef DepthOfField_h
#define DepthOfField_h

#include "RenderTarget.h"
#include "RenderContext.h"
#include "AAPLSharedTypes.h"
#include "Model.h"

class DepthOfField
{
    public:
    DepthOfField()
    {
        
    }
    
    ~DepthOfField()
    {
    }
    
    static void static_init()
    {
        //shader_coc.init(IOS_PATH("shader", "Quad", "vert"), IOS_PATH("shader", "DepthOfField_coc", "frag"));
        //shader_blur.init(IOS_PATH("shader", "Quad", "vert"), IOS_PATH("shader", "DepthOfField_blur", "frag"));
    }
    
    void init(id<MTLDevice> device, float focusDistance, float focusRange, const glm::vec2 &focusFalloff, float blurWidth)
    {
        _focus_distance = focusDistance;
        _focus_range = focusRange;
        _focus_falloff = focusFalloff;
        _blur_width = blurWidth;
        
        int w = RenderContext::window_width;
        int h = RenderContext::window_height;
        _rt_temp.init(device, MTLPixelFormatRGBA8Unorm, w, h);
        _rt_coc.init(device, MTLPixelFormatR8Unorm, w, h);
        
        _constants_buffer_coc = [device newBufferWithLength:sizeof(AAPL::constant_dof_pass_coc) options:0];
        _constants_buffer_blur[0] = [device newBufferWithLength:sizeof(AAPL::constant_dof_pass_blur) options:0];
        _constants_buffer_blur[1] = [device newBufferWithLength:sizeof(AAPL::constant_dof_pass_blur) options:0];
        
        {
            auto buffer = (AAPL::constant_dof_pass_coc*)[_constants_buffer_coc contents];
            buffer->focusDistance = focusDistance;
            buffer->focusRange = focusRange;
            buffer->focusFalloff = to_simd_type(focusFalloff);
        }
        vec2 pixel_size(1.0f / RenderContext::window_width, 1.0f / RenderContext::window_height);
        vec2 step = pixel_size * _blur_width;

        {
            auto buffer = (AAPL::constant_dof_pass_blur*)[_constants_buffer_blur[0] contents];
            buffer->step = {step.x, 0};
        }
        {
            auto buffer = (AAPL::constant_dof_pass_blur*)[_constants_buffer_blur[1] contents];
            buffer->step = {0, step.y};
        }
        
    }
    
//    void resize(int width, int height)
//    {
//        _rt_temp.resize(width, height);
//        _rt_coc.resize(width, height);
//    }
    bool prepare_pipeline_state(id <MTLDevice> _device, id <MTLLibrary> _defaultLibrary)
    {
        {
            MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
            desc.depthWriteEnabled = NO;
            desc.depthCompareFunction = MTLCompareFunctionAlways;
            _depth_state = [_device newDepthStencilStateWithDescriptor: desc];
        }
        
        auto vert      = _newFunctionFromLibrary(_defaultLibrary, @"quad_vert");
        auto blur_frag    = _newFunctionFromLibrary(_defaultLibrary, @"dof_blur_frag");
        auto coc_frag = _newFunctionFromLibrary(_defaultLibrary, @"dof_coc_frag");
        
        {
            MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
            NSError *err = nil;
            desc.label = @"DOF Blur Pass";
            desc.vertexFunction = vert;
            desc.fragmentFunction = blur_frag;
            desc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
            //desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
            _pipeline_state[0] = [_device newRenderPipelineStateWithDescriptor: desc error: &err];
            CheckPipelineError(_pipeline_state[0], err);
            err = nil;
            
            desc.label = @"DOF CoC Pass";
            //desc.vertexFunction = vert;
            desc.fragmentFunction = coc_frag;
            desc.colorAttachments[0].pixelFormat = MTLPixelFormatR8Unorm;
            //desc.colorAttachments[0].pixelFormat = glareRT.pixel_format();
            _pipeline_state[1] = [_device newRenderPipelineStateWithDescriptor: desc error: &err];
            CheckPipelineError(_pipeline_state[1], err);
            err = nil;
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

    
    void render(id <MTLCommandBuffer> commandBuffer, RenderTexture & src, RenderTexture & dst, RenderTexture & depth_texture)
    {
        //glViewport(0, 0, RenderContext::window_width, RenderContext::window_height);
        coc(commandBuffer, depth_texture, _rt_coc);
        blur(commandBuffer, src, _rt_temp, dof_blur_horizon);
        blur(commandBuffer, _rt_temp, dst, dof_blur_vertical);
    }
    
    void set_focus_range(float focus_range)
    {
        _focus_range = focus_range;
        auto buffer = (AAPL::constant_dof_pass_coc*)[_constants_buffer_coc contents];
        //buffer->focusDistance = focusDistance;
        buffer->focusRange = focus_range;
        //buffer->focusFalloff = to_simd_type(focusFalloff);

    }
    
    void set_focus_falloff(float focus_falloff)
    {
        _focus_falloff.x = _focus_falloff.y = focus_falloff;
        auto buffer = (AAPL::constant_dof_pass_coc*)[_constants_buffer_coc contents];
        //buffer->focusDistance = focusDistance;
        ///buffer->focusRange = focus_range;
        buffer->focusFalloff = {focus_falloff, focus_falloff};
    }
    
    void set_focus_distance(float focus_distance)
    {
        _focus_distance = focus_distance;
        auto buffer = (AAPL::constant_dof_pass_coc*)[_constants_buffer_coc contents];
        buffer->focusDistance = focus_distance;
    }
    
    private:
    
    enum dof_blur_mode{dof_blur_horizon, dof_blur_vertical};
    
    void blur(id <MTLCommandBuffer> commandBuffer, RenderTexture & src, RenderTexture & dst, dof_blur_mode mode)
    {
        _render_pass_desc.colorAttachments[0].texture = dst.texture();
        auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc];
        [encoder pushDebugGroup:@"DOFBlurPass"];
        encoder.label = @"DOF blur pass";
        
        //[encoder setViewport: MTLViewport{0, 0, static_cast<double>(w), static_cast<double>(h)}];
        [encoder setDepthStencilState: _depth_state];
        [encoder setRenderPipelineState: _pipeline_state[0]];
        [encoder setCullMode: MTLCullModeNone];
        
        if (dof_blur_vertical == mode)
            [encoder setFragmentBuffer: _constants_buffer_blur[1] offset:0 atIndex:0];
        else
            [encoder setFragmentBuffer: _constants_buffer_blur[0] offset:0 atIndex:0];
        
        [encoder setFragmentTexture: src.texture() atIndex:0];
        [encoder setFragmentTexture: _rt_coc.texture() atIndex:1];
        
        ModelManager::screen_aligned_quad.render(encoder);
        
        [encoder popDebugGroup];
        [encoder endEncoding];
    }
    
    void coc(id <MTLCommandBuffer> commandBuffer, RenderTexture & depth_texture, RenderTexture & dst)
    {
        _render_pass_desc.colorAttachments[0].texture = dst.texture();
        auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc];
        [encoder pushDebugGroup:@"DOFCoCPass"];
        encoder.label = @"DOF CoC pass";
        
        //[encoder setViewport: MTLViewport{0, 0, static_cast<double>(w), static_cast<double>(h)}];
        [encoder setDepthStencilState: _depth_state];
        [encoder setRenderPipelineState: _pipeline_state[1]];
        [encoder setCullMode: MTLCullModeNone];

        [encoder setFragmentBuffer: _constants_buffer_coc offset:0 atIndex:0];
        [encoder setFragmentTexture: depth_texture.texture() atIndex:0];
        
        ModelManager::screen_aligned_quad.render(encoder);
        
        [encoder popDebugGroup];
        [encoder endEncoding];
    }
    

    float _blur_width;
    float _focus_distance;
    float _focus_range;
    glm::vec2 _focus_falloff;
    
private:
//    static Shader shader_coc;
//    static Shader shader_blur;
    
    id <MTLRenderPipelineState> _pipeline_state[2];
    MTLRenderPassDescriptor*    _render_pass_desc;
    
    id <MTLDepthStencilState>   _depth_state;
    
    id <MTLBuffer> _constants_buffer_coc;
    id <MTLBuffer> _constants_buffer_blur[2];
    
    RenderTexture _rt_temp;
    RenderTexture _rt_coc;
};


#endif /* DepthOfField_h */
