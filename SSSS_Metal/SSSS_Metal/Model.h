//
//  Model.h
//  MetalBasic3D
//
//  Created by yushroom on 9/8/15.
//  Copyright (c) 2015 Apple Inc. All rights reserved.
//

#ifndef MetalBasic3D_Model_h
#define MetalBasic3D_Model_h

#include <vector>

#include <glm/glm.hpp>

#include "Debug.h"

#import <Metal/Metal.h>

using glm::vec3;
using glm::vec2;

typedef std::vector<uint32_t> UIntArray;
typedef std::vector<vec3> Vec3Array;
typedef std::vector<vec2> Vec2Array;

class Model
{
private:
    UIntArray _indices;
    Vec3Array _vertices;
    Vec3Array _normals;
    Vec2Array _uv;
    Vec3Array _tangent;
    Vec3Array _bitangent;
    
    bool _use_normal = true;
    bool _use_uv = true;
    bool _use_tangent = false;
    bool _use_bitangent = false;
    
    id <MTLBuffer> _vertexBuffer;
    id <MTLBuffer> _indexBuffer;
    id <MTLBuffer> _normalBuffer;
    id <MTLBuffer> _tangentBuffer;
    id <MTLBuffer> _uvBuffer;
    
public:
    
    void init(id <MTLDevice> device, const std::string& str_path, bool use_normal = true, bool use_uv = true, bool use_tangent = false, bool use_bitangent = false)
    {
        _use_normal  = use_normal;
        _use_uv		 = use_uv;
        _use_tangent = use_tangent;
        _use_bitangent = use_bitangent;
        _loadMeshFromFile(str_path);
        _bindBuffer(device);
    }
    
    void render(id <MTLRenderCommandEncoder> renderEncoder, bool disable_normal = false, bool disable_uv = false, bool disable_tangent = false)
    {
        int buffer_index = 1;
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex: buffer_index];
        buffer_index++;
        if (_use_normal && !disable_normal) {
            [renderEncoder setVertexBuffer:_normalBuffer offset:0 atIndex: buffer_index];
            buffer_index++;
        }
        if (_use_tangent && !disable_tangent) {
            [renderEncoder setVertexBuffer:_tangentBuffer offset:0 atIndex:buffer_index];
            buffer_index++;
        }
        if (_use_uv && !disable_uv) {
            [renderEncoder setVertexBuffer:_uvBuffer offset:0 atIndex:buffer_index];
            buffer_index++;
        }
        // tell the render context we want to draw our primitives
        //[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
        [renderEncoder drawIndexedPrimitives: MTLPrimitiveTypeTriangle
                                  indexCount: _indices.size()
                                   indexType: MTLIndexTypeUInt32
                                 indexBuffer: _indexBuffer
                           indexBufferOffset: 0];
    }
    
private:
    
    void _loadMeshFromFile(const std::string& str_path);

    void _bindBuffer(id <MTLDevice> device)
    {
        _indexBuffer = [device newBufferWithBytes: reinterpret_cast<const void*>(_indices.data())
                                           length: _indices.size() * sizeof(_indices[0])
                                          options: MTLResourceOptionCPUCacheModeDefault];
        _indexBuffer.label = @"Indices";
        
        // setup the vertex buffers
        _vertexBuffer = [device newBufferWithBytes: reinterpret_cast<const void*>(_vertices.data())
                                             length: _vertices.size() * sizeof(_vertices[0])
                                            options: MTLResourceOptionCPUCacheModeDefault];
        if (_use_normal) {
            _normalBuffer = [device newBufferWithBytes: reinterpret_cast<const void*>(_normals.data())
                                                length: _normals.size() * sizeof(_normals[0])
                                               options: MTLResourceOptionCPUCacheModeDefault];
        }
        if (_use_tangent) {
            _tangentBuffer = [device newBufferWithBytes: reinterpret_cast<const void*>(_tangent.data())
                                                length: _tangent.size() * sizeof(_tangent[0])
                                               options: MTLResourceOptionCPUCacheModeDefault];
        }
        if (_use_uv) {
            _uvBuffer = [device newBufferWithBytes: reinterpret_cast<const void*>(_uv.data())
                                                 length: _uv.size() * sizeof(_uv[0])
                                                options: MTLResourceOptionCPUCacheModeDefault];
        }
        
        _vertexBuffer.label = @"Vertices";
    }
    
};
#endif
