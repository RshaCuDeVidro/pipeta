const std = @import("std");
const builtin = @import("builtin");

pub inline fn getPEB() usize {
    if (builtin.cpu.arch == .x86_64) {
        return asm ("movq %%gs:0x60, %[ret]"
            : [ret] "=r" (-> usize),
        );
    } else if (builtin.cpu.arch == .x86) {
        return asm ("movl %%fs:0x30, %[ret]"
            : [ret] "=r" (-> usize),
        );
    } else {
        @compileError("Unsupported architecture for getPEB");
    }
}

pub fn findNtdllBase() usize {
    const peb = getPEB();
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
            const expected = [_]u16{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' };
            if (name_slice.len == expected.len) {
                var is_ntdll = true;
                for (expected, 0..) |c, i| {
                    const uc = name_slice[i];
                    var lc = uc;
                    if (uc >= 'A' and uc <= 'Z') lc = uc + 32;
                    if (lc != c) { is_ntdll = false; break; }
                }
                if (is_ntdll) {
                    const dll_base_ptr = @as(*usize, @ptrFromInt(entry_base + 0x30));
                    return dll_base_ptr.*;
                }
            }
        }
        current = @as(*usize, @ptrFromInt(current)).*;
    }
    return 0;
}

/// Find a `syscall; ret` gadget (0x0F 0x05 0xC3) inside ntdll .text section.
/// Used for indirect syscalls so the syscall instruction executes from ntdll,
/// not from our own binary. Cached so the scan only happens once.
var cached_gadget: usize = 0;
var gadget_scanned: bool = false;

pub fn findSyscallGadget() usize {
    if (gadget_scanned) return cached_gadget;
    gadget_scanned = true;

    const base = findNtdllBase();
    if (base == 0) return 0;

    // Parse PE headers to find .text section bounds
    const e_lfanew = @as(*u32, @ptrFromInt(base + 0x3C)).*;
    const nt_headers = base + e_lfanew;
    const num_sections = @as(*u16, @ptrFromInt(nt_headers + 0x06)).*;
    const size_of_optional_header = @as(*u16, @ptrFromInt(nt_headers + 0x14)).*;
    const section_table = nt_headers + 0x18 + size_of_optional_header;

    var i: usize = 0;
    while (i < num_sections) : (i += 1) {
        const sec = section_table + i * 40;
        const name_ptr = @as(*[8]u8, @ptrFromInt(sec));
        // .text\0\0\0
        if (name_ptr[0] == '.' and name_ptr[1] == 't' and name_ptr[2] == 'e' and
            name_ptr[3] == 'x' and name_ptr[4] == 't' and name_ptr[5] == 0)
        {
            const virtual_size = @as(*u32, @ptrFromInt(sec + 0x08)).*;
            const virtual_addr = @as(*u32, @ptrFromInt(sec + 0x0C)).*;
            const text_start = base + virtual_addr;
            const text_end = text_start + virtual_size;

            // Scan for 0x0F 0x05 0xC3 (syscall; ret)
            var addr = text_start;
            while (addr + 2 < text_end) : (addr += 1) {
                const b = @as(*[3]u8, @ptrFromInt(addr));
                if (b[0] == 0x0F and b[1] == 0x05 and b[2] == 0xC3) {
                    cached_gadget = addr;
                    return addr;
                }
            }
            break;
        }
    }
    return 0;
}
