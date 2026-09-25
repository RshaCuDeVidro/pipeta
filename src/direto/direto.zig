const std = @import("std");
const builtin = @import("builtin");

comptime {
    // The indirect-syscall stubs below are x86_64-only (64-bit registers and
    // the Windows x64 syscall ABI). Fail loudly on other architectures.
    if (builtin.cpu.arch != .x86_64) {
        @compileError("pipeta supports x86_64 Windows targets only");
    }
}

pub const ntdll = @import("ntdll.zig");
pub const ssn = @import("ssn.zig");

pub inline fn getPEB() usize { return ntdll.getPEB(); }
pub fn resolveSSN(func_name: []const u8) u16 {
    const base = ntdll.findNtdllBase();
    if (base == 0) return 0;
    return ssn.resolveSingleSSN(base, func_name);
}

// Indirect syscall via the ntdll `syscall; ret` gadget.
//
// Layout note: at the moment `syscall` executes, RSP must be exactly as if a
// normal call had been made, so the kernel finds arg5/arg6 at [RSP+0x28] and
// [RSP+0x30]. We reserve 0x48 bytes, store arg5 at +0x20 and arg6 at +0x28,
// then `call` the gadget (which pushes 8 more bytes). The syscall number is
// written with `movl` so the upper 16 bits of EAX are guaranteed zero — using
// `movw` would leave the high bits of the gadget address in EAX.

pub inline fn syscall2(num: u16, arg1: usize, arg2: usize) usize {
    const gadget = ntdll.findSyscallGadget();
    if (gadget == 0) return 0xC0000000;
    var ret: usize = undefined;
    asm volatile (
        \\subq $0x48, %%rsp
        \\movq %[gadget], %%r11
        \\movq %[arg1], %%r10
        \\movq %[arg2], %%rdx
        \\movl %[num], %%eax
        \\callq *%%r11
        \\addq $0x48, %%rsp
        : [ret] "={rax}" (ret)
        : [num] "r" (@as(u32, num)), [arg1] "r" (arg1), [arg2] "r" (arg2), [gadget] "r" (gadget)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

pub inline fn syscall3(num: u16, arg1: usize, arg2: usize, arg3: usize) usize {
    const gadget = ntdll.findSyscallGadget();
    if (gadget == 0) return 0xC0000000;
    var ret: usize = undefined;
    asm volatile (
        \\subq $0x48, %%rsp
        \\movq %[gadget], %%r11
        \\movq %[arg1], %%r10
        \\movq %[arg2], %%rdx
        \\movq %[arg3], %%r8
        \\movl %[num], %%eax
        \\callq *%%r11
        \\addq $0x48, %%rsp
        : [ret] "={rax}" (ret)
        : [num] "r" (@as(u32, num)), [arg1] "r" (arg1), [arg2] "r" (arg2), [arg3] "r" (arg3), [gadget] "r" (gadget)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

pub inline fn syscall5(num: u16, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
    const gadget = ntdll.findSyscallGadget();
    if (gadget == 0) return 0xC0000000;
    var ret: usize = undefined;
    asm volatile (
        \\subq $0x48, %%rsp
        \\movq %[gadget], %%r11
        \\movq %[arg5], 0x20(%%rsp)
        \\movq %[arg1], %%r10
        \\movq %[arg2], %%rdx
        \\movq %[arg3], %%r8
        \\movq %[arg4], %%r9
        \\movl %[num], %%eax
        \\callq *%%r11
        \\addq $0x48, %%rsp
        : [ret] "={rax}" (ret)
        : [num] "r" (@as(u32, num)), [arg1] "r" (arg1), [arg2] "r" (arg2), [arg3] "r" (arg3), [arg4] "r" (arg4), [arg5] "r" (arg5), [gadget] "r" (gadget)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

pub inline fn syscall6(num: u16, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    const gadget = ntdll.findSyscallGadget();
    if (gadget == 0) return 0xC0000000;
    var ret: usize = undefined;
    asm volatile (
        \\subq $0x48, %%rsp
        \\movq %[gadget], %%r11
        \\movq %[arg5], 0x20(%%rsp)
        \\movq %[arg6], 0x28(%%rsp)
        \\movq %[arg1], %%r10
        \\movq %[arg2], %%rdx
        \\movq %[arg3], %%r8
        \\movq %[arg4], %%r9
        \\movl %[num], %%eax
        \\callq *%%r11
        \\addq $0x48, %%rsp
        : [ret] "={rax}" (ret)
        : [num] "r" (@as(u32, num)), [arg1] "r" (arg1), [arg2] "r" (arg2), [arg3] "r" (arg3), [arg4] "r" (arg4), [arg5] "r" (arg5), [arg6] "r" (arg6), [gadget] "r" (gadget)
        : .{ .rcx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .memory = true }
    );
    return ret;
}

pub const UnicodeString = extern struct { Length: u16, MaximumLength: u16, Buffer: [*]const u16 };
pub const ObjectAttributes = extern struct { Length: u32, RootDirectory: usize, ObjectName: *const UnicodeString, Attributes: u32, SecurityDescriptor: usize, SecurityQualityOfService: usize };

pub fn ntProtectVirtualMemory(handle: usize, base_addr: *usize, region_size: *usize, new_protect: usize, old_protect: *u32) usize {
    const num = resolveSSN("NtProtectVirtualMemory");
    if (num == 0) return 0xC0000000;
    return syscall5(num, handle, @intFromPtr(base_addr), @intFromPtr(region_size), new_protect, @intFromPtr(old_protect));
}

pub fn ntDelayExecution(milliseconds: i64) void {
    const num = resolveSSN("NtDelayExecution");
    if (num == 0) return;
    var delay: i64 = -milliseconds * 10000;
    // Alertable must be FALSE (0).
    _ = syscall2(num, 0, @intFromPtr(&delay));
}
