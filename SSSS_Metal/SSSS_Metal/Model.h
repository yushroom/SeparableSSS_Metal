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

using glm::vec3;
using glm::vec2;

typedef std::vector<uint32_t> UIntArray;
typedef std::vector<vec3> Vec3Array;
typedef std::vector<vec2> Vec2Array;

class Model
{
private:
    UIntArray _triangles;
    Vec3Array _vertices;
    Vec3Array _normals;
    Vec2Array _uv;
    Vec3Array _tangent;
    Vec3Array _bitangent;
    
    bool _use_normal = true;
    bool _use_uv = true;
    bool _use_tangent = false;
    bool _use_bitangent = false;
    
public:
    
    void init(const std::string& str_path, bool use_normal = true, bool use_uv = true, bool use_tangent = false, bool use_bitangent = false)
    {
        _use_normal  = use_normal;
        _use_uv		 = use_uv;
        _use_tangent = use_tangent;
        _use_bitangent = use_bitangent;
        _loadMeshFromFile(str_path);
        //_BindBuffer();
    }
    
    uint32_t VertexCount() const
    {
        return (uint32_t)_vertices.size();
    }
    
    uint32_t IndexCount() const
    {
        return (uint32_t)_triangles.size();
    }
    
    const UIntArray& Triangles() const
    {
        return _triangles;
    }
    
    const Vec3Array& Vertices() const
    {
        return _vertices;
    }
    
    const Vec3Array& Normals() const
    {
        return _normals;
    }
    
    const Vec2Array& UV() const
    {
        return _uv;
    }
    
private:
    
    void _loadMeshFromFile(const std::string& str_path);

};
#endif
