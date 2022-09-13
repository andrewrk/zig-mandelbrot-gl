const c = @import("c.zig").c;
const std = @import("std");
const panic = std.debug.panic;

pub const is_on = if (std.debug.runtime_safety) c.GL_TRUE else c.GL_FALSE;

pub fn assertNoError() void {
    if (std.debug.runtime_safety) {
        const err = c.glGetError();
        if (err != c.GL_NO_ERROR) {
            // _ = err;
            panic("GL error: {}\n", .{err});
        }
    }
}
