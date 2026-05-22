const std = @import("std");

const DATA_BLOB = extern struct {
    cbData: u32,
    pbData: [*]u8,
};

extern "crypt32" fn CryptUnprotectData(
    pDataIn: *const DATA_BLOB,
    ppszDataDescr: ?*?[*]u16,
    pOptionalEntropy: ?*const DATA_BLOB,
    pvReserved: ?*anyopaque,
    pPromptStruct: ?*anyopaque,
    dwFlags: u32,
    pDataOut: *DATA_BLOB,
) callconv(.C) c_int;

extern "kernel32" fn LocalFree(hMem: [*]u8) callconv(.C) ?*anyopaque;

pub fn unprotectData(allocator: std.mem.Allocator, encrypted_data: []const u8) ![]u8 {
    if (encrypted_data.len == 0) return error.EmptyData;

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

    var plaintext = try allocator.alloc(u8, ciphertext.len);
    errdefer allocator.free(plaintext);

    // Using Zig's standard library for AES-GCM
    const cipher = std.crypto.aead.aes_gcm.Aes256Gcm;
    
    // In Chromium, the payload has the tag appended at the end (last 16 bytes)
    if (ciphertext.len < 16) return error.CiphertextTooShort;
    const actual_ciphertext = ciphertext[0..ciphertext.len - 16];
    const tag = ciphertext[ciphertext.len - 16..][0..16];

    try cipher.decrypt(plaintext[0..actual_ciphertext.len], actual_ciphertext, tag.*, "", iv, key);
    return plaintext[0..actual_ciphertext.len];
}
