const Builder = @import("std").build.Builder;
const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("mandelbrot", "src/main.zig");
    exe.setBuildMode(mode);

    // mac
    if (builtin.target.os.tag == .macos) {
        const library_path = std.os.getenv("LIBRARY_PATH") orelse null;
        const include_path = std.os.getenv("CPATH") orelse null;
        if (library_path != null and include_path != null) {
            exe.addLibPath(library_path.?);
            exe.addIncludeDir(include_path.?);
        }
    }

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("epoxy");

    const run_cmd = exe.run();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
