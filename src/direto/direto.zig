const std = @import("std");
pub const ntdll = @import("ntdll.zig");
pub const ssn = @import("ssn.zig");

pub inline fn getPEB() usize {
    return ntdll.getPEB();
}

pub fn resolveSSN(func_name: []const u8) u16 {
    const base = ntdll.findNtdllBase();
    if (base == 0) return 0;
    return ssn.resolveSingleSSN(base, func_name);
}

/// Executes a syscall with 2 arguments (Windows x64).
pub inline fn syscall2(num: u16, arg1: usize, arg2: usize) usize {
    return asm volatile (
        "syscall"
        : [ret] "={rax}" (-> usize),
        : [num] "{rax}" (num),
          [arg1] "{r10}" (arg1), // Windows syscall expects arg1 in r10
          [arg2] "{rdx}" (arg2),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
}

/// Executes a syscall with 3 arguments (Windows x64).
pub inline fn syscall3(num: u16, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile (
        "syscall"
        : [ret] "={rax}" (-> usize),
        : [num] "{rax}" (num),
          [arg1] "{r10}" (arg1),
          [arg2] "{rdx}" (arg2),
          [arg3] "{r8}" (arg3),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
}

/// Executes a syscall with 4 arguments (Windows x64).
pub inline fn syscall4(num: u16, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
    return asm volatile (
        "syscall"
        : [ret] "={rax}" (-> usize),
        : [num] "{rax}" (num),
          [arg1] "{r10}" (arg1),
          [arg2] "{rdx}" (arg2),
          [arg3] "{r8}" (arg3),
          [arg4] "{r9}" (arg4),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
}

/// Executes a syscall with 5 arguments (Windows x64).
pub inline fn syscall5(num: u16, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
    // 5th arg and beyond are passed on the stack.
    // However, inline assembly with stack arguments is tricky in Zig.
    // The typical x64 syscall convention: rcx (r10), rdx, r8, r9, then stack.
    // Let's implement a small naked function or properly push to stack.
    // A simpler way is to just call a wrapper or build the frame.
    // For NtProtectVirtualMemory, we need 5 arguments.
    // Since Zig 0.11+, we can't easily push in inline asm without upsetting the compiler's stack awareness.
    // Let's use a function that correctly sets up the stack.
    var ret: usize = undefined;
    asm volatile (
        \\ subq $0x38, %%rsp
        \\ movq %[arg5], 0x28(%%rsp)
        \\ movq %[arg1], %%r10
        \\ movq %[arg2], %%rdx
        \\ movq %[arg3], %%r8
        \\ movq %[arg4], %%r9
        \\ movw %[num], %%ax
        \\ syscall
        \\ addq $0x38, %%rsp
        : [ret] "={rax}" (ret)
        : [num] "r" (num),
          [arg1] "r" (arg1),
          [arg2] "r" (arg2),
          [arg3] "r" (arg3),
          [arg4] "r" (arg4),
          [arg5] "r" (arg5)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

pub fn ntProtectVirtualMemory(handle: usize, base_addr: *usize, region_size: *usize, new_protect: usize, old_protect: *u32) usize {
    const num = resolveSSN("NtProtectVirtualMemory");
    if (num == 0) return 0xC0000000;
    return syscall5(num, handle, @intFromPtr(base_addr), @intFromPtr(region_size), new_protect, @intFromPtr(old_protect));
}

/// Executes a syscall with 6 arguments (Windows x64).
pub inline fn syscall6(num: u16, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    var ret: usize = undefined;
    asm volatile (
        \\ subq $0x38, %%rsp
        \\ movq %[arg5], 0x28(%%rsp)
        \\ movq %[arg6], 0x30(%%rsp)
        \\ movq %[arg1], %%r10
        \\ movq %[arg2], %%rdx
        \\ movq %[arg3], %%r8
        \\ movq %[arg4], %%r9
        \\ movw %[num], %%ax
        \\ syscall
        \\ addq $0x38, %%rsp
        : [ret] "={rax}" (ret)
        : [num] "r" (num),
          [arg1] "r" (arg1),
          [arg2] "r" (arg2),
          [arg3] "r" (arg3),
          [arg4] "r" (arg4),
          [arg5] "r" (arg5),
          [arg6] "r" (arg6)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

pub const UnicodeString = extern struct {
    Length: u16,
    MaximumLength: u16,
    Buffer: [*]const u16,
};

pub const ObjectAttributes = extern struct {
    Length: u32,
    RootDirectory: usize,
    ObjectName: *const UnicodeString,
    Attributes: u32,
    SecurityDescriptor: usize,
    SecurityQualityOfService: usize,
};

pub fn ntOpenKey(root_key: usize, obj_attrs: *const ObjectAttributes) usize {
    _ = root_key;
    const num = resolveSSN("NtOpenKey");
    if (num == 0) return 0;
    
    var handle: usize = 0;
    const status = syscall3(num, @intFromPtr(&handle), 0xF003F, @intFromPtr(obj_attrs));
    if (status != 0) return 0;
    return handle;
}

pub fn ntSetValueKey(key_handle: usize, value_name: *const UnicodeString, dtype: u32, data: usize, data_size: usize) usize {
    const num = resolveSSN("NtSetValueKey");
    if (num == 0) return 0xC0000000;
    return syscall6(num, key_handle, @intFromPtr(value_name), 0, dtype, data, data_size);
}

pub fn ntDelayExecution(milliseconds: i64) void {
    const num = resolveSSN("NtDelayExecution");
    if (num == 0) return;
    
    var delay: i64 = -milliseconds * 10000;
    _ = syscall2(num, 2, @intFromPtr(&delay));
}
