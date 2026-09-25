const std = @import("std");

/// Length of a UTF-8 sequence given its first byte (invalid bytes count as 1).
pub fn utf8SeqLen(b: u8) usize {
    if (b < 0x80) return 1;
    if (b >= 0xF0) return 4;
    if (b >= 0xE0) return 3;
    if (b >= 0xC0) return 2;
    return 1;
}

/// Return the farthest index at or beyond `limit` that ends on a complete unit:
/// a full JSON escape sequence (`\x` or `\uXXXX`) or a complete UTF-8
/// character. Always advances by at least one unit, so it never splits an
/// escape or a codepoint (it may exceed `limit` by up to one unit).
pub fn safeCut(escaped: []const u8, start: usize, limit: usize) usize {
    if (start >= escaped.len) return start;
    var i = start;
    var last_safe = start;
    while (i < escaped.len) {
        const c = escaped[i];
        var next: usize = i + 1;
        if (c == '\\') {
            if (i + 1 < escaped.len) {
                next = if (escaped[i + 1] == 'u' and i + 6 <= escaped.len) i + 6 else i + 2;
            }
        } else if (c >= 0x80) {
            next = @min(i + utf8SeqLen(c), escaped.len);
        }
        last_safe = next;
        i = next;
        if (next >= limit) break;
    }
    return last_safe;
}

/// Escape a byte string for embedding inside a JSON string literal.
/// Valid UTF-8 sequences pass through; invalid bytes are escaped as `\u00XX`
/// so the resulting document is always parseable JSON.
pub fn escape(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const hex = "0123456789abcdef";

    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c >= 0x80) {
            const seq_len = std.unicode.utf8ByteSequenceLength(c) catch {
                try appendHexByte(allocator, &out, hex, c);
                i += 1;
                continue;
            };
            if (i + seq_len <= s.len and std.unicode.utf8ValidateSlice(s[i .. i + seq_len])) {
                try out.appendSlice(allocator, s[i .. i + seq_len]);
                i += seq_len;
            } else {
                try appendHexByte(allocator, &out, hex, c);
                i += 1;
            }
            continue;
        }

        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            0x08 => try out.appendSlice(allocator, "\\b"),
            0x0C => try out.appendSlice(allocator, "\\f"),
            else => {
                if (c < 0x20) {
                    try appendHexByte(allocator, &out, hex, c);
                } else {
                    try out.append(allocator, c);
                }
            },
        }
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn appendHexByte(allocator: std.mem.Allocator, out: *std.ArrayList(u8), hex: []const u8, c: u8) !void {
    try out.appendSlice(allocator, "\\u00");
    try out.append(allocator, hex[(c >> 4) & 0x0F]);
    try out.append(allocator, hex[c & 0x0F]);
}

// ============================================================
//  Tests (run on the host: zig test src/json.zig)
// ============================================================

test "escape round-trips ASCII, controls and valid UTF-8" {
    const input = "quote:\" backslash:\\ newline:\n tab:\t bell:\x07 " ++
        "accent:é arrow:→ emoji:🦀";
    const escaped = try escape(std.testing.allocator, input);
    defer std.testing.allocator.free(escaped);

    const doc = try std.fmt.allocPrint(std.testing.allocator, "{{\"content\": \"{s}\"}}", .{escaped});
    defer std.testing.allocator.free(doc);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, doc, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings(input, parsed.value.object.get("content").?.string);
}

test "escape keeps invalid UTF-8 parseable" {
    const input = [_]u8{ 0xFF, 0xFE, 'a', 0x80 };
    const escaped = try escape(std.testing.allocator, &input);
    defer std.testing.allocator.free(escaped);

    const doc = try std.fmt.allocPrint(std.testing.allocator, "{{\"content\": \"{s}\"}}", .{escaped});
    defer std.testing.allocator.free(doc);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, doc, .{});
    defer parsed.deinit();
    _ = parsed.value.object.get("content").?;
}

test "escape keeps backticks literal (valid JSON)" {
    const escaped = try escape(std.testing.allocator, "a`b");
    defer std.testing.allocator.free(escaped);
    try std.testing.expectEqualStrings("a`b", escaped);
}

test "safeCut never splits an escape sequence" {
    const s = "\\u0041\\nX"; // literal: \ u 0 0 4 1 \ n X
    try std.testing.expectEqual(@as(usize, 6), safeCut(s, 0, 4));
    try std.testing.expectEqual(@as(usize, 6), safeCut(s, 0, 6));
    try std.testing.expectEqual(@as(usize, 8), safeCut(s, 0, 7));
    try std.testing.expectEqual(@as(usize, 9), safeCut(s, 0, 100));
}

test "safeCut never splits a multibyte UTF-8 char" {
    const s = "ab\xC3\xA9z"; // "abéz"
    try std.testing.expectEqual(@as(usize, 4), safeCut(s, 0, 3));
    try std.testing.expectEqual(@as(usize, 4), safeCut(s, 0, 4));
    try std.testing.expectEqual(@as(usize, 5), safeCut(s, 0, 5));
}
