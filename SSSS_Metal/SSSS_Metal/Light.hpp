#ifndef LIGHT_H
#define LIGHT_H

#include <Metal/Metal.h>

#include <fstream>
#include <glm/glm.hpp>

#include "RenderTarget.h"
#include "Camera.h"

const float PI = 3.1415926536f;

//class ShadowMap;
class Camera;

class Light 
{
public:
	void init(id <MTLDevice> device)
	{
		fov = 45.0f * PI / 180.f;
		falloffWidth = 0.05f;
		attenuation = 1.0f / 128.0f;
		farPlane = 10.0f;
		bias = -0.01f;

		camera.setDistance(2.0);
		camera.setProjection(fov, 1, 0.1f, farPlane);
        camera.build();
		color = vec3(0.0f, 0.0f, 0.0f);
		intensity = 0.0f;
		shadowMap.init(device);
		camera.setViewportSize(ShadowMap::SHADOW_MAP_SIZE, ShadowMap::SHADOW_MAP_SIZE);
	}

	friend std::ostream& operator <<(std::ostream &os, const Light &light)
	{
		os << light.camera;
		os << light.color.x << std::endl;
		os << light.color.y << std::endl;
		os << light.color.z << std::endl;

		return os;
	}

	friend std::istream& operator >>(std::istream &is, Light &light)
	{
		is >> light.camera;
		is >> light.color.x;
		is >> light.color.y;
		is >> light.color.z;
		light.intensity = light.color.x;

        light.camera.build();
        
		return is;
	}

	Camera camera;
	float fov;
	float falloffWidth;
	float intensity;
	glm::vec3 color;
	float attenuation;
	float farPlane;
	float bias;
	ShadowMap shadowMap;
};

#endif