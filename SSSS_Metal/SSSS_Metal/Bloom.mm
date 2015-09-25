//#include <algorithm>
#include <sstream>
#include <cstdio>

#include <glm/glm.hpp>
#include "Bloom.h"
#include "Debug.h"
#include "AAPLSharedTypes.h"
#include "Utilities.h"
#include "Model.h"

using namespace std;

using glm::vec2;
using glm::vec3;


void Bloom::init(id<MTLDevice> device, ToneMapOperator toneMapOperator, float exposure, float bloomThreshold, float bloomWidth, float bloomIntensity, float defocus)
{
    
    this->toneMapOperator = toneMapOperator;
    this->exposure = exposure;
    this->burnout = numeric_limits<float>::infinity();
    this->bloomThreshold = bloomThreshold;
    this->bloomWidth = bloomWidth;
    this->bloomIntensity = bloomIntensity;
    this->defocus = defocus;
    
    int w = RenderContext::window_width;
    int h = RenderContext::window_height;
    resize(device, w, h);
}

void Bloom::resize(id<MTLDevice> device, int width, int height)
{
    glareRT.init(device, MTLPixelFormatRGBA8Unorm, width / 2, height / 2);
    
    int base = 2;
    for (int i = 0; i < N_PASSES; i++)
    {
        _constants_buffer_blur[i][0] = [device newBufferWithLength:sizeof(AAPL::constant_bloom_pass_blur) options:0];
        _constants_buffer_blur[i][1] = [device newBufferWithLength:sizeof(AAPL::constant_bloom_pass_blur) options:0];
        //_constants_buffer_blur[i][0].label = @"bloom_pass_constant_buffer_combine";
        //_constants_buffer_blur[i][1].label = @"bloom_pass_constant_buffer_combine";
        
        auto buffer = (AAPL::constant_bloom_pass_blur*)[_constants_buffer_blur[i][0] contents];
        buffer->step = to_simd_type(vec2(1.0f / std::max(width / base, 1), 1.0f / std::max(height / base, 1)) * bloomWidth * vec2(1, 0));
        
        buffer = (AAPL::constant_bloom_pass_blur*)[_constants_buffer_blur[i][1] contents];
        buffer->step = to_simd_type(vec2(1.0f / std::max(width / base, 1), 1.0f / std::max(height / base, 1)) * bloomWidth * vec2(0, 1));
        
        _constants_buffer_glare.label = @"bloom_pass_constant_buffer_glare";
        
        tmpRT[i][0].init(device, MTLPixelFormatRGBA8Unorm, std::max(width / base, 1), std::max(height / base, 1));
        tmpRT[i][1].init(device, MTLPixelFormatRGBA8Unorm, std::max(width / base, 1), std::max(height / base, 1));
        base *= 2;
    }
    
    {
        _constants_buffer_glare = [device newBufferWithLength:sizeof(AAPL::constant_bloom_pass_glare) options:0];
        _constants_buffer_glare.label = @"bloom_pass_constant_buffer_glare";
        auto buffer = (AAPL::constant_bloom_pass_glare*)[_constants_buffer_glare contents];
        buffer->pixelSize = { 1.0f / (width / 2), 1.0f / (height / 2)};
        buffer->bloomThreshold = this->bloomThreshold;
        buffer->exposure = this->exposure;
    }
    {
        _constants_buffer_combine = [device newBufferWithLength:sizeof(AAPL::constant_bloom_pass_combine) options:0];
        _constants_buffer_combine.label = @"bloom_pass_constant_buffer_combine";
        auto buffer = (AAPL::constant_bloom_pass_combine*)[_constants_buffer_combine contents];
        buffer->pixelSize = {1.0f / width, 1.0f / height};
        buffer->exposure = this->exposure;
        buffer->bloomIntensity = this->bloomIntensity;
        buffer->defocus = this->defocus;
    }
}

void Bloom::render(id <MTLCommandBuffer> commandBuffer, RenderTexture *src, RenderTexture *dst)
{
    if (bloomIntensity > 0.0f)
    {
        glareDetection(commandBuffer, *src);
        //glareRT.render_to_screen();
        
        RenderTexture* current = &glareRT;
        for (int i = 0; i < N_PASSES; i++)
        {
            blur(commandBuffer, current, &tmpRT[i][0], vec2(1.0f, 0.0f), i, 0);		// horizontal
            blur(commandBuffer, &tmpRT[i][0], &tmpRT[i][1], vec2(0.0, 1.0f), i, 1);	// vertical
            
            current = &tmpRT[i][1];
        }
        
        combine(commandBuffer, src, dst);
    }
    else
    {
        //toneMap(src, dst);
        Debug::LogError("ERROR, no toneMap");
    }
}


void Bloom::glareDetection(id <MTLCommandBuffer> commandBuffer, RenderTexture & src)
{
    int w = glareRT.width();
    int h = glareRT.height();
    
    _render_pass_desc.colorAttachments[0].texture = glareRT.texture();
    auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc];
    [encoder pushDebugGroup:@"BloomGlarePass"];
    encoder.label = @"bloom glare pass";
    
//    vec2 pixelSize = vec2(1.0f / w, 1.0f / h);
//    auto buffer = (AAPL::constant_bloom_pass*)[_constants_buffer contents];
//    buffer->pixelSize = to_simd_type(pixelSize);
    
    [encoder setViewport: MTLViewport{0, 0, static_cast<double>(w), static_cast<double>(h)}];
    [encoder setDepthStencilState: _depth_state];
    [encoder setRenderPipelineState: _pipeline_state[2]];
    [encoder setCullMode: MTLCullModeNone];
    [encoder setFragmentBuffer: _constants_buffer_glare offset:0 atIndex:0];
    [encoder setFragmentTexture: src.texture() atIndex:0];
    
    ModelManager::screen_aligned_quad.render(encoder);
    
    [encoder popDebugGroup];
    [encoder endEncoding];
}

void Bloom::blur(id <MTLCommandBuffer> commandBuffer, RenderTexture * src, RenderTexture * dst, glm::vec2 direction, int i, int j)
{
    int w = dst->width();
    int h = dst->height();
    
    _render_pass_desc.colorAttachments[0].texture = dst->texture();
    auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc];
    [encoder pushDebugGroup:@"BloomBlurPass"];
    encoder.label = @"bloom blur pass";
    
//    vec2 pixelSize = vec2(1.0f / w, 1.0f / h);
//    vec2 step = pixelSize * bloomWidth * direction;
//    auto buffer = (AAPL::constant_bloom_pass*)[_constants_buffer contents];
//    buffer->step = to_simd_type(step);
    
    [encoder setViewport: MTLViewport{0, 0, static_cast<double>(w), static_cast<double>(h)}];
    [encoder setDepthStencilState: _depth_state];
    [encoder setRenderPipelineState: _pipeline_state[0]];
    [encoder setCullMode: MTLCullModeNone];
    [encoder setFragmentBuffer: _constants_buffer_blur[i][j] offset:0 atIndex:0];
    [encoder setFragmentTexture: src->texture() atIndex:0];
    
    ModelManager::screen_aligned_quad.render(encoder);
    
    [encoder popDebugGroup];
    [encoder endEncoding];
}

void Bloom::combine(id <MTLCommandBuffer> commandBuffer, RenderTexture *src, RenderTexture *dst)
{
    int w = RenderContext::window_width;
    int h = RenderContext::window_height;
    
    _render_pass_desc.colorAttachments[0].texture = dst->texture();
    auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc];
    [encoder pushDebugGroup:@"BloomCombinePass"];
    encoder.label = @"bloom combine pass";
    
//    vec2 pixelSize = vec2(1.0f / w, 1.0f / h);
//    auto buffer = (AAPL::constant_bloom_pass*)[_constants_buffer contents];
//    buffer->pixelSize = to_simd_type(pixelSize);
    
    [encoder setViewport: MTLViewport{0, 0, static_cast<double>(w), static_cast<double>(h)}];
    [encoder setDepthStencilState: _depth_state];
    [encoder setRenderPipelineState: _pipeline_state[1]];
    [encoder setCullMode: MTLCullModeNone];
    [encoder setFragmentBuffer: _constants_buffer_combine offset:0 atIndex:0];
    [encoder setFragmentTexture: src->texture() atIndex:0];
    for (int i = 0; i < N_PASSES; i++) {
        [encoder setFragmentTexture: tmpRT[i][1].texture() atIndex: i + 1];
    }
    
    ModelManager::screen_aligned_quad.render(encoder);
    
    [encoder popDebugGroup];
    [encoder endEncoding];
    
}


