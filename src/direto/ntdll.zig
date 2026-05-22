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

    // peb + 0x18 = Ldr (PPEB_LDR_DATA)
    const ldr_ptr = @as(*usize, @ptrFromInt(peb + 0x18));
    const ldr = ldr_ptr.*;
    if (ldr == 0) return 0;

    // ldr + 0x20 = InMemoryOrderModuleList.Flink
    const head_ptr = @as(*usize, @ptrFromInt(ldr + 0x20));
    const head = head_ptr.*;
    if (head == 0) return 0;

    var current = @as(*usize, @ptrFromInt(head)).*;

    while (current != head and current != 0) {
        // InMemoryOrderModuleList entry is offset by 0x10 from the start of LDR_DATA_TABLE_ENTRY
        const entry_base = current - 0x10;

        // BaseDllName is at entry_base + 0x58 (UNICODE_STRING)
        // Length (2 bytes) at 0x58, MaximumLength (2 bytes) at 0x5A, Buffer (pointer) at 0x60
        const name_len_ptr = @as(*u16, @ptrFromInt(entry_base + 0x58));
        const name_len = name_len_ptr.*;
        
        const name_buf_ptr = @as(*usize, @ptrFromInt(entry_base + 0x60));
        const name_buf = name_buf_ptr.*;

        if (name_len > 0 and name_buf != 0) {
            const name_slice = @as([*]u16, @ptrFromInt(name_buf))[0 .. name_len / 2];
            
            // Check if it's ntdll.dll (case insensitive)
            const expected = [_]u16{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' };
            if (name_slice.len == expected.len) {
                var is_ntdll = true;
                for (expected, 0..) |c, i| {
                    const uc = name_slice[i];
                    // Very simple case insensitive check for a-z
                    var lc = uc;
                    if (uc >= 'A' and uc <= 'Z') {
                        lc = uc + 32;
                    }
                    if (lc != c) {
                        is_ntdll = false;
                        break;
                    }
                }
                
                if (is_ntdll) {
                    // DllBase is at entry_base + 0x30
                    const dll_base_ptr = @as(*usize, @ptrFromInt(entry_base + 0x30));
                    return dll_base_ptr.*;
                }
            }
        }

        // Flink is the first member of LIST_ENTRY, so current points to the next Flink
        current = @as(*usize, @ptrFromInt(current)).*;
    }

    return 0;
}
