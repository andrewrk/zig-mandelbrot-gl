const std = @import("std");
const c = @import("c.zig");
const panic = std.debug.panic;
const debug_gl = @import("./debug_gl.zig");
const StaticGeometry = @import("static_geometry.zig").StaticGeometry;
const AllShaders = @import("all_shaders.zig").AllShaders;
const math3d = @import("math3d.zig");
const Mat4x4 = math3d.Mat4x4;

const App = struct {
    window: *c.GLFWwindow,
    all_shaders: AllShaders,
    static_geometry: StaticGeometry,
    projection: Mat4x4,
    framebuffer_width: u31,
    framebuffer_height: u31,
};
var application: App = undefined;

extern fn errorCallback(err: c_int, description: [*c]const u8) void {
    panic("Error: {}\n", description);
}

extern fn framebufferResizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const app = &application;
    app.framebuffer_width = @intCast(u31, width);
    app.framebuffer_height = @intCast(u31, height);
    resetProjection(app);
}

pub fn main() anyerror!void {
    _ = c.glfwSetErrorCallback(errorCallback);
    if (c.glfwInit() == c.GL_FALSE) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 2);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug_gl.is_on);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_DEPTH_BITS, 0);
    c.glfwWindowHint(c.GLFW_STENCIL_BITS, 8);

    var window = c.glfwCreateWindow(800, 600, c"Mandelbrot Set", null, null) orelse return error.GlfwCreateWindowFailed;
    defer c.glfwDestroyWindow(window);

    const app = &application;
    c.glfwSetWindowUserPointer(window, app);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    // create and bind exactly one vertex array per context and use
    // glVertexAttribPointer etc every frame.
    var vertex_array_object: c.GLuint = undefined;
    c.glGenVertexArrays(1, &vertex_array_object);
    c.glBindVertexArray(vertex_array_object);
    defer c.glDeleteVertexArrays(1, &vertex_array_object);

    {
        // Returns the previous callback or null
        _ = c.glfwSetFramebufferSizeCallback(window, framebufferResizeCallback);
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(window, &width, &height);
        app.framebuffer_width = @intCast(u31, width);
        app.framebuffer_height = @intCast(u31, height);
    }

    app.all_shaders = try AllShaders.init();
    defer app.all_shaders.deinit();

    app.static_geometry = StaticGeometry.init();
    defer app.static_geometry.deinit();

    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

    resetProjection(app);

    debug_gl.assertNoError();

    //drawFrame(&app);
    c.glfwSwapBuffers(window);

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        c.glfwPollEvents();
    }

    debug_gl.assertNoError();
}

fn resetProjection(app: *App) void {
    app.projection = math3d.mat4x4Ortho(
        0.0,
        @intToFloat(f32, app.framebuffer_width),
        @intToFloat(f32, app.framebuffer_height),
        0.0,
    );
    c.glViewport(0, 0, app.framebuffer_width, app.framebuffer_height);
}

fn drawFrame(app: *App) void {
    const char_left = @intToFloat(f32, left) + @intToFloat(f32, i * font_char_width) * size;
    const model = mat4x4_identity.translate(char_left, @intToFloat(f32, top), 0.0).scale(size, size, 0.0);
    const mvp = app.projection.mult(model);

    app.font.draw(app.all_shaders, col, mvp);

    const as = &app.all_shaders;
    as.texture.bind();
    as.texture.setUniformMat4x4(as.texture_uniform_mvp, mvp);
    as.texture.setUniformInt(as.texture_uniform_tex, 0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, s.vertex_buffer);
    c.glEnableVertexAttribArray(@intCast(c.GLuint, as.texture_attrib_position));
    c.glVertexAttribPointer(@intCast(c.GLuint, as.texture_attrib_position), 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, s.tex_coord_buffers[index]);
    c.glEnableVertexAttribArray(@intCast(c.GLuint, as.texture_attrib_tex_coord));
    c.glVertexAttribPointer(@intCast(c.GLuint, as.texture_attrib_tex_coord), 2, c.GL_FLOAT, c.GL_FALSE, 0, null);

    c.glActiveTexture(c.GL_TEXTURE0);
    c.glBindTexture(c.GL_TEXTURE_2D, s.texture_id);

    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
}
