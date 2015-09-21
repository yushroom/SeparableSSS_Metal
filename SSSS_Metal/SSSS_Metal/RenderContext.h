#ifndef RENDERCONTEX_H
#define RENDERCONTEX_H

#include <Metal/Metal.h>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include "Camera.h"

static const long kInFlightCommandBuffers = 3;

class RenderContext
{
public:

	static void set_window_size(int width, int height)
	{
		window_width = width;
		window_height = height;
	}

	static int window_width;
	static int window_height;
    
    static id <MTLDevice> device;
    static id <MTLLibrary> _defaultLibrary;
    
    static NSUInteger current_buffer_index;

	static glm::mat4 model_mat;
	static glm::mat4 prev_mvp;
	static Camera* camera;

	static glm::mat4 get_model_inverse_transpose()
	{
		return glm::inverse(glm::transpose(model_mat));
	}

	static glm::mat4 get_mvp_mat()
	{
		return camera->getProjectionMatrix() * camera->getViewMatrix() * model_mat;
	}

private:
	RenderContext();
};


#endif
