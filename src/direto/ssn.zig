const std = @import("std");

fn readCString(addr: usize) []const u8 {
    var len: usize = 0;
    while (@as(*u8, @ptrFromInt(addr + len)).* != 0) : (len += 1) {}
    return @as([*]const u8, @ptrFromInt(addr))[0..len];
}

/// Check if a function at the given address is an unhooked syscall stub.
/// Unhooked stubs start with: mov r10, rcx (0x4C 0x8B 0xD1) followed by mov eax, SSN (0xB8 XX XX)
fn isUnhookedStub(addr: usize) bool {
    const b = @as(*[4]u8, @ptrFromInt(addr));
    return b[0] == 0x4C and b[1] == 0x8B and b[2] == 0xD1 and b[3] == 0xB8;
}

/// Read the SSN from an unhooked stub at offset +4 (little-endian u16)
fn readSSN(addr: usize) u16 {
    return @as(*align(1) u16, @ptrFromInt(addr + 4)).*;
}

pub fn extractSSN(func_addr: usize, ntdll_base: usize, export_dir: usize) u16 {
    // Fast path: the function is unhooked, just read the SSN directly
    if (isUnhookedStub(func_addr)) {
        return readSSN(func_addr);
    }
    return hellsGate(func_addr, ntdll_base, export_dir);
}

/// HellsGate "halo" approach:
/// 1. Find the nearest unhooked Nt function ABOVE the hooked target in memory.
/// 2. Count how many syscall stubs exist between that neighbor and the target
///    (by scanning for the 0x4C 0x8B 0xD1 0xB8 pattern at each expected stub position).
/// 3. target SSN = neighbor_ssn + count_of_stubs_between
/// 4. Fallback: try reading the SSN directly from the hooked function (hook may have
///    overwritten only the first few bytes, leaving the SSN at offset 4 intact).
fn hellsGate(hooked_addr: usize, ntdll_base: usize, export_dir: usize) u16 {
    const num_names = @as(*u32, @ptrFromInt(export_dir + 0x18)).*;
    const addr_of_names = ntdll_base + @as(*u32, @ptrFromInt(export_dir + 0x20)).*;
    const addr_of_functions = ntdll_base + @as(*u32, @ptrFromInt(export_dir + 0x1C)).*;
    const addr_of_name_ordinals = ntdll_base + @as(*u32, @ptrFromInt(export_dir + 0x24)).*;

    // Collect all Nt function addresses (both hooked and unhooked) so we can
    // find the nearest unhooked neighbor and count stubs between it and the target.
    var best_neighbor_addr: usize = 0;
    var best_neighbor_ssn: u16 = 0;
    var best_neighbor_diff: usize = std.math.maxInt(usize);

    // We need to scan stubs between neighbor and target. To do this properly,
    // we collect all Nt function addresses first, sort them, then walk from
    // the neighbor toward the target counting stub patterns.

    // Collect all Nt* function addresses into a stack buffer
    var nt_addrs: [512]struct { addr: usize, unhooked: bool, ssn: u16 } = undefined;
    var nt_count: usize = 0;

    for (0..num_names) |i| {
        if (nt_count >= 512) break;
        const name_rva = @as(*u32, @ptrFromInt(addr_of_names + i * 4)).*;
        const name = readCString(ntdll_base + name_rva);
        if (name.len < 3 or name[0] != 'N' or name[1] != 't') continue;

        const ordinal = @as(*u16, @ptrFromInt(addr_of_name_ordinals + i * 2)).*;
        const func_rva = @as(*u32, @ptrFromInt(addr_of_functions + ordinal * 4)).*;
        const func_addr = ntdll_base + func_rva;

        const unhooked = isUnhookedStub(func_addr);
        const ssn: u16 = if (unhooked) readSSN(func_addr) else 0;

        nt_addrs[nt_count] = .{ .addr = func_addr, .unhooked = unhooked, .ssn = ssn };
        nt_count += 1;

        // Track the nearest unhooked function ABOVE our target
        if (unhooked and func_addr < hooked_addr) {
            const diff = hooked_addr - func_addr;
            if (diff < best_neighbor_diff) {
                best_neighbor_diff = diff;
                best_neighbor_addr = func_addr;
                best_neighbor_ssn = ssn;
            }
        }
    }

    // Sort by address (simple insertion sort — small N, no allocations needed)
    var i_sorted: usize = 1;
    while (i_sorted < nt_count) : (i_sorted += 1) {
        var j: usize = i_sorted;
        while (j > 0 and nt_addrs[j].addr < nt_addrs[j - 1].addr) {
            const tmp = nt_addrs[j];
            nt_addrs[j] = nt_addrs[j - 1];
            nt_addrs[j - 1] = tmp;
            j -= 1;
        }
    }

    if (best_neighbor_addr != 0) {
        // Count actual syscall stubs between the neighbor and the target.
        // We scan the memory region from neighbor to target, looking for the
        // 0x4C 0x8B 0xD1 0xB8 pattern at each position.
        var stub_count: u16 = 0;
        var scan_addr = best_neighbor_addr;
        // Don't count the neighbor itself; start from the next stub position.
        // Syscall stubs are typically ~0x20 bytes apart, but we scan byte-by-byte
        // looking for the pattern to be robust against different layouts.
        scan_addr += 1; // Move past the neighbor's first byte to avoid counting it

        while (scan_addr < hooked_addr) {
            if (isUnhookedStub(scan_addr)) {
                stub_count += 1;
                // Skip past this stub's header (skip the mov r10,rcx + mov eax,SSN = 6 bytes min)
                scan_addr += 6;
            } else {
                scan_addr += 1;
            }
        }
        return best_neighbor_ssn + stub_count;
    }

    // Fallback: try reading SSN directly from the hooked function.
    // Some hooks (e.g., jmp to detour) overwrite only the first 2-5 bytes,
    // leaving the 0xB8 XX XX (mov eax, SSN) intact at offset 4.
    // Check if bytes at offset 3-4 look like 0xB8 followed by a valid-looking SSN.
    const b3 = @as(*u8, @ptrFromInt(hooked_addr + 3)).*;
    if (b3 == 0xB8) {
        return @as(*align(1) u16, @ptrFromInt(hooked_addr + 4)).*;
    }
    // Also check offset 4 directly in case the hook is exactly 4 bytes (e.g., jmp short)
    const b4 = @as(*u8, @ptrFromInt(hooked_addr + 4)).*;
    if (b4 == 0xB8) {
        return @as(*align(1) u16, @ptrFromInt(hooked_addr + 5)).*;
    }

    return 0;
}

pub fn resolveSingleSSN(base: usize, func_name: []const u8) u16 {
    const e_lfanew = @as(*u32, @ptrFromInt(base + 0x3C)).*;
    const nt_headers = base + e_lfanew;
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
        const name = readCString(base + name_rva);
        if (std.mem.eql(u8, name, func_name)) {
            const ordinal = @as(*u16, @ptrFromInt(addr_of_name_ordinals + i * 2)).*;
            const func_rva = @as(*u32, @ptrFromInt(addr_of_functions + ordinal * 4)).*;
            return extractSSN(base + func_rva, base, export_dir);
        }
    }
    return 0;
}
