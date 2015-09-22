#include "TextureLoader.h"
#include <gli/gli.hpp>

//std::vector<GLuint> TextureLoader::_textures;

id <MTLTexture> TextureLoader::CreateTextureCubemap(id <MTLDevice> device, const char* path, MTLPixelFormat format)
{
    gli::textureCube texture(gli::load_dds(path));
    assert(!texture.empty());
    //printf("%d %d\n", texture.levels(), texture.layers());
    //gli::gl GL;
    //gli::gl::format const glformat = GL.translate(texture.format());
    //printf("%s\n\t%X %X %X\n", path, format.Internal, format.External, format.Type);
    
    assert(!gli::is_compressed(texture.format()));
    
    uint32_t w = (uint32_t)texture[0][0].dimensions().x;
    uint32_t h = (uint32_t)texture[0][0].dimensions().y;
    
    uint32_t bytes_pet_pixel = 4 * 2; // MTLPixelFormatRGBA16Float
    if (format == MTLPixelFormatRGBA32Float)
    {
        bytes_pet_pixel = 4 * 4;
    }
    
    if (format != MTLPixelFormatRGBA32Float && format != MTLPixelFormatRGBA16Float)
    {
        Debug::LogError("CreateTextureCubemap format error!");
        exit(1);
    }
    
    auto desc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat: format size: w mipmapped: NO];
    id<MTLTexture> mtltexture = [device newTextureWithDescriptor: desc];
    
    for (int face = 0; face < 6; face++)
    {
        auto t = texture[face][0];
        //unsigned long w = t.dimensions().x;
        //unsigned long h = t.dimensions().y;
        [mtltexture replaceRegion: MTLRegionMake2D(0, 0, w, h)
                      mipmapLevel: 0
                            slice: face
                        withBytes: t.data()
                      bytesPerRow: bytes_pet_pixel * w
                    bytesPerImage: bytes_pet_pixel * w * h];
    }
    return mtltexture;
}

id <MTLTexture> TextureLoader::CreateTexture(id <MTLDevice> device, const char* path, MTLPixelFormat format, bool srgb)
{
    //Debug::LogInfo(path);
    
    gli::texture2D texture(gli::load_dds(path));
    assert(!texture.empty());
    //printf("%d %d\n", Texture.levels(), Texture.layers());
    //gli::gl GL;
    //gli::gl::format const format = GL.translate(texture.format());
    //printf("%s\n\t%X %X %X\n", path, format.Internal, format.External, format.Type);
    
    uint32_t w = (uint32_t)texture.dimensions().x;
    uint32_t h = (uint32_t)texture.dimensions().y;
    
    //MTLPixelFormat mtl_format = MTLPixelFormatRGBA8Unorm;
    
    // hack
//    int f = format.Internal;
//    uint32_t bytes_per_row = 0;
//    if (srgb && f == gli::gl::INTERNAL_RGBA8_UNORM)
//    {
//        //f = 0x8C4F;
//        //f = gli::gl::INTERNAL_SRGB8_ALPHA8;
//        mtl_format = MTLPixelFormatRGBA8Unorm_sRGB;
//        bytes_per_row = 4 * w;
//    }
    
    // for beckman
//    if (f == gli::gl::INTERNAL_RG8_UNORM)
//    {
//        //f = gli::gl::INTERNAL_R8_UNORM;
//        mtl_format = MTLPixelFormatR8Unorm;
//        bytes_per_row = w;
//    }
    
    uint32_t bytes_per_pixel = 0;
    switch (format) {
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatRGBA8Unorm_sRGB:
        case MTLPixelFormatRG16Float:
            bytes_per_pixel = 4;
            break;
        case MTLPixelFormatRGBA16Float:
            bytes_per_pixel = 4 * 2;
            break;
        case MTLPixelFormatRGBA32Float:
            bytes_per_pixel = 4 * 4;
            break;
        case MTLPixelFormatRG8Unorm:
            bytes_per_pixel = 2;
            break;
        case MTLPixelFormatR8Unorm:
            bytes_per_pixel = 1;
            break;
        default:
            break;
    }
    //auto bpp = texture.size() / w / h;
    //assert(bytes_per_row * h == texture.size());
    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped: YES];
    //desc.mipmapLevelCount = texture.levels();
    id<MTLTexture> mtltexture = [device newTextureWithDescriptor: desc];
    
    assert(!gli::is_compressed(texture.format()));
    
    
    if (gli::is_compressed(texture.format()))
    {
//        for (std::size_t level = 0; level < texture.levels(); ++level)
//        {
//            glCompressedTexSubImage2D(GL_TEXTURE_2D, static_cast<GLint>(level),
//                                      0, 0,
//                                      static_cast<GLsizei>(texture[level].dimensions().x),
//                                      static_cast<GLsizei>(texture[level].dimensions().y),
//                                      f,
//                                      static_cast<GLsizei>(texture[level].size()),
//                                      texture[level].data());
//        }
    }
    else
    {
        for (std::size_t Level = 0; Level < texture.levels(); ++Level)
        {
            auto t = texture[Level];
            w = (uint32_t)t.dimensions().x;
            h = (uint32_t)t.dimensions().y;
            [mtltexture replaceRegion: MTLRegionMake2D(0, 0, w, h)
                          mipmapLevel: Level
                            withBytes: t.data()
                          bytesPerRow: bytes_per_pixel * w];
        }
//        auto t = texture[0];
//        //unsigned long w = t.dimensions().x;
//        //unsigned long h = t.dimensions().y;
//        [mtltexture replaceRegion: MTLRegionMake2D(0, 0, w, h)
//                      mipmapLevel: 0
//                            slice: 0
//                        withBytes: t.data()
//                      bytesPerRow: bytes_per_pixel * w
//                    bytesPerImage: bytes_per_pixel * w * h];
        
    }
    
    return mtltexture;
}

//static GLuint CreateTextureArray(char const* Filename)
//{
//    gli::texture2D Texture(gli::load_dds(Filename));
//    assert(!Texture.empty());
//    //printf("%d %d\n", Texture.levels(), Texture.layers());
//    gli::gl GL;
//    gli::gl::format const Format = GL.translate(Texture.format());
//    GLuint texture_id = 0;
//    glGenTextures(1, &texture_id);
//    glBindTexture(GL_TEXTURE_2D_ARRAY, texture_id);
//    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_BASE_LEVEL, 0);
//    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, static_cast<GLint>(Texture.levels() - 1));
//    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_SWIZZLE_R, Format.Swizzle[0]);
//    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_SWIZZLE_G, Format.Swizzle[1]);
//    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_SWIZZLE_B, Format.Swizzle[2]);
//    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_SWIZZLE_A, Format.Swizzle[3]);
//    glTexStorage3D(GL_TEXTURE_2D_ARRAY, static_cast<GLint>(Texture.levels()),
//                   Format.Internal,
//                   static_cast<GLsizei>(Texture.dimensions().x),
//                   static_cast<GLsizei>(Texture.dimensions().y),
//                   static_cast<GLsizei>(1));
//    if (gli::is_compressed(Texture.format()))
//    {
//        for (std::size_t Level = 0; Level < Texture.levels(); ++Level)
//        {
//            glCompressedTexSubImage3D(GL_TEXTURE_2D_ARRAY, static_cast<GLint>(Level),
//                                      0, 0, 0,
//                                      static_cast<GLsizei>(Texture[Level].dimensions().x),
//                                      static_cast<GLsizei>(Texture[Level].dimensions().y),
//                                      static_cast<GLsizei>(1),
//                                      Format.External,
//                                      static_cast<GLsizei>(Texture[Level].size()),
//                                      Texture[Level].data());
//        }
//    }
//    else
//    {
//        for (std::size_t Level = 0; Level < Texture.levels(); ++Level)
//        {
//            glTexSubImage3D(GL_TEXTURE_2D_ARRAY, static_cast<GLint>(Level),
//                            0, 0, 0,
//                            static_cast<GLsizei>(Texture[Level].dimensions().x),
//                            static_cast<GLsizei>(Texture[Level].dimensions().y),
//                            static_cast<GLsizei>(1),
//                            Format.External, Format.Type,
//                            Texture[Level].data());
//        }
//    }
//    check_gl_error();
//    _textures.push_back(texture_id);
//    return texture_id;
//}
//
//static GLuint CreateTexture3D(const char* path)
//{
//    gli::texture3D texture(gli::load_dds(path));
//    assert(!texture.empty());
//    //printf("%d %d\n", texture.levels(), texture.layers());
//    gli::gl GL;
//    gli::gl::format const format = GL.translate(texture.format());
//    //printf("%d %d %d\n", texture.dimensions().x, texture.dimensions().y, texture.dimensions().z);
//    GLuint texture_id = 0;
//    glGenTextures(1, &texture_id);
//    glBindTexture(GL_TEXTURE_3D, texture_id);
//    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_BASE_LEVEL, 0);
//    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAX_LEVEL, static_cast<GLint>(texture.levels() - 1));
//    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, Format.Swizzle[0]);
//    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, Format.Swizzle[1]);
//    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_B, Format.Swizzle[2]);
//    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_A, Format.Swizzle[3]);
//    //glTexStorage3D(GL_TEXTURE_3D, static_cast<GLint>(texture.levels()),
//    //	format.Internal,
//    //	static_cast<GLsizei>(texture.dimensions().x),
//    //	static_cast<GLsizei>(texture.dimensions().y),
//    //	static_cast<GLsizei>(texture.dimensions().z));
//    
//    // hack
//    int f = format.Internal;
//    // for Noise.dds
//    if (f == gli::gl::INTERNAL_RG8_UNORM)
//    {
//        f = gli::gl::INTERNAL_R8_UNORM;
//    }
//    
//    if (gli::is_compressed(texture.format()))
//    {
//        for (std::size_t level = 0; level < texture.levels(); ++level)
//        {
//            glCompressedTexImage3D(GL_TEXTURE_3D, static_cast<GLint>(level),
//                                   f,
//                                   static_cast<GLsizei>(texture[level].dimensions().x),
//                                   static_cast<GLsizei>(texture[level].dimensions().y),
//                                   static_cast<GLsizei>(texture[level].dimensions().z),
//                                   0,
//                                   static_cast<GLsizei>(texture[level].size()),
//                                   texture[level].data());
//        }
//    }
//    else
//    {
//        for (std::size_t Level = 0; Level < texture.levels(); ++Level)
//        {
//            glTexImage3D(GL_TEXTURE_3D, static_cast<GLint>(Level),
//                         f,
//                         static_cast<GLsizei>(texture[Level].dimensions().x),
//                         static_cast<GLsizei>(texture[Level].dimensions().y),
//                         static_cast<GLsizei>(texture[Level].dimensions().z),
//                         0,
//                         //static_cast<GLsizei>(1),
//                         format.External, format.Type,
//                         texture[Level].data());
//        }
//    }
//    //        check_gl_error();
//    
//    
//    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_MIRRORED_REPEAT);
//    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_MIRRORED_REPEAT);
//    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
//    //glGenerateMipmap(GL_TEXTURE_3D);
//    glBindTexture(GL_TEXTURE_3D, 0);
//    
//    _textures.push_back(texture_id);
//    check_gl_error();
//    
//    return texture_id;
//}
//
//static void shut_down()
//{
//    glDeleteTextures((GLsizei)_textures.size(), &_textures[0]);
//}
