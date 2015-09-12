#ifndef TEXTURELOADER_H
#define TEXTURELOADER_H

#include <vector>
#include <Metal/Metal.h>
#include "Debug.h"

class TextureLoader
{
public:
    static id <MTLTexture> CreateTextureCubemap(id <MTLDevice> device, const char* path, MTLPixelFormat format);
    static id <MTLTexture> CreateTexture(       id <MTLDevice> device, const char* path, MTLPixelFormat format, bool srgb);
    static id <MTLTexture> CreateTextureArray(  id <MTLDevice> device, const char* path);
    static id <MTLTexture> CreateTexture3D(     id <MTLDevice> device, const char* path);
    
    static id <MTLTexture> CreateTextureCubemap(id <MTLDevice> device, const std::string path, MTLPixelFormat format)
    {
        return CreateTextureCubemap(device, path.c_str(), format);
    }
    
    static id <MTLTexture> CreateTexture(       id <MTLDevice> device, const std::string path, MTLPixelFormat format,  bool srgb = false)
    {
        return CreateTexture(device, path.c_str(), format, srgb);
    }
    
private:
	TextureLoader();

	//static std::vector<GLuint> _textures;
};


#endif