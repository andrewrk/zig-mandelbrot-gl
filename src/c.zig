pub const c = struct {
    pub usingnamespace @cImport({
        @cInclude("epoxy/gl.h");
        @cInclude("GLFW/glfw3.h");
    });
};
