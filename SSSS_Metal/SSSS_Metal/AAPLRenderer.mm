/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Metal Renderer for Metal Basic 3D. Acts as the update and render delegate for the view controller and performs rendering. In MetalBasic3D, the renderer draws 2 cubes, whos color values change every update.
 */

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#import "AAPLRenderer.h"
#import "AAPLViewController.h"
#import "AAPLView.h"
#import "AAPLTransforms.h"
#import "AAPLSharedTypes.h"

#include "RenderContext.h"
#include "Utilities.h"
#include "Model.h"
#include "TextureLoader.h"

#include "RenderTarget.h"

#include "Camera.h"
#include "Light.hpp"

#include "SeparableSSS.h"

#define CAMERA_FOV 20.0f
#define PI 3.1415926536f

#define N_LIGHTS 3

using namespace AAPL;
using namespace simd;

@implementation AAPLRenderer
{
    CFTimeInterval              _frameTime;
    // constant synchronization for buffering <kInFlightCommandBuffers> frames
    dispatch_semaphore_t        _inflight_semaphore;
    id <MTLBuffer>              _shadow_pass_buffer[kInFlightCommandBuffers][N_LIGHTS];
    id <MTLBuffer>              _sky_pass_buffer[kInFlightCommandBuffers];
    id <MTLBuffer>              _main_pass_buffer[kInFlightCommandBuffers];
    
    // renderer global ivars
    id <MTLDevice>              _device;
    id <MTLCommandQueue>        _commandQueue;
    id <MTLLibrary>             _defaultLibrary;
    id <MTLRenderPipelineState> _pipeline_main_pass;
    id <MTLRenderPipelineState> _pipeline_shadow_pass;
    id <MTLRenderPipelineState> _pipeline_skydome;
    id <MTLRenderPipelineState> _pipeline_quad;
    
    //MTLRenderPassDescriptor*    _render_pass_desc_texture_to_screen;
    MTLRenderPassDescriptor*    _render_pass_desc_skydome;
    MTLRenderPassDescriptor*    _render_pass_desc_main;
    
    id <MTLDepthStencilState>   _depth_state_none;
    id <MTLDepthStencilState>   _depth_state_shadow;
    id <MTLDepthStencilState>   _depth_state_main;
    id <MTLDepthStencilState>   _depth_state_sky;
    id <MTLDepthStencilState>   _depth_state_ssss;
    
    DepthStencil    _depth_stencil;
    RenderTexture   _rt_main;
    RenderTexture   _rt_depth;
    
    Model       _model_head;
    Model       _model_sphere;
    Model       _model_quad;
    Camera      _camera;
    Light       _lights[N_LIGHTS];
    
    bool        enable_ssss;
    
    SeparableSSS ssss;
    
    id <MTLTexture>     _tex_sky;
    id <MTLTexture>     _tex_head_diffuse;
    id <MTLTexture>     _tex_head_specularAO;
    id <MTLTexture>     _tex_head_normal_map;
    id <MTLTexture>     _tex_sky_irradiance_map;
    id <MTLTexture>     _tex_beckmann;
    
    // this value will cycle from 0 to g_max_inflight_buffers whenever a display completes ensuring renderer clients
    // can synchronize between g_max_inflight_buffers count buffers, and thus avoiding a constant buffer from being overwritten between draws
    //NSUInteger _constantDataBufferIndex;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        RenderContext::current_buffer_index = 0;
        _inflight_semaphore = dispatch_semaphore_create(kInFlightCommandBuffers);
    }
    return self;
}

#pragma mark Configure

- (void)configure:(AAPLView *)view
{
    // find a usable Device
    _device = view.device;
    
    
    enable_ssss = true;
    
    
    int width = view.bounds.size.width * 2;
    int height = view.bounds.size.height * 2;
    RenderContext::set_window_size(width, height);
    
    // setup view with drawable formats
    view.depthPixelFormat   = MTLPixelFormatDepth32Float;
    view.stencilPixelFormat = MTLPixelFormatInvalid;
    view.sampleCount        = 1;
    
    // create a new command queue
    _commandQueue = [_device newCommandQueue];
    
    _defaultLibrary = [_device newDefaultLibrary];
    if(!_defaultLibrary) {
        NSLog(@">> ERROR: Couldnt create a default shader library");
        // assert here becuase if the shader libary isn't loading, nothing good will happen
        assert(0);
    }
    
    if (![self preparePipelineState:view])
    {
        NSLog(@">> ERROR: Couldnt create a valid pipeline state");
        
        // cannot render anything without a valid compiled pipeline state object.
        assert(0);
    }

        
    // allocate a number of buffers in memory that matches the sempahore count so that
    // we always have one self contained memory buffer for each buffered frame.
    // In this case triple buffering is the optimal way to go so we cycle through 3 memory buffers
    for (int i = 0; i < kInFlightCommandBuffers; i++)
    {
        for (int j = 0; j < N_LIGHTS; j++)
        {
            _shadow_pass_buffer[i][j] = [_device newBufferWithLength: sizeof(constants_mvp) options:0];
            _shadow_pass_buffer[i][j].label = [NSString stringWithFormat: @"shadow_pass_constant_buffer%i for light%i", i, j];
        }
        
        _sky_pass_buffer[i] = [_device newBufferWithLength: sizeof(constants_mvp) options:0];
        _sky_pass_buffer[i].label = [NSString stringWithFormat: @"sky_pass_constant_buffer%i", i];

        _main_pass_buffer[i] = [_device newBufferWithLength:sizeof(constant_main_pass) options:0];
        _main_pass_buffer[i].label = [NSString stringWithFormat: @"main_pass_constant_buffer%i", i];
    }
}

void load_preset(std::string path, Camera& _camera, Light* lights)
{
    std::ifstream fs(path);
    fs >> _camera;
    _camera.build();
    
    for (int i = 0; i < N_LIGHTS; i++)
    {
        fs >> lights[i];
    }
    
    fs.close();
}

- (BOOL)preparePipelineState:(AAPLView *)view
{
    for (int i = 0; i < N_LIGHTS; i++)
    {
        _lights[i].init(_device);
    }
    
    ModelManager::static_init(_device);
    
    load_preset(IOS_PATH("Preset", "Preset9", "txt"), _camera, _lights);
    
    _rt_main.init(_device, MTLPixelFormatRGBA8Unorm);
    _rt_depth.init(_device, MTLPixelFormatR32Float);
    _depth_stencil.init(_device);
    
    // load resources
    //*******************************************************************
    _model_head.init(_device, IOS_PATH("head", "head_optimized", "obj"), true, true, true, false);
    _model_sphere.init(_device, IOS_PATH("Models", "Sphere", "obj"), false, false, false, false);
    _model_quad.init(_device, IOS_PATH("Models", "Quad", "obj"), false, false, false, false);
    
    // Load the texture
    _tex_head_diffuse       = TextureLoader::CreateTexture(_device,         IOS_PATH("head", "DiffuseMap_R8G8B8A8_1024_mipmaps", "dds"), MTLPixelFormatRGBA8Unorm_sRGB);
    _tex_head_specularAO    = TextureLoader::CreateTexture(_device,         IOS_PATH("head", "SpecularAOMap_RGBA8UNorm", "dds"),        MTLPixelFormatRGBA8Unorm);
    _tex_head_normal_map    = TextureLoader::CreateTexture(_device,         IOS_PATH("head", "NormalMap_RG16f_1024_mipmaps", "dds"),    MTLPixelFormatRG16Float);
    _tex_sky                = TextureLoader::CreateTextureCubemap(_device,  IOS_PATH("StPeters", "DiffuseMap", "dds"),                  MTLPixelFormatRGBA16Float);
    _tex_sky_irradiance_map = TextureLoader::CreateTextureCubemap(_device,  IOS_PATH("StPeters", "IrradianceMap", "dds"),               MTLPixelFormatRGBA32Float);
    _tex_beckmann           = TextureLoader::CreateTexture(_device,         IOS_PATH("Texture", "BeckmannMap", "dds"),                  MTLPixelFormatR8Unorm);
    
    SeparableSSS::static_init();
    ssss.init(_device, CAMERA_FOV, 0.012f);
    ssss.prepare_pipeline_state(_device, _defaultLibrary, _rt_main);
    
    
    // Shader loading
    //*******************************************************************
    auto shadow_vert    = _newFunctionFromLibrary(_defaultLibrary, @"shadow_pass_vert");
    //auto shadow_frag = _newFunctionFromLibrary(_defaultLibrary, @"shadow_pass_frag");
    
    auto main_vert      = _newFunctionFromLibrary(_defaultLibrary, @"main_pass_vert");
    auto main_frag      = _newFunctionFromLibrary(_defaultLibrary, @"main_pass_frag");
    
    auto skydome_vert   = _newFunctionFromLibrary(_defaultLibrary, @"skydome_pass_vert");
    auto skydome_frag   = _newFunctionFromLibrary(_defaultLibrary, @"skydome_pass_frag");
    
    auto quad_vert      = _newFunctionFromLibrary(_defaultLibrary, @"quad_vert");
    auto quad_frag      = _newFunctionFromLibrary(_defaultLibrary, @"quad_frag");
    
    // Pipeline setup
    //*********************************************************************
    {
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        NSError *err = nil;
        desc.label = @"Shdow Pass";
        desc.vertexFunction = shadow_vert;
        desc.fragmentFunction = nil;
        desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        _pipeline_shadow_pass = [_device newRenderPipelineStateWithDescriptor:desc error: &err];
        CheckPipelineError(_pipeline_shadow_pass, err);
        
        desc.label = @"Main Pass";
        desc.vertexFunction = main_vert;
        desc.fragmentFunction = main_frag;
        desc.colorAttachments[0].pixelFormat = _rt_main.pixel_format();
        desc.colorAttachments[1].pixelFormat = _rt_depth.pixel_format();
        desc.depthAttachmentPixelFormat = _depth_stencil.pixel_format();
        _pipeline_main_pass = [_device newRenderPipelineStateWithDescriptor: desc error:&err];
        CheckPipelineError(_pipeline_main_pass, err);
        
        desc.colorAttachments[1].pixelFormat = MTLPixelFormatInvalid;
        
        desc.label = @"Sky Pass";
        desc.vertexFunction = skydome_vert;
        desc.fragmentFunction = skydome_frag;
        desc.colorAttachments[0].pixelFormat = _rt_main.pixel_format();
        desc.depthAttachmentPixelFormat = _depth_stencil.pixel_format();
        _pipeline_skydome = [_device newRenderPipelineStateWithDescriptor: desc error: & err];
        CheckPipelineError(_pipeline_skydome, err);
        
        desc.label = @"Quad Pass";
        desc.vertexFunction = quad_vert;
        desc.fragmentFunction = quad_frag;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        desc.depthAttachmentPixelFormat = view.depthPixelFormat;
        _pipeline_quad = [_device newRenderPipelineStateWithDescriptor: desc error: & err];
        CheckPipelineError(_pipeline_quad, err);
    }
    
    //Setup depth and stencil state objects
    //*********************************************************************
    {
        MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
        //MTLStencilDescriptor *stencil_desc = [[MTLStencilDescriptor alloc] init];
        
        desc.depthWriteEnabled = NO;
        desc.depthCompareFunction = MTLCompareFunctionAlways;
        _depth_state_none = [_device newDepthStencilStateWithDescriptor: desc];
        
        desc.depthWriteEnabled = YES;
        desc.depthCompareFunction = MTLCompareFunctionLess;
        _depth_state_shadow = [_device newDepthStencilStateWithDescriptor: desc];
        
        desc.depthWriteEnabled = YES;
        desc.depthCompareFunction = MTLCompareFunctionLess;
//        stencil_desc.stencilCompareFunction = MTLCompareFunctionAlways;
//        stencil_desc.stencilFailureOperation = MTLStencilOperationKeep;
//        stencil_desc.depthFailureOperation = MTLStencilOperationKeep;
//        stencil_desc.depthStencilPassOperation = MTLStencilOperationReplace;
//        stencil_desc.readMask = 0xFF;
//        stencil_desc.writeMask = 0xFF;
//        desc.frontFaceStencil = stencil_desc;
//        desc.backFaceStencil = stencil_desc;
        _depth_state_main = [_device newDepthStencilStateWithDescriptor: desc];
        
        desc.depthWriteEnabled = YES;
        desc.depthCompareFunction = MTLCompareFunctionLess;
        _depth_state_sky = [_device newDepthStencilStateWithDescriptor: desc];
        
    }
    
    //Render Pass Desc
    //*********************************************************************
    {
        _render_pass_desc_main = [MTLRenderPassDescriptor renderPassDescriptor];
        auto color_attachment_0 = _render_pass_desc_main.colorAttachments[0];
        auto color_attachment_1 = _render_pass_desc_main.colorAttachments[1];
        //color_attachment_0.texture = _rt_main.msaa_texture();
        //color_attachment_0.resolveTexture = _rt_main.texture();
        color_attachment_0.texture = _rt_main.texture();
        color_attachment_0.loadAction = MTLLoadActionClear;
        //color_attachment_0.storeAction = MTLStoreActionMultisampleResolve;
        color_attachment_0.storeAction = MTLStoreActionStore;
        color_attachment_0.clearColor = MTLClearColorMake(1, 0, 0, 1);
        
        color_attachment_1.texture = _rt_depth.texture();
        color_attachment_1.loadAction = MTLLoadActionClear;
        //color_attachment_0.storeAction = MTLStoreActionMultisampleResolve;
        color_attachment_1.storeAction = MTLStoreActionStore;
        color_attachment_1.clearColor = MTLClearColorMake(1, 0, 0, 1);
        
        auto depth_attachment = _render_pass_desc_main.depthAttachment;
        depth_attachment.texture = _depth_stencil.get_depth_stencil_texture();
        depth_attachment.loadAction = MTLLoadActionClear;
        depth_attachment.storeAction = MTLStoreActionStore;
        depth_attachment.clearDepth = 1.0;
    }
    {
        _render_pass_desc_skydome = [MTLRenderPassDescriptor renderPassDescriptor];
        auto color_attachment_0 = _render_pass_desc_skydome.colorAttachments[0];
        color_attachment_0.texture = _rt_main.texture();
        color_attachment_0.loadAction = MTLLoadActionLoad;
        color_attachment_0.storeAction = MTLStoreActionStore;
        color_attachment_0.clearColor = MTLClearColorMake(1, 0, 0, 1);
        auto depth_attachment = _render_pass_desc_skydome.depthAttachment;
        depth_attachment.texture = _depth_stencil.get_depth_stencil_texture();
        depth_attachment.loadAction = MTLLoadActionLoad;
        depth_attachment.storeAction = MTLStoreActionStore;
        //depth_attachment.clearDepth = 1.0;
    }
    
    return YES;
}

#pragma mark Render
- (void)ShdowPass: (id<MTLCommandBuffer>)commandBuffer
{
    RenderContext::model_mat = glm::scale(mat4(1.0f), vec3(0.7f, 0.7f, 0.7f)) * glm::translate(mat4(1.0f), vec3(0, 0.2f, 0.425f));
    for (int i = 0; i < N_LIGHTS; i++)
    {
        auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _lights[i].shadowMap.renderPassDescriptor()];
        [encoder pushDebugGroup:[NSString stringWithFormat: @"Shdow Pass %d", i]];
        encoder.label = [NSString stringWithFormat: @"ShadowMap%d", i];
        
        // setup encoder state
        [encoder setRenderPipelineState: _pipeline_shadow_pass];
        [encoder setDepthStencilState: _depth_state_shadow];
        [encoder setCullMode: MTLCullModeFront];
        [encoder setDepthBias:0.01 slopeScale: 1.0f clamp: 0.01];
        
//        auto proj = _lights[i].camera.getProjectionMatrix();
//        auto linear_proj = proj;
//        float Q = proj[2][2];
//        float N = -proj[3][2] / Q;
//        float F = -N * Q / (1-Q);
//        linear_proj[2][2] /= F;
//        linear_proj[3][2] /= F;
//        
//        auto mvp = linear_proj * _lights[i].camera.getViewMatrix() * RenderContex::model_mat;
        
        RenderContext::camera = &_lights[i].camera;
        auto uniform_buffer = (constants_mvp*)[_shadow_pass_buffer[RenderContext::current_buffer_index][i] contents];
        uniform_buffer->MVP = to_simd_type(RenderContext::get_mvp_mat());
        //uniform_buffer->MVP = to_simd_type(mvp);
        [encoder setVertexBuffer:_shadow_pass_buffer[RenderContext::current_buffer_index][i] offset:0 atIndex:0 ];
        
        _model_head.render(encoder, true, true, true);
        
        [encoder popDebugGroup];
        [encoder endEncoding];
    }
}

- (void)MainPass: (id<MTLCommandBuffer>)commandBuffer
{
    {
        bool separate_speculars = false;
        bool enable_ssss = true;
        bool enable_sss_translucency = true;
        float sss_width = 0.012f;
        //vec3 sss_strength = vec3(0.48f, 0.41f, 0.28f);
        //vec3 sss_falloff = vec3(1.0f, 0.37f, 0.3f);
        float translucency = 0.1f;	// TODO 0.88
        
        //double speed = 1;
        float specularIntensity = 1.88f;
        float specularRoughness = 0.3f;
        float specularFresnel = 0.82f;
        float bumpiness = 0.9f;
        float ambient = 0.80f; // 0.61f
        
        float falloff_width = 0.1f;
        
        auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc_main];
        [encoder pushDebugGroup:@"MainPass"];
        encoder.label = @"main pass";
        [encoder setDepthStencilState: _depth_state_main];
        [encoder setRenderPipelineState: _pipeline_main_pass];
        [encoder setCullMode: MTLCullModeFront];
        
        auto constant_buffer = (constant_main_pass*)[ _main_pass_buffer[RenderContext::current_buffer_index] contents];
        RenderContext::camera = &_camera;
        RenderContext::model_mat = glm::scale(mat4(1.0f), vec3(0.7f, 0.7f, 0.7f)) * glm::translate(mat4(1.0f), vec3(0, 0.2f, 0.425f));;
        constant_buffer->MVP = to_simd_type(RenderContext::get_mvp_mat());
        constant_buffer->Model = to_simd_type(RenderContext::model_mat);
        constant_buffer->ModelInverseTranspose = to_simd_type(RenderContext::get_model_inverse_transpose());
        constant_buffer->camera_position = to_simd_type(vec4(_camera.getEyePosition(), 1.0));
        
        constant_buffer->bumpiness = bumpiness;
        constant_buffer->specularIntensity = specularIntensity;
        constant_buffer->specularRoughness = specularRoughness;
        constant_buffer->specularFresnel = specularFresnel;
        constant_buffer->translucency = translucency;
        constant_buffer->sssWidth = sss_width;
        constant_buffer->ambient = ambient;
        constant_buffer->sssEnabled = enable_ssss;
        constant_buffer->sssTranslucencyEnabled = enable_sss_translucency;
        constant_buffer->separate_speculars = separate_speculars;
        
        for (int i = 0; i < N_LIGHTS; i++)
        {
            auto& l = _lights[i];
            auto& lc = l.camera;
            auto& pos = lc.getEyePosition();
            constant_buffer->lights[i].position = to_simd_type(pos);
            constant_buffer->lights[i].direction = to_simd_type(lc.getLookAtPosition() - pos);
            constant_buffer->lights[i].color = to_simd_type(l.color);
            constant_buffer->lights[i].falloffStart = cos(0.5f * l.fov);
            constant_buffer->lights[i].falloffWidth = falloff_width;
            constant_buffer->lights[i].attenuation = l.attenuation;
            constant_buffer->lights[i].farPlane = l.farPlane;
            constant_buffer->lights[i].bias = l.bias;
            constant_buffer->lights[i].viewProjection = to_simd_type(ShadowMap::getViewProjectionTextureMatrix(lc.getViewMatrix(), lc.getProjectionMatrix()));
        }

        [encoder setVertexBuffer: _main_pass_buffer[RenderContext::current_buffer_index] offset:0 atIndex:0];
        [encoder setFragmentBuffer: _main_pass_buffer[RenderContext::current_buffer_index] offset:0 atIndex:0];
        [encoder setFragmentTexture: _tex_head_diffuse atIndex:0];
        [encoder setFragmentTexture: _tex_head_specularAO atIndex:1];
        [encoder setFragmentTexture: _tex_head_normal_map atIndex:2];
        [encoder setFragmentTexture: _tex_beckmann atIndex:3];
        [encoder setFragmentTexture: _tex_sky_irradiance_map atIndex:4];
        for (int i = 0; i < N_LIGHTS; i++)
        {
            [encoder setFragmentTexture: _lights[i].shadowMap.get_depth_stencil_texture() atIndex:5+i];
        }

        _model_head.render(encoder);
        
        [encoder popDebugGroup];
        [encoder endEncoding];
    }
    
    {
        auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: _render_pass_desc_skydome];
        [encoder pushDebugGroup:@"SkyPass"];
        encoder.label = @"sky pass";
        [encoder setDepthStencilState: _depth_state_sky];
        [encoder setRenderPipelineState: _pipeline_skydome];
        [encoder setCullMode: MTLCullModeBack];
        
        auto constant_buffer = (constants_mvp*)[_sky_pass_buffer[RenderContext::current_buffer_index] contents];
        RenderContext::camera = &_camera;
        RenderContext::model_mat = glm::scale(glm::mat4(1.0f), glm::vec3(2.f));
        constant_buffer->MVP = to_simd_type( RenderContext::get_mvp_mat() );
        [encoder setVertexBuffer:_sky_pass_buffer[RenderContext::current_buffer_index] offset:0 atIndex:0];
        [encoder setFragmentTexture: _tex_sky atIndex:0];
        
        _model_sphere.render(encoder);
    
        [encoder popDebugGroup];
        [encoder endEncoding];
    }
}

- (void)SkyPass: (id<MTLCommandBuffer>) commandBuffer
{
    
}

- (void)DrawTextureToScreen: (id<MTLTexture>) texture commandBuffer: (id<MTLCommandBuffer>) commandBuffer view:(AAPLView*) view
{
    auto encoder = [commandBuffer renderCommandEncoderWithDescriptor: view.renderPassDescriptor];
    [encoder pushDebugGroup:@"texture2ScreenPass"];
    encoder.label = @"texture pass";
    
    // setup encoder state
    [encoder setRenderPipelineState: _pipeline_quad];
    [encoder setDepthStencilState: _depth_state_none];
    [encoder setCullMode: MTLCullModeNone];
    [encoder setDepthBias:0.01 slopeScale: 1.0f clamp: 0.01];
    [encoder setFragmentTexture: texture atIndex: 0];
    _model_quad.render(encoder, true);
    
    [encoder popDebugGroup];
    [encoder endEncoding];
}

- (void)render:(AAPLView *)view
{
    // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
    // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
    // signifying the CPU can go ahead and prepare another frame.
    dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
    
    // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
    [self updateConstantBuffer];
    
    // create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    [self ShdowPass: commandBuffer];
    [self MainPass: commandBuffer];
    
    if (enable_ssss)
    {
        float sss_width = 0.012f;
        vec3 sss_strength = vec3(0.48f, 0.41f, 0.28f);
        vec3 sss_falloff = vec3(1.0f, 0.37f, 0.3f);
        ssss.setStrength(sss_strength);
        ssss.setFalloff(sss_falloff);
        ssss.setWidth(sss_width);
        ssss.render(commandBuffer, _rt_main, _rt_depth, _depth_stencil);
    }
    
    [self DrawTextureToScreen: _rt_main.texture() commandBuffer: commandBuffer view: view];
    
    [commandBuffer presentDrawable: view.currentDrawable];
    
    // call the view's completion handler which is required by the view since it will signal its semaphore and set up the next buffer
    __block dispatch_semaphore_t block_sema = _inflight_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        
        // GPU has completed rendering the frame and is done using the contents of any buffers previously encoded on the CPU for that frame.
        // Signal the semaphore and allow the CPU to proceed and construct the next frame.
        dispatch_semaphore_signal(block_sema);
    }];
    
    // finalize rendering here. this will push the command buffer to the GPU
    [commandBuffer commit];
    
    // This index represents the current portion of the ring buffer being used for a given frame's constant buffer updates.
    // Once the CPU has completed updating a shared CPU/GPU memory buffer region for a frame, this index should be updated so the
    // next portion of the ring buffer can be written by the CPU. Note, this should only be done *after* all writes to any
    // buffers requiring synchronization for a given frame is done in order to avoid writing a region of the ring buffer that the GPU may be reading.
    RenderContext::current_buffer_index = (RenderContext::current_buffer_index + 1) % kInFlightCommandBuffers;
}

- (void)reshape:(AAPLView *)view
{
    // when reshape is called, update the view and projection matricies since this means the view orientation or size changed
    float aspect = fabsf(float(view.bounds.size.width) / float(view.bounds.size.height));
    _camera.setProjection(CAMERA_FOV * PI / 180.0f, aspect, 0.1f, 100.0f);
}

#pragma mark Update

// called every frame
- (void)updateConstantBuffer
{
//    glm::mat4 model = glm::scale(mat4(1.0f), vec3(0.7f, 0.7f, 0.7f)) * glm::translate(mat4(1.0f), vec3(0, 0.2f, 0.425f));
//    mat4 modelView = _camera.getViewMatrix() * model;
//    mat4 MVP = _camera.getProjectionMatrix() * modelView;
}

// just use this to update app globals
- (void)update:(AAPLViewController *)controller
{
    //_rotation += controller.timeSinceLastDraw * 50.0f;
    _frameTime += controller.timeSinceLastDraw;
}

- (void)viewController:(AAPLViewController *)controller willPause:(BOOL)pause
{
    // timer is suspended/resumed
    // Can do any non-rendering related background work here when suspended
}

- (void)enable_ssss: (BOOL)enabled
{
    enable_ssss = enabled;
}


@end
