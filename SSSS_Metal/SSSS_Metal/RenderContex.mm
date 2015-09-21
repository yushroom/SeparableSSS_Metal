#include "RenderContext.h"

int RenderContext::window_width = 0;
int RenderContext::window_height = 0;
glm::mat4 RenderContext::model_mat;
Camera* RenderContext::camera;
glm::mat4 RenderContext::prev_mvp;


NSUInteger RenderContext::current_buffer_index = 0;