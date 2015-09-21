//
//  Model.m
//  MetalBasic3D
//
//  Created by yushroom on 9/8/15.
//  Copyright (c) 2015 Apple Inc. All rights reserved.
//

#include "Model.h"

#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>


Model ModelManager::screen_aligned_quad;
Model ModelManager::triangle;

void Model::_loadMeshFromFile(const std::string& str_path)
{
    _vertices.clear();
    _normals.clear();
    _uv.clear();
    _indices.clear();
    _bitangent.clear();
    
    Assimp::Importer importer;
    const char* path = str_path.c_str();
    unsigned int load_option =
    //aiProcess_CalcTangentSpace |
    aiProcess_Triangulate |
    aiProcess_JoinIdenticalVertices |
    aiProcess_SortByPType;
    if (_use_normal) load_option |= aiProcess_GenSmoothNormals;
    if (_use_tangent || _use_bitangent) load_option |= aiProcess_CalcTangentSpace;
    const aiScene* scene = importer.ReadFile(path, load_option);
    
    if (!scene) {
        Debug::LogError("Can not open model " + str_path + ". This file may not exist or is not supported");
        return; // TODO
    }
    
    // get each mesh
    int nvertices = 0;
    int ntriangles = 0;
    
    for (unsigned int i = 0; i < scene->mNumMeshes; i++) {
        aiMesh* mesh = scene->mMeshes[i];
        nvertices += mesh->mNumVertices;
        ntriangles += mesh->mNumFaces;
    }
    
    _vertices.reserve(nvertices);
    if (_use_normal) _normals.reserve(nvertices);
    if (_use_uv) _uv.reserve(nvertices);
    if (_use_tangent) _tangent.reserve(nvertices);
    if (_use_bitangent) _bitangent.reserve(nvertices);
    _indices.resize(ntriangles * 3);	// TODO, *3?
    int idx = 0;
    int idx2 = 0;
    for (unsigned int i = 0; i < scene->mNumMeshes; i++)
    {
        aiMesh* mesh = scene->mMeshes[i];
        if (_use_uv)
            assert(mesh->HasTextureCoords(0) == true);
        
        for (unsigned int j = 0; j < mesh->mNumVertices; j++)
        {
            aiVector3D& v = mesh->mVertices[j];
            _vertices.push_back(vec3(v.x, v.y, v.z));
            
            if (_use_normal)
            {
                aiVector3D& n = mesh->mNormals[j];
                _normals.push_back(vec3(n.x, n.y, n.z));
            }
            
            if (_use_uv)
            {
                aiVector3D& u = mesh->mTextureCoords[0][j];
                _uv.push_back(vec2(u.x, u.y));
            }
            
            if (_use_tangent)
            {
                auto& t = mesh->mTangents[j];
                _tangent.push_back(vec3(t.x, t.y, t.z));
            }
            if (_use_bitangent)
            {
                auto& t = mesh->mBitangents[j];
                _bitangent.push_back(vec3(t.x, t.y, t.z));
            }
            
            //aabb.expand(glm::vec3(v.x, v.y, v.z));
        }
        
        //int temp_idx = idx/3;
        for (unsigned int j = 0; j < mesh->mNumFaces; j++)
        {
            const aiFace& Face = mesh->mFaces[j];
            assert(Face.mNumIndices == 3);
            _indices[idx++] = Face.mIndices[0] + idx2;
            _indices[idx++] = Face.mIndices[1] + idx2;
            _indices[idx++] = Face.mIndices[2] + idx2;
        }
        idx2 += mesh->mNumVertices;
    }
}
