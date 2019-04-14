const std = @import("std");
const c = @import("c.zig");
const panic = std.debug.panic;
const assert = std.debug.assert;
const debug_gl = @import("./debug_gl.zig");
const StaticGeometry = @import("static_geometry.zig").StaticGeometry;
const AllShaders = @import("all_shaders.zig").AllShaders;
const math3d = @import("math3d.zig");
const Mat4x4 = math3d.Mat4x4;
const mat4x4_identity = math3d.mat4x4_identity;

const App = struct {
    window: *c.GLFWwindow,
    all_shaders: AllShaders,
    static_geometry: StaticGeometry,
    projection: Mat4x4,
    framebuffer_width: u31,
    framebuffer_height: u31,
    image: Image,
};
var application: App = undefined;
var img_buf: []u8 = [0]u8{};

extern fn errorCallback(err: c_int, description: [*c]const u8) void {
    panic("Error: {}\n", description);
}

extern fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
    if (action != c.GLFW_PRESS) return;

    switch (key) {
        c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(window, c.GL_TRUE),
        c.GLFW_KEY_SPACE => renderFrame(&application),
        else => {},
    }
}

extern fn framebufferResizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const app = &application;
    app.framebuffer_width = @intCast(u31, width);
    app.framebuffer_height = @intCast(u31, height);
    resetProjection(app);
}

pub fn main() anyerror!void {
    const app = &application;

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

    app.window = c.glfwCreateWindow(800, 600, c"Mandelbrot Set", null, null) orelse return error.GlfwCreateWindowFailed;
    defer c.glfwDestroyWindow(app.window);

    c.glfwSetWindowUserPointer(app.window, app);

    _ = c.glfwSetKeyCallback(app.window, keyCallback);
    {
        // Returns the previous callback or null
        _ = c.glfwSetFramebufferSizeCallback(app.window, framebufferResizeCallback);
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(app.window, &width, &height);
        app.framebuffer_width = @intCast(u31, width);
        app.framebuffer_height = @intCast(u31, height);
    }

    c.glfwMakeContextCurrent(app.window);
    c.glfwSwapInterval(1);

    // create and bind exactly one vertex array per context and use
    // glVertexAttribPointer etc every frame.
    var vertex_array_object: c.GLuint = undefined;
    c.glGenVertexArrays(1, &vertex_array_object);
    c.glBindVertexArray(vertex_array_object);
    defer c.glDeleteVertexArrays(1, &vertex_array_object);

    app.all_shaders = try AllShaders.init();
    defer app.all_shaders.deinit();

    app.static_geometry = StaticGeometry.init();
    defer app.static_geometry.deinit();

    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

    app.image = try Image.init(app.framebuffer_width, app.framebuffer_height);

    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    debug_gl.assertNoError();

    resetProjection(app);

    debug_gl.assertNoError();

    while (c.glfwWindowShouldClose(app.window) == c.GL_FALSE) {
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

        c.glfwPollEvents();
        drawFrame(app);
        c.glfwSwapBuffers(app.window);
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
    app.image.deinit();
    app.image = Image.init(app.framebuffer_width, app.framebuffer_height) catch @panic("unable to create image");
    const bytes_len = 4 * app.framebuffer_width * app.framebuffer_height;
    img_buf = std.heap.c_allocator.realloc(img_buf, bytes_len) catch @panic("unable to realloc image buffer");
    renderFrame(app);
}

const Image = struct {
    texture_id: c.GLuint,
    vertex_buffer: c.GLuint,
    tex_coord_buffer: c.GLuint,
    width: u31,
    height: u31,

    fn init(w: u31, h: u31) anyerror!Image {
        var s = Image{
            .texture_id = undefined,
            .vertex_buffer = undefined,
            .tex_coord_buffer = undefined,
            .width = w,
            .height = h,
        };

        c.glGenTextures(1, &s.texture_id);
        errdefer c.glDeleteTextures(1, &s.texture_id);

        c.glBindTexture(c.GL_TEXTURE_2D, s.texture_id);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glPixelStorei(c.GL_PACK_ALIGNMENT, 4);

        c.glGenBuffers(1, &s.vertex_buffer);
        errdefer c.glDeleteBuffers(1, &s.vertex_buffer);

        const vertexes = [][3]c.GLfloat{
            []c.GLfloat{ 0.0, 0.0, 0.0 },
            []c.GLfloat{ 0.0, @intToFloat(c.GLfloat, h), 0.0 },
            []c.GLfloat{ @intToFloat(c.GLfloat, w), 0.0, 0.0 },
            []c.GLfloat{ @intToFloat(c.GLfloat, w), @intToFloat(c.GLfloat, h), 0.0 },
        };

        c.glBindBuffer(c.GL_ARRAY_BUFFER, s.vertex_buffer);
        c.glBufferData(c.GL_ARRAY_BUFFER, 4 * 3 * @sizeOf(c.GLfloat), &vertexes[0][0], c.GL_STATIC_DRAW);

        c.glGenBuffers(1, &s.tex_coord_buffer);
        errdefer c.glDeleteBuffers(1, &s.tex_coord_buffer);

        const img_w = @intToFloat(f32, s.width);
        const img_h = @intToFloat(f32, s.height);
        const tex_coords = [][2]c.GLfloat{
            []c.GLfloat{ 0, 0 },
            []c.GLfloat{ 0, 1 },
            []c.GLfloat{ 1, 0 },
            []c.GLfloat{ 1, 1 },
        };

        c.glBindBuffer(c.GL_ARRAY_BUFFER, s.tex_coord_buffer);
        c.glBufferData(c.GL_ARRAY_BUFFER, 4 * 2 * @sizeOf(c.GLfloat), &tex_coords[0][0], c.GL_STATIC_DRAW);

        return s;
    }

    fn deinit(s: *Image) void {
        c.glDeleteBuffers(1, &s.tex_coord_buffer);
        c.glDeleteBuffers(1, &s.vertex_buffer);
        c.glDeleteTextures(1, &s.texture_id);
        s.* = undefined;
    }

    fn update(s: *Image, data: []const u8) void {
        assert(data.len == s.width * s.height * 4);

        c.glBindTexture(c.GL_TEXTURE_2D, s.texture_id);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            s.width,
            s.height,
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            data.ptr,
        );
    }

    fn draw(s: *Image, as: AllShaders, mvp: Mat4x4) void {
        as.texture.bind();
        as.texture.setUniformMat4x4(as.texture_uniform_mvp, mvp);
        as.texture.setUniformInt(as.texture_uniform_tex, 0);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, s.vertex_buffer);
        c.glEnableVertexAttribArray(@intCast(c.GLuint, as.texture_attrib_position));
        c.glVertexAttribPointer(@intCast(c.GLuint, as.texture_attrib_position), 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, s.tex_coord_buffer);
        c.glEnableVertexAttribArray(@intCast(c.GLuint, as.texture_attrib_tex_coord));
        c.glVertexAttribPointer(@intCast(c.GLuint, as.texture_attrib_tex_coord), 2, c.GL_FLOAT, c.GL_FALSE, 0, null);

        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, s.texture_id);

        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }
};

fn renderFrame(app: *App) void {
    const row_len = app.framebuffer_width * 4;
    var y: u31 = 0;
    while (y < app.framebuffer_height) : (y += 1) {
        var x: u31 = 0;
        while (x < app.framebuffer_width) : (x += 1) {
            const pix_offset = y * row_len + x * 4;
            const y_scale = @intToFloat(f32, y) / @intToFloat(f32, app.framebuffer_height);
            const x_scale = @intToFloat(f32, x) / @intToFloat(f32, app.framebuffer_width);

            img_buf[pix_offset + 0] = @floatToInt(u8, 0xff * y_scale);
            img_buf[pix_offset + 1] = 0x00;
            img_buf[pix_offset + 2] = @floatToInt(u8, 0xff * x_scale);
            img_buf[pix_offset + 3] = 0xff;
        }
    }
    app.image.update(img_buf);
}

fn drawFrame(app: *App) void {
    const model = mat4x4_identity;
    const mvp = app.projection.mult(model);
    app.image.draw(app.all_shaders, mvp);
}
